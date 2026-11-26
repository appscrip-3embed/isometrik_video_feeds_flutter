import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ism_video_reel_player/presentation/screens/media/media_edit/model/media_edit_audio_model.dart';
import 'package:ism_video_reel_player/presentation/screens/media/media_edit/model/media_edit_models.dart';
import 'package:ism_video_reel_player/utils/post_sound_util.dart';
import 'package:ism_video_reel_player/utils/utility.dart';

part 'media_edit_event.dart';
part 'media_edit_state.dart';

class MediaEditBloc extends Bloc<MediaEditEvent, MediaEditState> {
  MediaEditBloc() : super(MediaEditInitialState()) {
    on<MediaEditInitialEvent>(_onInitial);
    on<UpdateMediaItemEvent>(_onUpdateMediaItem);
    on<OnRemoveMediaEvent>(_onRemoveMedia);
    on<ConfirmRemoveMediaEvent>(_onConfirmRemoveMedia);
    on<AddMoreMediaEvent>(_onAddMoreMedia);
    on<OnSelectMediaEvent>(_onSelectMedia);
    on<ReorderMediaEvent>(_onReorderMedia);
    on<NavigateToTextEditorEvent>(_onNavigateToTextEditor);
    on<NavigateToFilterScreenEvent>(_onNavigateToFilterScreen);
    on<NavigateToImageAdjustmentEvent>(_onNavigateToImageAdjustment);
    on<NavigateToAudioEditorEvent>(_onNavigateToAudioEditor);
    on<NavigateToVideoTrimEvent>(_onNavigateToVideoTrim);
    on<NavigateToVideoEditEvent>(_onNavigateToVideoEdit);
    on<NavigateToVideoFilterEvent>(_onNavigateToVideoFilter);
    on<NavigateToCoverPhotoEvent>(_onNavigateToCoverPhoto);
    on<ProceedToNextEvent>(_onProceedToNext);
    on<MediaEditResetProcessingFlagsEvent>(_onResetProcessingFlags);
  }

  final List<MediaEditItem> _mediaEditItems = [];
  int _currentIndex = 0;
  int? _pendingRemoveIndex;

  Future<void> _onInitial(
    MediaEditInitialEvent event,
    Emitter<MediaEditState> emit,
  ) async {
    _mediaEditItems.clear();
    _mediaEditItems.addAll(event.mediaDataList);
    _currentIndex = 0;

    if (_mediaEditItems.isEmpty) {
      emit(MediaEditEmptyState());
    } else {
      emit(MediaEditLoadedState(
        mediaEditItems: List.from(_mediaEditItems),
        currentIndex: _currentIndex,
      ));
    }
  }

  Future<void> _onUpdateMediaItem(
    UpdateMediaItemEvent event,
    Emitter<MediaEditState> emit,
  ) async {
    if (_currentIndex >= 0 && _currentIndex < _mediaEditItems.length) {
      _mediaEditItems[_currentIndex] = event.updatedItem;
      emit(MediaEditLoadedState(
        mediaEditItems: List.from(_mediaEditItems),
        currentIndex: _currentIndex,
      ));
    }
  }

  Future<void> _onRemoveMedia(
    OnRemoveMediaEvent event,
    Emitter<MediaEditState> emit,
  ) async {
    _pendingRemoveIndex = event.index;
    // The dialog will be shown by the view, then ConfirmRemoveMediaEvent will be triggered
  }

  Future<void> _onConfirmRemoveMedia(
    ConfirmRemoveMediaEvent event,
    Emitter<MediaEditState> emit,
  ) async {
    if (_pendingRemoveIndex == null) return;

    final index = _pendingRemoveIndex!;
    _pendingRemoveIndex = null;

    if (_mediaEditItems.length <= 1) {
      emit(MediaEditEmptyState());
      return;
    }

    _mediaEditItems.removeAt(index);
    if (_currentIndex >= _mediaEditItems.length) {
      _currentIndex = _mediaEditItems.length - 1;
    } else if (_currentIndex > index) {
      _currentIndex--;
    }

    if (_mediaEditItems.isEmpty) {
      emit(MediaEditEmptyState());
    } else {
      emit(MediaEditLoadedState(
        mediaEditItems: List.from(_mediaEditItems),
        currentIndex: _currentIndex,
      ));
    }
  }

  Future<void> _onAddMoreMedia(
    AddMoreMediaEvent event,
    Emitter<MediaEditState> emit,
  ) async {
    _mediaEditItems.addAll(event.newMedia);
    _syncCarouselSoundAcrossEditItems();
    emit(MediaEditLoadedState(
      mediaEditItems: List.from(_mediaEditItems),
      currentIndex: _currentIndex,
    ));
  }

