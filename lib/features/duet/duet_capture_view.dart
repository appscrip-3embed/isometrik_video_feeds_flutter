import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ism_video_reel_player/features/duet/duet_config.dart';
import 'package:ism_video_reel_player/features/duet/duet_layout.dart';
import 'package:ism_video_reel_player/features/duet/duet_session.dart';
import 'package:ism_video_reel_player/features/duet/widgets/duet_stage.dart';
import 'package:ism_video_reel_player/presentation/screens/widgets/isr_processing_overlay.dart';
import 'package:ism_video_reel_player/res/res.dart';
import 'package:ism_video_reel_player/utils/app_log.dart';
import 'package:ism_video_reel_player/utils/utility.dart';
import 'package:video_player/video_player.dart';

/// Live duet capture: original reel + camera (or gallery) in [layout].
///
/// Standalone feature UI — opened only via [DuetCaptureCoordinator].
/// Pops with a [DuetSession] that includes [DuetSession.composedOutputPath] when
/// [onComposeClip] is provided (compose runs here so the feed never flashes).
typedef DuetComposeClipCallback = Future<String?> Function(DuetSession session);

class DuetCaptureView extends StatefulWidget {
  const DuetCaptureView({
    super.key,
    required this.session,
    this.config = const DuetConfig(),
    this.onComposeClip,
  });

  final DuetSession session;
  final DuetConfig config;

  /// FFmpeg compose on this screen behind [IsrProcessingOverlay], then pop.
  final DuetComposeClipCallback? onComposeClip;

  @override
  State<DuetCaptureView> createState() => _DuetCaptureViewState();
}

