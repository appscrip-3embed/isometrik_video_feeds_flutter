import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:ism_video_reel_player/presentation/screens/media/media_edit/media_edit.dart';
import 'package:ism_video_reel_player/utils/audio_source_util.dart';
import 'package:ism_video_reel_player/utils/post_sound_util.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

class VideoPreviewWidget extends StatefulWidget {
  const VideoPreviewWidget({
    super.key,
    required this.mediaEditItem,
    required this.onRemoveMedia,
    required this.mediaEditConfig,
    this.postSoundStartOffsetMilliseconds = 0,
    this.forcePostLevelSoundOverlay = false,
  });

  final MediaEditItem mediaEditItem;
  /// Seek position on the post soundtrack before this video slice (mixed carousel).
  final int postSoundStartOffsetMilliseconds;
  /// When true, play [MediaEditItem.sound] as overlay (mute file audio) even if muxed.
  final bool forcePostLevelSoundOverlay;
  final VoidCallback onRemoveMedia;
  final MediaEditConfig mediaEditConfig;

  @override
  State<VideoPreviewWidget> createState() => _VideoPreviewWidgetState();
}

class _VideoPreviewWidgetState extends State<VideoPreviewWidget> {
  VideoPlayerController? _videoController;
  AudioPlayer? _soundPlayer;
  bool _showPauseIcon = false;
  Timer? _pauseIconTimer;
  bool _isVideoVisible = true;
  bool _wasPlayingBeforeVisibilityChange = false;
  bool _videoEnded = false;
  bool _lastVideoPlaying = false;

  bool get _hasSelectedSound =>
      widget.mediaEditItem.sound?.soundUrl?.trim().isNotEmpty == true;

  bool get _soundMuxedIntoVideo {
    final edited = widget.mediaEditItem.editedPath?.trim() ?? '';
    final original = widget.mediaEditItem.originalPath.trim();
    return edited.isNotEmpty && edited != original;
  }

  /// Always overlay the library track in the editor so [start_time] is honored
  /// (muxed files may still contain audio from 0:00).
  bool get _usesSeparateSoundPreview =>
      _hasSelectedSound &&
      (!_soundMuxedIntoVideo ||
          widget.forcePostLevelSoundOverlay ||
          widget.postSoundStartOffsetMilliseconds > 0 ||
          PostSoundUtil.isLibrarySoundId(widget.mediaEditItem.sound?.soundId));

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  @override
  void didUpdateWidget(VideoPreviewWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    final soundChanged =
        oldWidget.mediaEditItem.sound?.soundId !=
            widget.mediaEditItem.sound?.soundId ||
        oldWidget.mediaEditItem.sound?.soundMetadata?['start_time'] !=
            widget.mediaEditItem.sound?.soundMetadata?['start_time'];
    final offsetChanged = oldWidget.postSoundStartOffsetMilliseconds !=
        widget.postSoundStartOffsetMilliseconds;
    if (oldWidget.mediaEditItem != widget.mediaEditItem ||
        soundChanged ||
        offsetChanged) {
      unawaited(_stopSoundPreview());
      _initializeVideo();
    }
  }

  @override
  void dispose() {
    _videoController?.removeListener(_videoListener);
    _videoController?.dispose();
    _pauseIconTimer?.cancel();
    unawaited(_stopSoundPreview());
    super.dispose();
  }

  Future<void> _stopSoundPreview() async {
    final player = _soundPlayer;
    _soundPlayer = null;
    if (player != null) {
      try {
        await player.stop();
        await player.dispose();
      } catch (_) {}
    }
  }

  Future<void> _initializeVideo() async {
    await _disposeVideoController();
    if (!mounted) return;
    await _createVideoController(widget.mediaEditItem);
  }

  Future<void> _disposeVideoController() async {
    if (_videoController != null) {
      _videoController!.removeListener(_videoListener);
      await _videoController!.dispose();
      _videoController = null;
    }
  }