  /// After "add more", share the same soundtrack on every slide (image + video).
  void _syncCarouselSoundAcrossEditItems() {
    if (!PostSoundUtil.useCarouselPostSoundOverlayForEditItems(_mediaEditItems)) {
      return;
    }
    final sound = PostSoundUtil.firstSoundOnEditItems(_mediaEditItems);
    if (sound == null) return;
    PostSoundUtil.applySoundToAllEditItems(_mediaEditItems, sound);
  }

  Future<void> _onSelectMedia(
    OnSelectMediaEvent event,
    Emitter<MediaEditState> emit,
  ) async {
    if (event.index >= 0 && event.index < _mediaEditItems.length) {
      _currentIndex = event.index;
      emit(MediaEditLoadedState(
        mediaEditItems: List.from(_mediaEditItems),
        currentIndex: _currentIndex,
      ));
    }
  }

  Future<void> _onReorderMedia(
    ReorderMediaEvent event,
    Emitter<MediaEditState> emit,
  ) async {
    final maxMediaIndex = _mediaEditItems.length;

    // Validate indices - exclude add button from reordering
    if (event.oldIndex < 0 ||
        event.oldIndex >= maxMediaIndex ||
        event.newIndex < 0 ||
        event.newIndex >= maxMediaIndex) {
      return;
    }

    final item = _mediaEditItems.removeAt(event.oldIndex);
    _mediaEditItems.insert(event.newIndex, item);

    // Update current index to follow the reordered item
    if (_currentIndex == event.oldIndex) {
      _currentIndex = event.newIndex;
    } else if (_currentIndex > event.oldIndex &&
        _currentIndex <= event.newIndex) {
      _currentIndex--;
    } else if (_currentIndex < event.oldIndex &&
        _currentIndex >= event.newIndex) {
      _currentIndex++;
    }

    emit(MediaEditLoadedState(
      mediaEditItems: List.from(_mediaEditItems),
      currentIndex: _currentIndex,
    ));
  }

  Future<void> _onNavigateToTextEditor(
    NavigateToTextEditorEvent event,
    Emitter<MediaEditState> emit,
  ) async {
    if (event.result != null && event.result!['success'] == true) {
      final editedFile = event.result!['file'] as File?;
      if (editedFile != null && _currentIndex < _mediaEditItems.length) {
        final currentItem = _mediaEditItems[_currentIndex];
        final updatedItem = MediaEditItem(
          editedPath: editedFile.path,
          originalPath: currentItem.originalPath,
          mediaType: currentItem.mediaType,
          width: currentItem.width,
          height: currentItem.height,
          duration: currentItem.duration,
          thumbnailPath: editedFile.path,
          sound: currentItem.sound,
          metaData: currentItem.metaData,
        );
        _mediaEditItems[_currentIndex] = updatedItem;
        emit(MediaEditLoadedState(
          mediaEditItems: List.from(_mediaEditItems),
          currentIndex: _currentIndex,
        ));
      }
    }
  }

  Future<void> _onNavigateToFilterScreen(
    NavigateToFilterScreenEvent event,
    Emitter<MediaEditState> emit,
  ) async {
    if (event.result != null && event.result!['success'] == true) {
      final editedFile = event.result!['file'] as File?;
      if (editedFile != null && _currentIndex < _mediaEditItems.length) {
        final currentItem = _mediaEditItems[_currentIndex];
        final updatedItem = MediaEditItem(
          editedPath: editedFile.path,
          originalPath: currentItem.originalPath,
          mediaType: currentItem.mediaType,
          width: currentItem.width,
          height: currentItem.height,
          duration: currentItem.duration,
          thumbnailPath: editedFile.path,
          sound: currentItem.sound,
          metaData: currentItem.metaData,
        );
        _mediaEditItems[_currentIndex] = updatedItem;
        emit(MediaEditLoadedState(
          mediaEditItems: List.from(_mediaEditItems),
          currentIndex: _currentIndex,
        ));
      }
    }
  }