class _DuetCaptureViewState extends State<DuetCaptureView>
    with WidgetsBindingObserver {
  CameraController? _camera;
  VideoPlayerController? _originalPlayer;
  VideoPlayerController? _galleryPreview;
  bool _initializing = true;
  bool _recording = false;
  int _elapsedSeconds = 0;
  Timer? _timer;
  String? _error;
  bool _usingFront = true;
  bool _composing = false;

  int get _maxSeconds {
    final fromConfig = widget.config.maxDurationSeconds;
    final fromOriginal = widget.session.originalDurationSeconds;
    final capped = fromOriginal > 0 ? fromOriginal : fromConfig;
    return capped.clamp(1, fromConfig);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    try {
      await Future.wait([
        _initOriginalPlayer(),
        _initCamera(),
      ]);
    } catch (e, st) {
      AppLog.error('DuetCaptureView bootstrap: $e\n$st');
      if (mounted) {
        setState(() => _error = IsrTranslationFile.duetCameraFailedMessage);
      }
    } finally {
      if (mounted) setState(() => _initializing = false);
    }
  }

  Future<void> _initOriginalPlayer() async {
    final path = widget.session.originalVideoPath;
    final controller = path.startsWith('http')
        ? VideoPlayerController.networkUrl(Uri.parse(path))
        : VideoPlayerController.file(File(path));
    await controller.initialize();
    await controller.setLooping(true);
    await controller.setVolume(1);
    _originalPlayer = controller;
    if (mounted) setState(() {});
  }

  Future<void> _initCamera({CameraLensDirection? prefer}) async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw StateError('No cameras');
    }
    final wantFront = prefer == CameraLensDirection.front ||
        (prefer == null && _usingFront);
    final description = cameras.firstWhere(
      (c) => wantFront
          ? c.lensDirection == CameraLensDirection.front
          : c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    _usingFront = description.lensDirection == CameraLensDirection.front;

    final previous = _camera;
    // Duet export keeps the original reel's audio only — do not record mic.
    final controller = CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await controller.initialize();
    await previous?.dispose();
    _camera = controller;
    if (mounted) setState(() {});
  }

  Future<void> _flipCamera() async {
    if (_recording || _camera == null) return;
    await _initCamera(
      prefer: _usingFront
          ? CameraLensDirection.back
          : CameraLensDirection.front,
    );
  }

  Future<void> _startRecording() async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized || _recording) return;

    try {
      await _originalPlayer?.seekTo(Duration.zero);
      await _originalPlayer?.play();
      await camera.startVideoRecording();
      setState(() {
        _recording = true;
        _elapsedSeconds = 0;
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _elapsedSeconds++);
        if (_elapsedSeconds >= _maxSeconds) {
          unawaited(_stopRecording());
        }
      });
    } catch (e, st) {
      AppLog.error('DuetCaptureView startRecording: $e\n$st');
      Utility.showToastMessage(IsrTranslationFile.duetRecordFailedMessage);
    }
  }

  Future<void> _stopRecording() async {
    final camera = _camera;
    if (camera == null || !_recording) return;
    _timer?.cancel();
    try {
      final file = await camera.stopVideoRecording();
      await _originalPlayer?.pause();
      if (!mounted) return;
      setState(() => _recording = false);
      await _finishWithUserClip(
        file.path,
        DuetUserSource.camera,
      );
    } catch (e, st) {
      AppLog.error('DuetCaptureView stopRecording: $e\n$st');
      if (mounted) setState(() => _recording = false);
      Utility.showToastMessage(IsrTranslationFile.duetRecordFailedMessage);
    }
  }

  Future<void> _pickFromGallery() async {
    if (_recording || !widget.config.allowGalleryPick) return;
    try {
      final picked = await ImagePicker().pickVideo(
        source: ImageSource.gallery,
        maxDuration: Duration(seconds: _maxSeconds),
      );
      if (picked == null || !mounted) return;

      // Optional local preview of gallery clip before confirming.
      await _galleryPreview?.dispose();
      final preview = VideoPlayerController.file(File(picked.path));
      await preview.initialize();
      await preview.setLooping(true);
      await preview.play();
      _galleryPreview = preview;
      if (!mounted) return;

      final use = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(IsrTranslationFile.duetUseGalleryClip),
          content: AspectRatio(
            aspectRatio: preview.value.aspectRatio == 0
                ? 9 / 16
                : preview.value.aspectRatio,
            child: VideoPlayer(preview),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(IsrTranslationFile.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(IsrTranslationFile.confirm),
            ),
          ],
        ),
      );

      await preview.pause();
      if (use == true && mounted) {
        await _finishWithUserClip(
          picked.path,
          DuetUserSource.gallery,
        );
      }
    } catch (e, st) {
      AppLog.error('DuetCaptureView gallery: $e\n$st');
      Utility.showToastMessage(IsrTranslationFile.duetGalleryFailedMessage);
    }
  }

  Future<void> _finishWithUserClip(
    String clipPath,
    DuetUserSource source,
  ) async {
    final baseSession = widget.session.copyWith(
      userClipPath: clipPath,
      userSource: source,
    );

    final compose = widget.onComposeClip;
    if (compose == null) {
      if (!mounted) return;
      Navigator.of(context).pop(baseSession);
      return;
    }

    setState(() => _composing = true);
    try {
      final composed = await compose(baseSession);
      if (!mounted) return;
      if (composed == null || composed.isEmpty) {
        Utility.showToastMessage(IsrTranslationFile.duetComposeFailedMessage);
        setState(() => _composing = false);
        return;
      }
      Navigator.of(context).pop(
        baseSession.copyWith(composedOutputPath: composed),
      );
    } catch (e, st) {
      AppLog.error('DuetCaptureView compose: $e\n$st');
      if (mounted) {
        setState(() => _composing = false);
        Utility.showToastMessage(IsrTranslationFile.duetComposeFailedMessage);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      unawaited(camera.dispose());
      _camera = null;
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_initCamera());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    unawaited(_camera?.dispose() ?? Future.value());
    unawaited(_originalPlayer?.dispose() ?? Future.value());
    unawaited(_galleryPreview?.dispose() ?? Future.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_initializing)
              const Center(child: CircularProgressIndicator(color: Colors.white))
            else if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              )
            else
              DuetStage(
                layout: widget.session.layout,
                originalPane: _buildOriginalPane(),
                userPane: _buildUserPane(),
              ),
            if (_composing)
              Positioned.fill(
                child: IsrProcessingOverlay(
                  title: IsrTranslationFile.duetComposingTitle,
                  subtitle: IsrTranslationFile.duetComposingSubtitle,
                  primaryColor: IsrColors.appColor,
                ),
              ),
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Row(
                children: [
                  IconButton(
                    onPressed: _composing || _recording
                        ? null
                        : () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                  const Spacer(),
                  Text(
                    DuetLayoutGeometry.label(widget.session.layout),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _recording ? null : _flipCamera,
                    icon: const Icon(
                      Icons.cameraswitch_outlined,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            if (!_initializing && _error == null && !_composing)
              Positioned(
                left: 0,
                right: 0,
                bottom: 24,
                child: _buildBottomControls(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOriginalPane() {
    final player = _originalPlayer;
    if (player == null || !player.value.isInitialized) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2),
        ),
      );
    }
    return Center(
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: player.value.size.width,
          height: player.value.size.height,
          child: VideoPlayer(player),
        ),
      ),
    );
  }

  Widget _buildUserPane() {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Icon(Icons.videocam_off, color: Colors.white54),
        ),
      );
    }
    // Letterbox in-pane (matches FFmpeg export — full frame, black bars).
    return Center(
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: camera.value.previewSize?.height ?? 720,
          height: camera.value.previewSize?.width ?? 1280,
          child: CameraPreview(camera),
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    final progress = _maxSeconds == 0 ? 0.0 : _elapsedSeconds / _maxSeconds;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_recording)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '${_formatTime(_elapsedSeconds)} / ${_formatTime(_maxSeconds)}',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        if (_recording)
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 0, 40, 16),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              backgroundColor: Colors.white24,
              color: Colors.redAccent,
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            if (widget.config.allowGalleryPick)
              IconButton(
                onPressed: _recording ? null : _pickFromGallery,
                icon: const Icon(Icons.photo_library_outlined,
                    color: Colors.white, size: 28),
              )
            else
              const SizedBox(width: 48),
            GestureDetector(
              onTap: _recording ? _stopRecording : _startRecording,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 4),
                ),
                alignment: Alignment.center,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: _recording ? 28 : 56,
                  height: _recording ? 28 : 56,
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius:
                        BorderRadius.circular(_recording ? 6 : 28),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 48),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _recording
              ? IsrTranslationFile.duetTapToStop
              : IsrTranslationFile.duetTapToRecord,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }

  String _formatTime(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
