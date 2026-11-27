import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:ism_video_reel_player/presentation/screens/posts/media_kit_video_player.dart';
import 'package:ism_video_reel_player/presentation/screens/posts/safe_video_player.dart';
import 'package:ism_video_reel_player/presentation/screens/posts/video_player_interface.dart';
import 'package:ism_video_reel_player/utils/utils.dart';
import 'package:video_player/video_player.dart';

class StandardVideoNonPreloadedController implements IVideoPlayerController {
  StandardVideoNonPreloadedController(this._controller) {
    _setupListeners();
  }

  final VideoPlayerController _controller;
  final ValueNotifier<bool> _playingStateNotifier = ValueNotifier(false);
  final ValueNotifier<bool> _canBuildView = ValueNotifier(true);

  bool _isDisposed = false;
  bool _nativeDisposed = false;
  bool _hasLoggedError = false;
  int _attachCount = 0;

  void _setupListeners() {
    _controller.addListener(() {
      if (_isDisposed) return;

      _playingStateNotifier.value = _controller.value.isPlaying;

      if (_controller.value.hasError && !_hasLoggedError) {
        _hasLoggedError = true;
        debugPrint('❌ Video error: ${_controller.value.errorDescription}');
      }
    });
  }

  void retain() => _attachCount++;

  int release() {
    if (_attachCount > 0) _attachCount--;
    return _attachCount;
  }

  int get attachCount => _attachCount;

  /// Drop the platform view from the tree before native dispose.
  void prepareForDispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    if (_canBuildView.value) {
      _canBuildView.value = false;
    }
  }

  // --- IVideoPlayerController impl ---

  @override
  Future<void> initialize() => _controller.initialize();

  @override
  Future<void> play() {
    if (_isDisposed) return Future.value();
    return _controller.play();
  }

  @override
  Future<void> pause() {
    if (_isDisposed) return Future.value();
    return _controller.pause();
  }

  @override
  Future<void> seekTo(Duration position) {
    if (_isDisposed) return Future.value();
    return _controller.seekTo(position);
  }

  @override
  Future<void> setLooping(bool looping) {
    if (_isDisposed) return Future.value();
    return _controller.setLooping(looping);
  }

  @override
  Future<void> setVolume(double volume) {
    if (_isDisposed) return Future.value();
    return _controller.setVolume(volume);
  }

  @override
  Future<void> setPlaybackSpeed(double speed) {
    if (_isDisposed) return Future.value();
    return _controller.setPlaybackSpeed(speed);
  }

  @override
  bool get isPlaying => !_isDisposed && _controller.value.isPlaying;

  @override
  bool get isBuffering => !_isDisposed && _controller.value.isBuffering;

  @override
  bool get isInitialized => !_isDisposed && _controller.value.isInitialized;

  @override
  bool get isDisposed => _isDisposed;

  @override
  Duration get duration =>
      _isDisposed ? Duration.zero : _controller.value.duration;

  @override
  Duration get position =>
      _isDisposed ? Duration.zero : _controller.value.position;

  @override
  Size get videoSize =>
      _isDisposed ? Size.zero : _controller.value.size;

  @override
  double get aspectRatio =>
      _isDisposed ? 16 / 9 : _controller.value.aspectRatio;

  @override
  ValueNotifier<bool> get playingStateNotifier => _playingStateNotifier;

  @override
  Widget buildVideoPlayerWidget() => ValueListenableBuilder<bool>(
        valueListenable: _canBuildView,
        builder: (context, canBuild, _) {
          if (!canBuild || _isDisposed) {
            return const SizedBox.shrink();
          }
          return SafeVideoPlayer(
            controller: _controller,
            isBuildSafe: () => canBuild && !_isDisposed && !_nativeDisposed,
          );
        },
      );

  @override
  Future<void> forceResume() async {
    if (_isDisposed) return;
    if (!_controller.value.isPlaying) {
      await _controller.play();
    }
  }

  @override
  void addListener(VoidCallback listener) => _controller.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _controller.removeListener(listener);

  @override
  Future<void> dispose() async {
    prepareForDispose();
    if (_nativeDisposed) return;
    _nativeDisposed = true;

    VideoControllerDisposeScheduler.cancel(this);

    try {
      _playingStateNotifier.dispose();
    } catch (_) {}

    try {
      await _controller.dispose();
    } catch (e) {
      debugPrint('⚠️ Error disposing non-preload video controller: $e');
    }

    try {
      _canBuildView.dispose();
    } catch (_) {}
  }
}