  Future<void> _onNavigateToImageAdjustment(
    NavigateToImageAdjustmentEvent event,
    Emitter<MediaEditState> emit,
  ) async {
    if (event.result != null && event.result!['success'] == true) {
      final editedFile = event.result!['file'] as File?;
      if (editedFile != null && _currentIndex < _mediaEditItems.length) {
        final currentItem = _mediaEditItems[_currentIndex];
        final updatedItem = MediaEditItem(
          editedPath: editedFile.path,
          originalPath: currentItem.originalPath,
          mediaType: currentItem.mediaType,
          width: currentItem.width,
          height: currentItem.height,
          duration: currentItem.duration,
          thumbnailPath: editedFile.path,
          sound: currentItem.sound,
          metaData: currentItem.metaData,
        );
        _mediaEditItems[_currentIndex] = updatedItem;
        emit(MediaEditLoadedState(
          mediaEditItems: List.from(_mediaEditItems),
          currentIndex: _currentIndex,
        ));
      }
    }
  }

  Future<void> _onNavigateToAudioEditor(
    NavigateToAudioEditorEvent event,
    Emitter<MediaEditState> emit,
  ) async {
    if (_currentIndex >= _mediaEditItems.length) return;

    final sound = event.sound;
    final useCarouselOverlay =
        PostSoundUtil.useCarouselPostSoundOverlayForEditItems(_mediaEditItems);

    if (sound != null && sound.soundUrl?.isNotEmpty == true) {
      final item = _mediaEditItems[_currentIndex];
      if (!useCarouselOverlay && item.mediaType == EditMediaType.video) {
        final trackStartMs =
            PostSoundUtil.soundTrackStartOffsetMilliseconds(sound);
        // Non-zero start: preview uses muted video + synced overlay; mux at export.
        if (trackStartMs > 0) {
          // Drop a prior mux so preview uses the library URL + start_time.
          final editPath = item.editedPath?.trim() ?? '';
          final original = item.originalPath.trim();
          final clearedEdit =
              editPath.isNotEmpty && editPath != original ? original : null;
          _mediaEditItems[_currentIndex] = item.copyWith(
            sound: sound,
            editedPath: clearedEdit ?? item.editedPath,
          );
        } else {
          emit(MediaEditLoadedState(
            mediaEditItems: List.from(_mediaEditItems),
            currentIndex: _currentIndex,
            isApplyingSound: true,
          ));

          final videoPath = item.editedPath ?? item.originalPath;
          final muxed = await PostSoundUtil.muxVideoWithSound(
            videoPath: videoPath,
            sound: sound,
            showLoader: false,
          );
          if (muxed == videoPath) {
            Utility.showToastMessage(
              'Could not mix audio into this video. Try another sound or clip.',
            );
          }
          _mediaEditItems[_currentIndex] = item.copyWith(
            editedPath: muxed,
            sound: sound,
          );
        }
      } else {
        for (var i = 0; i < _mediaEditItems.length; i++) {
          _mediaEditItems[i] = _mediaEditItems[i].copyWith(sound: sound);
        }
      }
    } else {
      for (var i = 0; i < _mediaEditItems.length; i++) {
        _mediaEditItems[i] = _mediaEditItems[i].copyWith(sound: sound);
      }
    }
    emit(MediaEditLoadedState(
      mediaEditItems: List.from(_mediaEditItems),
      currentIndex: _currentIndex,
    ));
  }

  Future<void> _onNavigateToVideoTrim(
    NavigateToVideoTrimEvent event,
    Emitter<MediaEditState> emit,
  ) async {
    if (event.result != null && event.result!['success'] == true) {
      final editedFile = event.result!['file'] as File?;
      if (editedFile != null && _currentIndex < _mediaEditItems.length) {
        final currentItem = _mediaEditItems[_currentIndex];
        final updatedItem = MediaEditItem(
          editedPath: editedFile.path,
          originalPath: currentItem.originalPath,
          mediaType: currentItem.mediaType,
          width: currentItem.width,
          height: currentItem.height,
          duration: currentItem.duration,
          thumbnailPath: currentItem.thumbnailPath,
          sound: currentItem.sound,
          metaData: currentItem.metaData,
        );
        _mediaEditItems[_currentIndex] = updatedItem;
        emit(MediaEditLoadedState(
          mediaEditItems: List.from(_mediaEditItems),
          currentIndex: _currentIndex,
        ));
      }
    }
  }

  Future<void> _onNavigateToVideoEdit(
    NavigateToVideoEditEvent event,
    Emitter<MediaEditState> emit,
  ) async {
    if (event.result != null && event.result!['success'] == true) {
      final editedFile = event.result!['file'] as File?;
      if (editedFile != null && _currentIndex < _mediaEditItems.length) {
        final currentItem = _mediaEditItems[_currentIndex];
        final updatedItem = MediaEditItem(
          editedPath: editedFile.path,
          originalPath: currentItem.originalPath,
          mediaType: currentItem.mediaType,
          width: currentItem.width,
          height: currentItem.height,
          duration: currentItem.duration,
          thumbnailPath: currentItem.thumbnailPath,
          sound: currentItem.sound,
          metaData: currentItem.metaData,
        );
        _mediaEditItems[_currentIndex] = updatedItem;
        emit(MediaEditLoadedState(
          mediaEditItems: List.from(_mediaEditItems),
          currentIndex: _currentIndex,
        ));
      }
    }
  }