  Future<void> _createVideoController(MediaEditItem mediaItem) async {
    try {
      final videoPath = mediaItem.editedPath ?? mediaItem.originalPath;
      if (videoPath.isEmpty) return;

      final file = File(videoPath);
      if (!await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Video file not found'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final previous = _videoController;
      if (previous != null) {
        previous.removeListener(_videoListener);
        await previous.dispose();
      }
      _videoController = null;
      if (!mounted) return;

      _videoEnded = false;
      _videoController = VideoPlayerController.file(
        file,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      _videoController!.addListener(_videoListener);

      await _videoController!.initialize().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception(
              'Video initialization timeout - file may be corrupted or too large');
        },
      );

      if (!mounted) {
        final c = _videoController;
        _videoController = null;
        if (c != null) {
          c.removeListener(_videoListener);
          await c.dispose();
        }
        return;
      }

      if (_videoController!.value.isInitialized) {
        final shouldLoop = !_hasSelectedSound;
        await _videoController!.setLooping(shouldLoop);
        await _videoController!.setVolume(_usesSeparateSoundPreview ? 0.0 : 1.0);

        if (_usesSeparateSoundPreview) {
          await _prepareSeparateSoundPreview();
        }

        if (mounted) {
          setState(() {});
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to initialize video player'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Error loading video: ${e.toString().replaceFirst('Exception: ', '')}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _prepareSeparateSoundPreview() async {
    final url = widget.mediaEditItem.sound?.soundUrl?.trim() ?? '';
    if (url.isEmpty) return;
    await _stopSoundPreview();
    final player = AudioPlayer();
    _soundPlayer = player;
    try {
      await player.setReleaseMode(ReleaseMode.stop);
      // Local file for sound extracted from a reel; URL for library sounds.
      await player.setSource(audioSourceFromUrlOrPath(url));
      final offsetMs = widget.postSoundStartOffsetMilliseconds;
      if (offsetMs > 0) {
        await player.seek(Duration(milliseconds: offsetMs));
      }
    } catch (_) {
      await _stopSoundPreview();
    }
  }

  void _videoListener() {
    _videoErrorListener();
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;

    final duration = controller.value.duration;
    final position = controller.value.position;
    if (duration.inMilliseconds <= 0) return;

    final reachedEnd =
        position >= duration - const Duration(milliseconds: 200);
    if (reachedEnd && controller.value.isPlaying) {
      unawaited(_handleVideoReachedEnd());
    }

    final isPlaying = controller.value.isPlaying;
    if (isPlaying && !_lastVideoPlaying && _usesSeparateSoundPreview) {
      unawaited(_syncSoundWithVideoPlayback(playing: true));
    }
    _lastVideoPlaying = isPlaying;
  }

  Future<void> _handleVideoReachedEnd() async {
    if (_videoEnded) return;
    _videoEnded = true;
    final controller = _videoController;
    if (controller != null && controller.value.isPlaying) {
      await controller.pause();
      await controller.seekTo(Duration.zero);
    }
    await _stopSoundPreview();
    if (mounted) setState(() {});
  }

  Future<void> _syncSoundWithVideoPlayback({required bool playing}) async {
    if (!_usesSeparateSoundPreview) return;
    final player = _soundPlayer;
    final controller = _videoController;
    if (player == null || controller == null || !controller.value.isInitialized) {
      return;
    }

    final duration = controller.value.duration;
    final position = controller.value.position;
    if (duration.inMilliseconds <= 0) return;

    try {
      if (!playing) {
        await player.pause();
        return;
      }

      _videoEnded = false;
      final maxPosition = duration - const Duration(milliseconds: 50);
      final targetPosition = position > maxPosition ? maxPosition : position;
      final trackPosition =
          Duration(milliseconds: widget.postSoundStartOffsetMilliseconds) +
              targetPosition;
      await player.seek(trackPosition);
      await player.resume();

      final remaining = duration - targetPosition;
      if (remaining > Duration.zero) {
        Future.delayed(remaining, () async {
          if (!mounted || _videoEnded) return;
          final c = _videoController;
          if (c == null || !c.value.isInitialized) return;
          if (c.value.position >= c.value.duration - const Duration(milliseconds: 200)) {
            await _handleVideoReachedEnd();
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _handlePlayPause() async {
    if (!mounted) return;
    if (_videoController != null && _videoController!.value.isInitialized) {
      if (_videoController!.value.isPlaying) {
        await _videoController!.pause();
        await _syncSoundWithVideoPlayback(playing: false);
        _hidePauseIcon();
      } else {
        if (_videoEnded) {
          _videoEnded = false;
          await _videoController!.seekTo(Duration.zero);
          if (_usesSeparateSoundPreview) {
            await _prepareSeparateSoundPreview();
          }
        }
        await _videoController!.play();
        await _syncSoundWithVideoPlayback(playing: true);
        _showPauseIconTemporarily();
      }
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _showPauseIconTemporarily() {
    if (!mounted) return;
    setState(() {
      _showPauseIcon = true;
    });

    _pauseIconTimer?.cancel();
    _pauseIconTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _showPauseIcon = false;
        });
      }
    });
  }

  void _hidePauseIcon() {
    _pauseIconTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _showPauseIcon = false;
    });
  }

  void _videoErrorListener() {
    if (_videoController != null && _videoController!.value.hasError) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_videoController!.value.errorDescription ??
                'Unknown video error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _onVisibilityChanged(VisibilityInfo visibilityInfo) {
    if (!mounted) return;
    final isVisible = visibilityInfo.visibleFraction >= 1.0;

    if (_isVideoVisible != isVisible) {
      _isVideoVisible = isVisible;

      if (_videoController != null && _videoController!.value.isInitialized) {
        if (!isVisible && _videoController!.value.isPlaying) {
          _wasPlayingBeforeVisibilityChange = true;
          _videoController!.pause();
          unawaited(_syncSoundWithVideoPlayback(playing: false));
          _hidePauseIcon();
        } else if (isVisible && _wasPlayingBeforeVisibilityChange) {
          _wasPlayingBeforeVisibilityChange = false;
          _videoController!.play();
          unawaited(_syncSoundWithVideoPlayback(playing: true));
          _showPauseIconTemporarily();
        }
      }
    }
  }

  Widget _buildVideoSurface() {
    final controller = _videoController!;
    final videoSize = controller.value.size;
    if (videoSize.width <= 0 || videoSize.height <= 0) {
      return VideoPlayer(controller);
    }

    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: videoSize.width,
        height: videoSize.height,
        child: VideoPlayer(controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => VisibilityDetector(
        key: Key('video_preview_${widget.mediaEditItem.originalPath}'),
        onVisibilityChanged: _onVisibilityChanged,
        child: GestureDetector(
          onTap: () => unawaited(_handlePlayPause()),
          child: Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.black,
            child: _videoController != null &&
                    _videoController!.value.isInitialized
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      _buildVideoSurface(),
                      AnimatedOpacity(
                        opacity: _videoController!.value.isPlaying
                            ? (_showPauseIcon ? 1.0 : 0.0)
                            : 1.0,
                        duration: const Duration(milliseconds: 300),
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _videoController!.value.isPlaying
                                ? Icons.pause
                                : Icons.play_arrow,
                            color: Colors.white,
                            size: 40,
                          ),
                        ),
                      ),
                    ],
                  )
                : Container(
                    color: widget.mediaEditConfig.backgroundColor,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(
                              color: widget.mediaEditConfig.primaryColor),
                          const SizedBox(height: 16),
                          Text(
                            'Loading video...',
                            style: TextStyle(
                                color: widget.mediaEditConfig.primaryTextColor),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      );
}