class StandardVideoNonPreloadedManager implements IVideoCacheManager {
  factory StandardVideoNonPreloadedManager() => _instance;

  StandardVideoNonPreloadedManager._internal();

  static final StandardVideoNonPreloadedManager _instance =
      StandardVideoNonPreloadedManager._internal();

  static const Duration _sizeWaitTimeout = Duration(milliseconds: 800);

  /// Live decoders — keep low on mobile (SurfaceView / MediaCodec / AVPlayer).
  /// Reuse: must stay aligned with [ReelsFeedPrecacheCoordinator] warm window
  /// (mobile: visible + 1 ahead ≈ 2). Android already smooth; iOS was slow with
  /// 4 concurrent AVPlayers + custom HTTP headers on progressive MP4.
  static int get _maxLiveControllers =>
      (Platform.isAndroid || Platform.isIOS) ? 2 : 4;

  /// Insertion-ordered live controller map (url → wrapper).
  final LinkedHashMap<String, IVideoPlayerController> _liveControllers =
      LinkedHashMap<String, IVideoPlayerController>();

  /// URLs in the reels warm window — preferred keep, but soft-cap still wins.
  final Set<String> _warmPinnedUrls = <String>{};

  final Set<String> _initializingUrls = <String>{};

  void _trackLive(String url, IVideoPlayerController controller) {
    _liveControllers.remove(url);
    _liveControllers[url] = controller;
    _evictIfOverCap(exceptUrl: url);
  }

  void _untrack(String url, IVideoPlayerController? controller) {
    final existing = _liveControllers[url];
    if (existing == null) return;
    if (controller != null && !identical(existing, controller)) return;
    _liveControllers.remove(url);
  }

  /// Host feed passes display URLs (Gumlet/original) for the warm window.
  void setWarmPinnedUrls(Set<String> urls) {
    _warmPinnedUrls
      ..clear()
      ..addAll(urls);
    // Pins must not defeat the soft-cap (warm ahead + visible used to exceed 2).
    _evictIfOverCap();
  }

  /// Clears warm pins and disposes pooled decoders (profile / other tabs).
  void disposeReelsWarmPool() {
    _warmPinnedUrls.clear();
    _initializingUrls.clear();
    final entries = _liveControllers.entries.toList();
    _liveControllers.clear();
    for (final entry in entries) {
      final controller = entry.value;
      if (FeedVideoPlayerHandoff.isControllerProtected(controller)) {
        _liveControllers[entry.key] = controller;
        continue;
      }
      try {
        if (controller is StandardVideoNonPreloadedController) {
          controller.prepareForDispose();
        }
        VideoControllerDisposeScheduler.cancel(controller);
        VideoControllerDisposeScheduler.scheduleAfterUnmount(
          controller,
          controller.dispose,
        );
      } catch (e) {
        debugPrint('⚠️ disposeReelsWarmPool error for ${entry.key}: $e');
      }
    }
  }

  void _evictIfOverCap({String? exceptUrl}) {
    while (_liveControllers.length > _maxLiveControllers) {
      // Pass 1: drop non-warm first. Pass 2: drop warm pins too so soft-cap
      // always wins (avoids 3+ MediaCodec sessions during fast scroll).
      final evictUrl = _pickEvictionUrl(
            exceptUrl: exceptUrl,
            allowWarmPinned: false,
          ) ??
          _pickEvictionUrl(
            exceptUrl: exceptUrl,
            allowWarmPinned: true,
          );
      if (evictUrl == null) break;
      final victim = _liveControllers.remove(evictUrl);
      if (victim == null) continue;
      _warmPinnedUrls.remove(evictUrl);
      try {
        if (victim is StandardVideoNonPreloadedController) {
          victim.prepareForDispose();
        }
        VideoControllerDisposeScheduler.scheduleAfterUnmount(
          victim,
          victim.dispose,
        );
      } catch (e) {
        debugPrint('⚠️ Soft-cap eviction error for $evictUrl: $e');
      }
    }
  }