  Future<void> _onNavigateToVideoFilter(
    NavigateToVideoFilterEvent event,
    Emitter<MediaEditState> emit,
  ) async {
    if (event.result != null && event.result!['success'] == true) {
      final editedFile = event.result!['file'] as File?;
      if (editedFile != null && _currentIndex < _mediaEditItems.length) {
        final currentItem = _mediaEditItems[_currentIndex];
        final updatedItem = MediaEditItem(
          editedPath: editedFile.path,
          originalPath: currentItem.originalPath,
          mediaType: currentItem.mediaType,
          width: currentItem.width,
          height: currentItem.height,
          duration: currentItem.duration,
          thumbnailPath: currentItem.thumbnailPath,
          sound: currentItem.sound,
          metaData: currentItem.metaData,
        );
        _mediaEditItems[_currentIndex] = updatedItem;
        emit(MediaEditLoadedState(
          mediaEditItems: List.from(_mediaEditItems),
          currentIndex: _currentIndex,
        ));
      }
    }
  }

  Future<void> _onNavigateToCoverPhoto(
    NavigateToCoverPhotoEvent event,
    Emitter<MediaEditState> emit,
  ) async {
    if (event.coverFile != null && _currentIndex < _mediaEditItems.length) {
      final currentItem = _mediaEditItems[_currentIndex];
      final updatedItem = MediaEditItem(
        editedPath: currentItem.editedPath,
        originalPath: currentItem.originalPath,
        mediaType: currentItem.mediaType,
        width: currentItem.width,
        height: currentItem.height,
        duration: currentItem.duration,
        thumbnailPath: event.coverFile!.path,
        sound: currentItem.sound,
        metaData: currentItem.metaData,
      );
      _mediaEditItems[_currentIndex] = updatedItem;
      emit(MediaEditLoadedState(
        mediaEditItems: List.from(_mediaEditItems),
        currentIndex: _currentIndex,
      ));
    }
  }

  Future<void> _onProceedToNext(
    ProceedToNextEvent event,
    Emitter<MediaEditState> emit,
  ) async {
    emit(MediaEditLoadedState(
      mediaEditItems: List.from(_mediaEditItems),
      currentIndex: _currentIndex,
      isProcessingNext: true,
    ));

    try {
      final useCarousel =
          PostSoundUtil.useCarouselPostSoundOverlayForEditItems(_mediaEditItems);
      if (!useCarousel) {
        for (var i = 0; i < _mediaEditItems.length; i++) {
          final item = _mediaEditItems[i];
          final sound = item.sound;
          if (item.mediaType != EditMediaType.video ||
              sound == null ||
              sound.soundUrl?.trim().isEmpty == true) {
            continue;
          }
          final path = item.editedPath ?? item.originalPath;
          final muxed = await PostSoundUtil.muxVideoWithSound(
            videoPath: path,
            sound: sound,
            showLoader: false,
          );
          _mediaEditItems[i] = item.copyWith(editedPath: muxed);
        }
      }
      emit(MediaEditLoadedState(
        mediaEditItems: List.from(_mediaEditItems),
        currentIndex: _currentIndex,
        isProcessingNext: false,
        isApplyingSound: false,
      ));
      emit(MediaEditCompletedState(mediaEditItems: List.from(_mediaEditItems)));
    } catch (_) {
      emit(MediaEditLoadedState(
        mediaEditItems: List.from(_mediaEditItems),
        currentIndex: _currentIndex,
      ));
    }
  }

  void _onResetProcessingFlags(
    MediaEditResetProcessingFlagsEvent event,
    Emitter<MediaEditState> emit,
  ) {
    if (state is! MediaEditLoadedState) return;
    final current = state as MediaEditLoadedState;
    if (!current.isProcessingNext && !current.isApplyingSound) return;
    emit(MediaEditLoadedState(
      mediaEditItems: List.from(_mediaEditItems),
      currentIndex: _currentIndex,
      isProcessingNext: false,
      isApplyingSound: false,
    ));
  }

  int? get pendingRemoveIndex => _pendingRemoveIndex;
}
