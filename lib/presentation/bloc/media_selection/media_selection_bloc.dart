import 'dart:collection';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_thumbnail_video/index.dart' show ImageFormat;
import 'package:image_picker/image_picker.dart';
import 'package:ism_video_reel_player/presentation/screens/media/media_edit/model/media_edit_audio_model.dart';
import 'package:ism_video_reel_player/presentation/screens/media/media_selection/media_selection_config.dart';
import 'package:ism_video_reel_player/presentation/screens/media/media_selection/model/media_asset_data.dart';
import 'package:ism_video_reel_player/utils/utils.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart' as pm;
import 'package:video_compress/video_compress.dart';

part 'media_selection_event.dart';
part 'media_selection_state.dart';

class MediaSelectionBloc
    extends Bloc<MediaSelectionEvent, MediaSelectionState> {
  MediaSelectionBloc() : super(MediaSelectionInitialState()) {
    on<MediaSelectionInitialEvent>(_onInitial);
    on<RequestPermissionEvent>(_onRequestPermission);
    on<LoadAlbumsEvent>(_onLoadAlbums);
    on<LoadMediaEvent>(_onLoadMedia);
    on<SelectAlbumEvent>(_onSelectAlbum);
    on<SelectMediaEvent>(_onSelectMedia);
    on<DeselectMediaEvent>(_onDeselectMedia);
    on<ToggleSelectModeEvent>(_onToggleSelectMode);
    on<LoadMoreMediaEvent>(_onLoadMoreMedia);
    on<CaptureMediaEvent>(_onCaptureMedia);
    on<ProcessCapturedMediaEvent>(_onProcessCapturedMedia);
    on<ProceedToEditFilterEvent>(_onProceedToEditFilter);
  }

  // State variables
  MediaSelectionConfig? _config;
  final List<MediaAssetData> _selectedMedia = [];
  final List<MediaAssetData> _media = [];
  final List<pm.AssetPathEntity> _albums = [];
  pm.AssetPathEntity? _currentAlbum;
  bool _isMultiSelectMode = false;
  int _currentPage = 0;
  bool _isProcessingSelection = false;
  bool _hasMore = true;
  bool _isLoadingPage = false;
  bool _isPreparingSelection = false;

  /// Bumped on every fresh (non load-more) load so stale page results are dropped.
  int _loadGeneration = 0;

  /// Gallery assets backing [_media], keyed by [MediaAssetData.assetId].
  final Map<String, pm.AssetEntity> _assetsById = {};

  // Grid thumbnails kept in memory (LRU, bounded by total bytes).
  static const int _maxGridThumbnailBytes = 40 * 1024 * 1024;
  final LinkedHashMap<String, Uint8List> _gridThumbnailCache = LinkedHashMap();
  final Map<String, Future<Uint8List?>> _gridThumbnailInFlight = {};
  int _gridThumbnailBytes = 0;

  // Video thumbnail cache for non-gallery media (captured / preselected).
  final Map<String, String> _thumbnailCache = {};
  final Map<String, Uint8List> _assetThumbnailCache = {};
  final Set<String> _thumbnailGenerationInProgress = {};
  final Set<String> _assetThumbnailGenerationInProgress = {};
  final int _maxConcurrentThumbnails = 3;
  final int _maxConcurrentAssetThumbnails = 6;

  Future<void> _onInitial(
    MediaSelectionInitialEvent event,
    Emitter<MediaSelectionState> emit,
  ) async {
    _config = event.config;
    if (event.selectedMedia != null) {
      _selectedMedia.addAll(event.selectedMedia!);
    }
    add(const RequestPermissionEvent(openSettingsIfDenied: false));
  }

  Future<void> _onRequestPermission(
    RequestPermissionEvent event,
    Emitter<MediaSelectionState> emit,
  ) async {
    if (event.silentRecheck) {
      final ps = await pm.PhotoManager.getPermissionState(
        requestOption: const pm.PermissionRequestOption(),
      );
      if (ps.isAuth) {
        emit(MediaSelectionLoadingState());
        add(LoadAlbumsEvent());
      }
      // Still denied: keep current denied UI. Do not re-request (that loops).
      return;
    }

    // User tapped "Open Settings" from the denied screen — open settings only.
    // Do not call requestPermissionExtend again (triggers pause/resume loop).
    if (event.openSettingsIfDenied &&
        state is MediaSelectionPermissionDeniedState) {
      await pm.PhotoManager.openSetting();
      return;
    }

    emit(MediaSelectionLoadingState());
    final ps = await pm.PhotoManager.requestPermissionExtend();
    if (ps.isAuth) {
      // Stay in loading state until albums + first page of media are loaded
      add(LoadAlbumsEvent());
    } else {
      if (event.openSettingsIfDenied) {
        await pm.PhotoManager.openSetting();
      }
      emit(MediaSelectionPermissionDeniedState());
    }
  }

  Future<void> _onLoadAlbums(
    LoadAlbumsEvent event,
    Emitter<MediaSelectionState> emit,
  ) async {
    if (_config == null) return;

    try {
      _albums.clear();

      // Load all three album types in parallel for faster startup.
      // Each call gets its own filter instance; photo_manager may mutate it.
      final results = await Future.wait([
        pm.PhotoManager.getAssetPathList(
          type: pm.RequestType.common,
          hasAll: true,
          onlyAll: true,
          filterOption: _galleryFilter(),
        ),
        pm.PhotoManager.getAssetPathList(
          type: pm.RequestType.image,
          hasAll: true,
          onlyAll: true,
          filterOption: _galleryFilter(),
        ),
        pm.PhotoManager.getAssetPathList(
          type: pm.RequestType.video,
          hasAll: true,
          onlyAll: true,
          filterOption: _galleryFilter(),
        ),
      ]);

      final recentAlbum = results[0];
      final imagesAlbum = results[1];
      final videosAlbum = results[2];

      // Add albums if they have content
      if (recentAlbum.isNotEmpty &&
          _config!.mediaListType == MediaListType.imageVideo) {
        final recentCount = await recentAlbum.first.assetCountAsync;
        if (recentCount > 0) {
          log('load local media -> recent album ${recentAlbum.length}');
          for (final album in recentAlbum) {
            final count = await album.assetCountAsync;
            log('load local media -> album ${album.name} -> count $count');
          }
          _albums.add(recentAlbum.first);
        }
      }

      if (imagesAlbum.isNotEmpty &&
          (_config!.mediaListType == MediaListType.imageVideo ||
              _config!.mediaListType == MediaListType.image)) {
        final imagesCount = await imagesAlbum.first.assetCountAsync;
        if (imagesCount > 0) {
          _albums.add(imagesAlbum.first);
        }
      }

      if (videosAlbum.isNotEmpty &&
          (_config!.mediaListType == MediaListType.imageVideo ||
              _config!.mediaListType == MediaListType.video)) {
        final videosCount = await videosAlbum.first.assetCountAsync;
        if (videosCount > 0) {
          _albums.add(videosAlbum.first);
        }
      }

      // Set the first available album as current
      if (_albums.isNotEmpty) {
        _currentAlbum = _albums.first;
        _currentPage = 0;
        _hasMore = true;
        add(LoadMediaEvent(loadMore: false));
      } else {
        emit(MediaSelectionLoadedState(
          media: _media,
          albums: _albums,
          currentAlbum: _currentAlbum,
          selectedMedia: _selectedMedia,
          isMultiSelectMode: _isMultiSelectMode,
          hasMore: false,
        ));
      }
    } catch (e) {
      debugPrint('Error loading albums: $e');
      emit(MediaSelectionErrorState(message: 'Error loading albums: $e'));
    }
  }

  Future<void> _onLoadMedia(
    LoadMediaEvent event,
    Emitter<MediaSelectionState> emit,
  ) async {
    if (_currentAlbum == null || _config == null) return;
    if (event.loadMore && (_isLoadingPage || !_hasMore)) return;

    if (!event.loadMore) {
      _loadGeneration++;
      _currentPage = 0;
      _hasMore = true;
      _media.clear();
      _assetsById.clear();
    }
    final generation = _loadGeneration;
    final album = _currentAlbum!;
    _isLoadingPage = true;

    try {
      // For load-more, emit immediately so UI shows loading in grid.
      // For initial load, stay in LoadingState until we have media (no emit here).
      if (event.loadMore) {
        emit(MediaSelectionLoadedState(
          media: List.from(_media),
          albums: _albums,
          currentAlbum: _currentAlbum,
          selectedMedia: List.from(_selectedMedia),
          isMultiSelectMode: _isMultiSelectMode,
          isLoadingMore: true,
          hasMore: _hasMore,
        ));
      }
      log('load local media -> current page: $_currentPage');
      final page = await _loadAllowedAssets(album, _currentPage);
      if (generation != _loadGeneration) return;
      log('load local media -> allowed assets ${page.assets.length}');

      _currentPage = page.nextPage;
      _hasMore = page.hasMore;
      for (final asset in page.assets) {
        _assetsById[asset.id] = asset;
        _media.add(_convertAssetToMediaAssetData(asset));
      }

      emit(MediaSelectionLoadedState(
        media: List.from(_media),
        albums: _albums,
        currentAlbum: _currentAlbum,
        selectedMedia: List.from(_selectedMedia),
        isMultiSelectMode: _isMultiSelectMode,
        isLoadingMore: false,
        hasMore: _hasMore,
      ));
    } catch (e) {
      if (generation != _loadGeneration) return;
      debugPrint('Error loading media: $e');
      emit(MediaSelectionErrorState(message: 'Error loading media: $e'));
    } finally {
      if (generation == _loadGeneration) _isLoadingPage = false;
    }
  }

  Future<void> _onLoadMoreMedia(
    LoadMoreMediaEvent event,
    Emitter<MediaSelectionState> emit,
  ) async {
    if (_isLoadingPage || !_hasMore) return;
    add(LoadMediaEvent(loadMore: true));
  }

  Future<void> _onSelectAlbum(
    SelectAlbumEvent event,
    Emitter<MediaSelectionState> emit,
  ) async {
    _currentAlbum = event.album;
    _currentPage = 0;
    _hasMore = true;
    add(LoadMediaEvent(loadMore: false));
  }

  Future<void> _onSelectMedia(
    SelectMediaEvent event,
    Emitter<MediaSelectionState> emit,
  ) async {
    if (_config == null) return;

    // Prevent rapid successive selections
    if (_isProcessingSelection || _isPreparingSelection) {
      return;
    }

    if (_selectedMedia.contains(event.mediaData)) {
      add(DeselectMediaEvent(mediaData: event.mediaData));
      return;
    }

    _isProcessingSelection = true;

    try {
      // Check limits
      final isVideo = event.mediaData.mediaType == SelectedMediaType.video;

      // Check overall media limit
      if (_selectedMedia.length >= _config!.mediaLimit) {
        _isProcessingSelection = false;
        emit(MediaSelectionErrorState(message: getLimitMessage('media')));
        return;
      }

      // Check specific media type limits
      final videoCount = _selectedMedia
          .where((media) => media.mediaType == SelectedMediaType.video)
          .length;
      final imageCount = _selectedMedia
          .where((media) => media.mediaType == SelectedMediaType.image)
          .length;

      if (isVideo && videoCount >= _config!.videoMediaLimit) {
        _isProcessingSelection = false;
        emit(MediaSelectionErrorState(message: getLimitMessage('video')));
        return;
      } else if (!isVideo && imageCount >= _config!.imageMediaLimit) {
        _isProcessingSelection = false;
        emit(MediaSelectionErrorState(message: getLimitMessage('image')));
        return;
      }

      // Check multi-select mode limits
      if (_isMultiSelectMode) {
        if (_selectedMedia.length >= _config!.mediaLimit) {
          _isProcessingSelection = false;
          emit(MediaSelectionErrorState(message: getLimitMessage('media')));
          return;
        }
      }

      if (!_isMultiSelectMode) {
        _selectedMedia.clear();
      }
      _selectedMedia.add(event.mediaData);

      final newState = MediaSelectionLoadedState(
        media: List.from(_media),
        albums: _albums,
        currentAlbum: _currentAlbum,
        selectedMedia: List.from(_selectedMedia),
        isMultiSelectMode: _isMultiSelectMode,
        hasMore: _hasMore,
      );
      emit(newState);

      // If single select mode, proceed immediately
      if (!_isMultiSelectMode) {
        add(ProceedToEditFilterEvent());
      }
    } finally {
      _isProcessingSelection = false;
    }
  }

  Future<void> _onDeselectMedia(
    DeselectMediaEvent event,
    Emitter<MediaSelectionState> emit,
  ) async {
    // If we're in an error state, restore to loaded state first
    _selectedMedia.remove(event.mediaData);
    emit(MediaSelectionLoadedState(
      media: List.from(_media),
      albums: _albums,
      currentAlbum: _currentAlbum,
      selectedMedia: List.from(_selectedMedia),
      isMultiSelectMode: _isMultiSelectMode,
      hasMore: _hasMore,
    ));
  }

  Future<void> _onToggleSelectMode(
    ToggleSelectModeEvent event,
    Emitter<MediaSelectionState> emit,
  ) async {
    if (_config == null || !_config!.isMultiSelect) {
      return;
    }
    _isMultiSelectMode = !_isMultiSelectMode;
    if (!_isMultiSelectMode && _selectedMedia.length > 1) {
      final lastMedia = _selectedMedia.last;
      _selectedMedia.clear();
      _selectedMedia.add(lastMedia);
    }

    emit(MediaSelectionLoadedState(
      media: List.from(_media),
      albums: _albums,
      currentAlbum: _currentAlbum,
      selectedMedia: List.from(_selectedMedia),
      isMultiSelectMode: _isMultiSelectMode,
      hasMore: _hasMore,
    ));
  }

  Future<void> _onCaptureMedia(
    CaptureMediaEvent event,
    Emitter<MediaSelectionState> emit,
  ) async {
    try {
      final status = await Permission.camera.status;

      if (status.isDenied) {
        final result = await Permission.camera.request();
        if (!result.isGranted) {
          emit(MediaSelectionErrorState(
              message: 'Camera permission is required to capture media.'));
          return;
        }
      } else if (status.isPermanentlyDenied) {
        emit(MediaSelectionErrorState(
            message:
                'Camera access is permanently denied. Please enable it from settings.'));
        await openAppSettings();
        return;
      }

      final picker = ImagePicker();
      XFile? file;
      var duration = 0;

      if (event.mediaType == SelectedMediaType.video) {
        if (_config == null) return;
        file = await picker.pickVideo(
          source: ImageSource.camera,
          maxDuration: _config!.videoMaxDuration,
        );
        if (file != null) {
          final mediaInfo = await VideoCompress.getMediaInfo(file.path);
          duration = ((mediaInfo.duration ?? 0) / 1000).toInt();
        }
      } else {
        file = await picker.pickImage(source: ImageSource.camera);
      }

      if (file != null && file.path.isNotEmpty) {
        add(ProcessCapturedMediaEvent(
          file: File(file.path),
          mediaType: event.mediaType,
          duration: duration,
        ));
      }
    } catch (e) {
      emit(MediaSelectionErrorState(
          message: 'Error capturing media: ${e.toString()}'));
    }
  }

  Future<void> _onProcessCapturedMedia(
    ProcessCapturedMediaEvent event,
    Emitter<MediaSelectionState> emit,
  ) async {
    try {
      final filePath = event.file.path;
      final isVideo = event.mediaType == SelectedMediaType.video;

      final mediaData = MediaAssetData(
        assetId: 'camera_${DateTime.now().millisecondsSinceEpoch}',
        mediaType: isVideo ? SelectedMediaType.video : SelectedMediaType.image,
        localPath: filePath,
        file: event.file,
        width: 1080,
        height: 1920,
        duration: event.duration,
        extension: filePath.split('.').last,
        isTemp: 'true',
        isCaptured: true,
        sound: event.sound,
        soundAppliedToVideo: event.soundAppliedToVideo,
      );

      add(ProceedToEditFilterEvent(media: [mediaData]));
    } catch (e) {
      emit(MediaSelectionErrorState(
          message: 'Error processing captured media: ${e.toString()}'));
    }
  }

  Future<void> _onProceedToEditFilter(
    ProceedToEditFilterEvent event,
    Emitter<MediaSelectionState> emit,
  ) async {
    final mediaToEdit = event.media ?? _selectedMedia;
    if (mediaToEdit.isEmpty) {
      emit(MediaSelectionErrorState(
          message: 'Please select at least one media item'));
      return;
    }
    if (_isPreparingSelection) return;

    final needsResolve = mediaToEdit.any(
        (media) => media.localPath == null && _assetsById[media.assetId] != null);
    if (!needsResolve) {
      emit(MediaSelectionCompletedState(selectedMedia: mediaToEdit));
      return;
    }

    _isPreparingSelection = true;
    emit(_loadedState());
    try {
      final resolved = await Future.wait(mediaToEdit.map(_resolveSelectedMedia));
      final failed = resolved.where((media) => media.localPath == null).toList();
      if (failed.isNotEmpty) {
        _selectedMedia.removeWhere(failed.contains);
        _isPreparingSelection = false;
        emit(MediaSelectionErrorState(
            message: 'Unable to load the selected media. Please try again.'));
        emit(_loadedState());
        return;
      }
      _isPreparingSelection = false;
      emit(MediaSelectionCompletedState(selectedMedia: resolved));
      // CompletedState is not built. Restore the grid so the spinner does not
      // stay up while the editor is open and after the user comes back.
      emit(_loadedState());
    } finally {
      _isPreparingSelection = false;
    }
  }

  MediaSelectionLoadedState _loadedState() => MediaSelectionLoadedState(
        media: List.from(_media),
        albums: _albums,
        currentAlbum: _currentAlbum,
        selectedMedia: List.from(_selectedMedia),
        isMultiSelectMode: _isMultiSelectMode,
        hasMore: _hasMore,
        isPreparingSelection: _isPreparingSelection,
      );

  /// Fills [MediaAssetData.localPath], [MediaAssetData.file] and
  /// [MediaAssetData.thumbnailPath] for a gallery item. Done only on selection
  /// because [pm.AssetEntity.file] may copy or download (iCloud) the original.
  Future<MediaAssetData> _resolveSelectedMedia(MediaAssetData media) async {
    final asset = _assetsById[media.assetId];
    if (media.localPath != null || asset == null) return media;
    try {
      final results = await Future.wait<Object?>([
        asset.file,
        getThumbnailFile(asset),
      ]);
      final file = results[0] as File?;
      if (file == null) return media;
      media
        ..file = file
        ..localPath = file.path
        ..extension = file.path.split('.').last
        ..thumbnailPath ??= (results[1] as File?)?.path;
    } catch (e) {
      debugPrint('MediaSelectionBloc: resolve media ${media.assetId} error: $e');
    }
    return media;
  }

  /// Newest first. Video duration is applied by the photo library.
  /// Images ignore [pm.DurationConstraint].
  pm.FilterOptionGroup _galleryFilter() {
    final maxDuration =
        _config?.videoMaxDuration ?? const Duration(seconds: 60);
    return pm.FilterOptionGroup(
      videoOption: pm.FilterOption(
        durationConstraint: pm.DurationConstraint(max: maxDuration),
      ),
      orders: [
        const pm.OrderOption(
          type: pm.OrderOptionType.updateDate,
          asc: false,
        ),
      ],
    );
  }

  /// Fills one grid page from [album] starting at native page [startPage],
  /// skipping videos over [MediaSelectionConfig.videoMaxSizeBytes].
  ///
  /// A reported size of `0` is treated as unknown and kept.
  Future<({List<pm.AssetEntity> assets, int nextPage, bool hasMore})>
      _loadAllowedAssets(pm.AssetPathEntity album, int startPage) async {
    final pageSize = _config!.pageSize;
    final accepted = <pm.AssetEntity>[];
    var page = startPage;
    var hasMore = true;
    while (accepted.length < pageSize && hasMore) {
      final assets = await album.getAssetListPaged(page: page, size: pageSize);
      page++;
      if (assets.length < pageSize) hasMore = false;
      final allowed = await Future.wait(assets.map(_isWithinVideoSizeLimit));
      for (var i = 0; i < assets.length; i++) {
        if (allowed[i]) accepted.add(assets[i]);
      }
    }
    return (assets: accepted, nextPage: page, hasMore: hasMore);
  }

  Future<bool> _isWithinVideoSizeLimit(pm.AssetEntity asset) async {
    final maxBytes = _config?.videoMaxSizeBytes ?? 0;
    if (maxBytes <= 0 || asset.type != pm.AssetType.video) return true;
    try {
      final size = await asset.fileSize;
      if (size <= 0) return true;
      return size <= maxBytes;
    } catch (e) {
      debugPrint('Video size check failed for ${asset.id}: $e');
      return true;
    }
  }

  /// File-backed fields are filled lazily by [_resolveSelectedMedia].
  MediaAssetData _convertAssetToMediaAssetData(pm.AssetEntity asset) =>
      MediaAssetData(
        assetId: asset.id,
        mediaType: asset.type == pm.AssetType.video
            ? SelectedMediaType.video
            : SelectedMediaType.image,
        width: asset.width,
        height: asset.height,
        duration: asset.duration,
      );

  bool isGalleryAsset(String? assetId) => _assetsById.containsKey(assetId);

  Uint8List? cachedGridThumbnail(String assetId) {
    final bytes = _gridThumbnailCache.remove(assetId);
    if (bytes != null) _gridThumbnailCache[assetId] = bytes;
    return bytes;
  }

  /// In-memory grid thumbnail for a gallery asset, deduplicated per asset.
  Future<Uint8List?> getGridThumbnail(String assetId, pm.ThumbnailSize size) {
    final cached = cachedGridThumbnail(assetId);
    if (cached != null) return Future.value(cached);
    final asset = _assetsById[assetId];
    if (asset == null) return Future.value();
    return _gridThumbnailInFlight[assetId] ??= () async {
      try {
        final bytes = await asset.thumbnailDataWithSize(size, quality: 80);
        if (bytes != null && !isClosed) _putGridThumbnail(assetId, bytes);
        return bytes;
      } catch (e) {
        debugPrint('MediaSelectionBloc: grid thumbnail $assetId error: $e');
        return null;
      } finally {
        _gridThumbnailInFlight.remove(assetId)?.ignore();
      }
    }();
  }

  void _putGridThumbnail(String assetId, Uint8List bytes) {
    final previous = _gridThumbnailCache.remove(assetId);
    if (previous != null) _gridThumbnailBytes -= previous.lengthInBytes;
    _gridThumbnailCache[assetId] = bytes;
    _gridThumbnailBytes += bytes.lengthInBytes;
    while (_gridThumbnailBytes > _maxGridThumbnailBytes &&
        _gridThumbnailCache.length > 1) {
      final oldestKey = _gridThumbnailCache.keys.first;
      _gridThumbnailBytes -= _gridThumbnailCache.remove(oldestKey)!.lengthInBytes;
    }
  }

  Future<File?> getThumbnailFile(
    pm.AssetEntity asset,
  ) async {
    try {
      final bytes = await asset.thumbnailDataWithSize(
        const pm.ThumbnailSize(300, 300),
        format: pm.ThumbnailFormat.jpeg,
      );

      if (bytes == null) return null;

      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}/thumbnail_${asset.id.hashCode}_'
            '${DateTime.now().microsecondsSinceEpoch}.jpg',
      );

      await file.writeAsBytes(bytes, flush: true);

      return file;
    } catch (e) {
      debugPrint('MediaSelectionBloc: getThumbnailFile error: $e');
      return null;
    }
  }

  Future<Uint8List?> getAssetThumbnail(
    pm.AssetEntity asset, {
    int size = 300,
  }) async {
    final cacheKey = '${asset.id}_$size';
    if (_assetThumbnailCache.containsKey(cacheKey)) {
      return _assetThumbnailCache[cacheKey];
    }

    if (_assetThumbnailGenerationInProgress.contains(cacheKey)) {
      while (_assetThumbnailGenerationInProgress.contains(cacheKey)) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return _assetThumbnailCache[cacheKey];
    }

    while (_assetThumbnailGenerationInProgress.length >=
        _maxConcurrentAssetThumbnails) {
      await Future.delayed(const Duration(milliseconds: 25));
    }

    _assetThumbnailGenerationInProgress.add(cacheKey);

    try {
      final quality = _config?.thumbnailQuality ?? 50;
      final data = await asset.thumbnailDataWithSize(
        pm.ThumbnailSize.square(size),
        quality: quality,
      );
      if (data != null) {
        _assetThumbnailCache[cacheKey] = data;
      }
      return data;
    } catch (e) {
      debugPrint('Error loading thumbnail for ${asset.id}: $e');
      return null;
    } finally {
      _assetThumbnailGenerationInProgress.remove(cacheKey);
    }
  }

  // Helper methods for limit validation
  int getCurrentVideoCount() => _selectedMedia
      .where((media) => media.mediaType == SelectedMediaType.video)
      .length;

  int getCurrentImageCount() => _selectedMedia
      .where((media) => media.mediaType == SelectedMediaType.image)
      .length;

  bool canAddVideo() {
    if (_config == null) return false;
    return getCurrentVideoCount() < _config!.videoMediaLimit;
  }

  bool canAddImage() {
    if (_config == null) return false;
    return getCurrentImageCount() < _config!.imageMediaLimit;
  }

  bool canAddMedia() {
    if (_config == null) return false;
    return _selectedMedia.length < _config!.mediaLimit;
  }

  String getLimitMessage(String mediaType) {
    if (_config == null) return '';
    switch (mediaType) {
      case 'video':
        return 'Maximum ${_config!.videoMediaLimit} video${_config!.videoMediaLimit > 1 ? 's' : ''} allowed';
      case 'image':
        return 'Maximum ${_config!.imageMediaLimit} image${_config!.imageMediaLimit > 1 ? 's' : ''} allowed';
      default:
        return 'Maximum ${_config!.mediaLimit} media item${_config!.mediaLimit > 1 ? 's' : ''} allowed';
    }
  }

  // Thumbnail methods
  Future<String?> getVideoThumbnail(String videoPath) async {
    // Check cache first
    if (_thumbnailCache.containsKey(videoPath)) {
      return _thumbnailCache[videoPath];
    }

    // Check if already generating for this video
    if (_thumbnailGenerationInProgress.contains(videoPath)) {
      await Future.delayed(const Duration(milliseconds: 100));
      return _thumbnailCache[videoPath];
    }

    // Limit concurrent thumbnail generation
    if (_thumbnailGenerationInProgress.length >= _maxConcurrentThumbnails) {
      while (
          _thumbnailGenerationInProgress.length >= _maxConcurrentThumbnails) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }

    _thumbnailGenerationInProgress.add(videoPath);

    try {
      var thumbnailPath = await MediaUtil.generateThumbnail(
        video: videoPath,
        thumbnailPath: (await Directory.systemTemp.createTemp()).path,
        imageFormat: ImageFormat.JPEG,
        quality: _config?.thumbnailQuality ?? 70,
        timeMs: 1500,
      );
      if (thumbnailPath == null || thumbnailPath.isEmpty) return null;
      _thumbnailCache[videoPath] = thumbnailPath;
      return thumbnailPath;
    } catch (e) {
      debugPrint('Error generating thumbnail for $videoPath: $e');
      return null;
    } finally {
      _thumbnailGenerationInProgress.remove(videoPath);
    }
  }

  void cleanupThumbnailCache() {
    for (final thumbnailPath in _thumbnailCache.values) {
      try {
        final file = File(thumbnailPath);
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (e) {
        debugPrint('Error cleaning up thumbnail: $e');
      }
    }
    _thumbnailCache.clear();
    _thumbnailGenerationInProgress.clear();
    _gridThumbnailCache.clear();
    _gridThumbnailInFlight.clear();
    _gridThumbnailBytes = 0;
  }
}