  /// Oldest (insertion-order) live URL that is safe to dispose.
  String? _pickEvictionUrl({
    required String? exceptUrl,
    required bool allowWarmPinned,
  }) {
    for (final entry in _liveControllers.entries) {
      if (entry.key == exceptUrl) continue;
      if (!allowWarmPinned && _warmPinnedUrls.contains(entry.key)) continue;
      if (FeedVideoPlayerHandoff.isControllerProtected(entry.value)) continue;
      if (entry.value is StandardVideoNonPreloadedController) {
        final c = entry.value as StandardVideoNonPreloadedController;
        // Still attached to a mounted widget — do not tear down mid-frame.
        if (c.attachCount > 0) continue;
      }
      return entry.key;
    }
    return null;
  }

  @override
  Future<void> precacheVideos(
    List<String> videoUrls, {
    bool highPriority = false,
  }) async {
    final toWarm = <String>[];
    for (final url in videoUrls) {
      if (url.isEmpty) continue;
      final lower = url.toLowerCase();
      if (lower.endsWith('.m3u8')) {
        unawaited(VideoMediaUtil.precacheFirstSegment(url));
      }
      if (!highPriority) continue;
      if (_liveControllers.containsKey(url) || _initializingUrls.contains(url)) {
        continue;
      }
      toWarm.add(url);
    }

    // One-at-a-time warm on mobile — parallel AVPlayer inits stall iOS hard.
    final parallel = (Platform.isAndroid || Platform.isIOS) ? 1 : 2;
    for (var i = 0; i < toWarm.length; i += parallel) {
      final batch = toWarm.skip(i).take(parallel);
      await Future.wait(
        batch.map((url) {
          _initializingUrls.add(url);
          return _createAndInitializeController(url).whenComplete(() {
            _initializingUrls.remove(url);
          });
        }),
      );
    }
  }

  @override
  IVideoPlayerController? getCachedController(String url) {
    final controller = _liveControllers[url];
    if (controller == null) return null;
    if (controller.isDisposed || !controller.isInitialized) {
      _liveControllers.remove(url);
      return null;
    }
    return controller;
  }

  @override
  Future<IVideoPlayerController?> precacheMediaAndReturnController(
      String url, {
        bool useFallBackControllerOnFail = true,
      }) {
    final cached = getCachedController(url);
    if (cached != null && !cached.isDisposed && cached.isInitialized) {
      return Future.value(cached);
    }
    return _createAndInitializeController(
      url,
      useFallBackControllerOnFail: useFallBackControllerOnFail,
    );
  }

  Future<IVideoPlayerController?> _createAndInitializeController(
      String url, {
        bool useFallBackControllerOnFail = true,
      }) async {
    debugPrint(
        'StandardVideoCacheManager: _createAndInitializeController: $url');
    VideoPlayerController? controller;
    try {
      controller = _createVideoPlayerController(url);

      await controller.initialize().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          debugPrint(
              '⚠️ StandardNonCacheVideoPlayer initialization timeout for: $url');
          throw TimeoutException(
              'Video initialization timeout', const Duration(seconds: 15));
        },
      );

      if (!controller.value.isInitialized) {
        debugPrint(
            '❌ StandardNonCacheVideoPlayer not initialized properly for: $url');
        await controller.dispose();
        return useFallBackControllerOnFail? _fallbackToMediaKit(url, reason: 'not initialized') : null;
      }

      if (controller.value.hasError) {
        debugPrint(
            '❌ StandardNonCacheVideoPlayer has error after initialization: ${controller.value.errorDescription}');
        debugPrint('❌ URL: $url');
        await controller.dispose();
        return useFallBackControllerOnFail? _fallbackToMediaKit(url, reason: 'not initialized') : null;
      }

      // Size can be 0x0 briefly then become valid — wait before treating as failure.
      final size = await _waitForValidSize(controller);
      if (size == Size.zero) {
        debugPrint(
            '⚠️ StandardNonCacheVideoPlayer size still 0x0 after wait for: $url');
        await controller.dispose();
        controller = null;
        return useFallBackControllerOnFail? _fallbackToMediaKit(url, reason: 'not initialized') : null;
      }

      debugPrint(
          '✅ Video initialized successfully - Size: $size, Duration: ${controller.value.duration}, URL: $url');

      await Future.wait([
        controller.setLooping(false),
        controller.setVolume(1.0),
      ]);

      final wrapped = StandardVideoNonPreloadedController(controller);
      _trackLive(url, wrapped);
      return wrapped;
    } catch (e, stackTrace) {
      debugPrintStack(
          label: 'StandardVideoCacheManager cached error $e',
          stackTrace: stackTrace);
      debugPrint('❌ Error creating video controller for URL: $url - Error: $e');
      if (controller != null) {
        try {
          await controller.dispose();
        } catch (_) {}
      }
      await Future.delayed(const Duration(milliseconds: 300));
      return useFallBackControllerOnFail? _fallbackToMediaKit(url, reason: 'not initialized') : null;
    }
  }

  /// Waits for non-zero dimensions; many URLs report 0x0 right after [initialize].
  Future<Size> _waitForValidSize(VideoPlayerController controller) async {
    if (controller.value.size != Size.zero) {
      return controller.value.size;
    }

    final completer = Completer<Size>();
    Timer? timeoutTimer;

    void listener() {
      final size = controller.value.size;
      if (size != Size.zero) {
        controller.removeListener(listener);
        timeoutTimer?.cancel();
        if (!completer.isCompleted) {
          completer.complete(size);
        }
      }
    }

    controller.addListener(listener);
    timeoutTimer = Timer(_sizeWaitTimeout, () {
      controller.removeListener(listener);
      if (!completer.isCompleted) {
        completer.complete(controller.value.size);
      }
    });

    return completer.future;
  }

  Future<IVideoPlayerController?> _fallbackToMediaKit(
    String url, {
    required String reason,
  }) async {
    debugPrint('🔄 Standard player failed ($reason), trying MediaKit: $url');
    await Future.delayed(const Duration(milliseconds: 150));
    final fallback =
        await MediaKitCacheManager().createEphemeralFallbackController(url);
    if (fallback != null) {
      _trackLive(url, fallback);
    }
    return fallback;
  }

  VideoPlayerController _createVideoPlayerController(String mediaUrl) {
    if (Utility.isLocalUrl(mediaUrl)) {
      return VideoPlayerController.file(
        File(mediaUrl),
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: true,
          allowBackgroundPlayback: false,
        ),
      );
    }

    var url = preserveEmptyPathSegments(mediaUrl);
    if (url.startsWith('http:')) {
      url = url.replaceFirst('http:', 'https:');
    }

    final isHls = url.toLowerCase().endsWith('.m3u8');
    // iOS: empty headers for progressive MP4 — see [VideoMediaUtil.networkHttpHeaders].
    final headers = VideoMediaUtil.networkHttpHeaders(isHls: isHls);

    return VideoPlayerController.networkUrl(
      Uri.parse(url),
      videoPlayerOptions: VideoPlayerOptions(
        mixWithOthers: true,
        allowBackgroundPlayback: false,
      ),
      httpHeaders: headers,
      formatHint: isHls ? VideoFormat.hls : null,
    );
  }

  @override
  bool isVideoCached(String url) {
    final c = _liveControllers[url];
    return c != null && !c.isDisposed && c.isInitialized;
  }

  @override
  bool isVideoInitializing(String url) => _initializingUrls.contains(url);

  @override
  void markAsVisible(String url) {}

  @override
  void markAsNotVisible(String url) {}

  @override
  void attachedToWidget(String url, IVideoPlayerController? controller) {
    if (controller is StandardVideoNonPreloadedController) {
      VideoControllerDisposeScheduler.cancel(controller);
      controller.retain();
    }
    if (controller != null) {
      _trackLive(url, controller);
    }
  }

  @override
  void detachedFromWidget(String url, IVideoPlayerController? controller) {
    if (controller == null) return;

    if (controller is StandardVideoNonPreloadedController) {
      final remaining = controller.release();
      if (remaining > 0) return;

      // Decoder stays in the warm pool for the next widget attach.
      if (_warmPinnedUrls.contains(url)) return;

      _untrack(url, controller);
      // Drop platform view immediately, then dispose native after unmount.
      controller.prepareForDispose();
      VideoControllerDisposeScheduler.scheduleAfterUnmount(
        controller,
        controller.dispose,
      );
      return;
    }

    _untrack(url, controller);
    // MediaKit ephemeral fallback (or other backends): dispose after unmount.
    VideoControllerDisposeScheduler.scheduleAfterUnmount(controller, () async {
      if (controller.isDisposed) return;
      try {
        await controller.pause();
      } catch (_) {}
      try {
        await controller.dispose();
      } catch (e) {
        debugPrint('⚠️ Error disposing detached fallback controller: $e');
      }
    });
  }

  void forceClearVideo(String url) {
    _warmPinnedUrls.remove(url);
    _initializingUrls.remove(url);
    final controller = _liveControllers.remove(url);
    if (controller == null) return;
    if (FeedVideoPlayerHandoff.isControllerProtected(controller)) {
      _liveControllers[url] = controller;
      return;
    }
    try {
      if (controller is StandardVideoNonPreloadedController) {
        controller.prepareForDispose();
      }
      VideoControllerDisposeScheduler.cancel(controller);
      VideoControllerDisposeScheduler.scheduleAfterUnmount(
        controller,
        controller.dispose,
      );
    } catch (e) {
      debugPrint('⚠️ forceClearVideo error for $url: $e');
    }
  }

  @override
  void clearVideo(String url) {
    if (_warmPinnedUrls.contains(url)) return;
    final controller = _liveControllers.remove(url);
    if (controller == null) return;
    if (FeedVideoPlayerHandoff.isControllerProtected(controller)) {
      // Keep protected handoff controllers tracked under a temp key? Skip dispose.
      _liveControllers[url] = controller;
      return;
    }
    try {
      if (controller is StandardVideoNonPreloadedController) {
        controller.prepareForDispose();
      }
      VideoControllerDisposeScheduler.cancel(controller);
      VideoControllerDisposeScheduler.scheduleAfterUnmount(
        controller,
        controller.dispose,
      );
    } catch (e) {
      debugPrint('⚠️ clearVideo error for $url: $e');
    }
  }

  @override
  void clearControllers() {
    final entries = _liveControllers.entries.toList();
    _liveControllers.clear();
    for (final entry in entries) {
      final controller = entry.value;
      if (FeedVideoPlayerHandoff.isControllerProtected(controller)) {
        _liveControllers[entry.key] = controller;
        continue;
      }
      try {
        if (controller is StandardVideoNonPreloadedController) {
          controller.prepareForDispose();
        }
        VideoControllerDisposeScheduler.cancel(controller);
        VideoControllerDisposeScheduler.scheduleAfterUnmount(
          controller,
          controller.dispose,
        );
      } catch (e) {
        debugPrint('⚠️ clearControllers error for ${entry.key}: $e');
      }
    }
  }

  @override
  Map<String, dynamic> getCacheStats() => {
        'mode': 'reels-warm-pool',
        'cached_videos': _liveControllers.length,
        'max_live': _maxLiveControllers,
        'warm_pinned': _warmPinnedUrls.length,
        'initializing_videos': _initializingUrls.length,
        'visible_videos': 0,
      };
}
