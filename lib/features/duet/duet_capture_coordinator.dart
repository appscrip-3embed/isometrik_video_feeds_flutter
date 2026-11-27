import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ism_video_reel_player/domain/domain.dart';
import 'package:ism_video_reel_player/features/duet/duet_capture_view.dart';
import 'package:ism_video_reel_player/features/duet/duet_composer.dart';
import 'package:ism_video_reel_player/features/duet/duet_layout.dart';
import 'package:ism_video_reel_player/features/duet/duet_layout_picker_sheet.dart';
import 'package:ism_video_reel_player/features/duet/duet_session.dart';
import 'package:ism_video_reel_player/isr_video_reel_config.dart';
import 'package:ism_video_reel_player/presentation/screens/create_post_multimedia/create_post_flow_coordinator.dart';
import 'package:ism_video_reel_player/presentation/screens/media/media_edit/media_edit.dart'
    as me;
import 'package:ism_video_reel_player/presentation/screens/widgets/isr_processing_overlay.dart';
import 'package:ism_video_reel_player/res/res.dart';
import 'package:ism_video_reel_player/utils/utils.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Public entry for Instagram-style duet from an existing reel.
///
/// Mirrors [DubWithAudioCaptureCoordinator]: gate → layout → capture →
/// compose → media editor → post attributes.
///
/// Standalone: enable via [PostConfig.enableDuet]. Do not call from create-post.
///
/// Prep UX: a root [OverlayEntry] is inserted the moment a layout is tapped
/// (before the sheet finishes closing). Navigator dialogs race the sheet
/// dismiss animation and were invisible for 10–15s during download — do not
/// go back to showDialog/DialogRoute for this gate.
abstract final class DuetCaptureCoordinator {
  DuetCaptureCoordinator._();

  static const int _maxDownloadBytes = 120 * 1024 * 1024;

  static Future<void> handleFromPost(
    BuildContext context,
    TimeLineData post, {
    DuetConfig? config,
    Future<void> Function(TimeLineData post)? customHandler,
  }) async {
    if (customHandler != null) {
      await customHandler(post);
      return;
    }

    if (!await IsrAppNavigator.ensureCanCreateContent()) return;
    if (!context.mounted) return;

    final resolved = config ??
        IsrVideoReelConfig.postConfig.duetConfig ??
        const DuetConfig();

    if (post.isLocked == true) {
      if (resolved.onLockedPost != null) {
        resolved.onLockedPost!(context, post);
      } else {
        Utility.showToastMessage(IsrTranslationFile.duetLockedPostMessage);
      }
      return;
    }

    final canStart = resolved.canStart;
    if (canStart != null) {
      final allowed = await canStart(context, post);
      if (!allowed || !context.mounted) return;
    }

    final videoUrl = ReelDubAudioUtil.reelVideoUrlForDub(post);
    if (videoUrl == null) {
      Utility.showToastMessage(IsrTranslationFile.duetNoVideoMessage);
      return;
    }

    // Insert "Preparing for duet" on layout tap — before the sheet pops — so
    // the feed is never interactive during dismiss + download.
    final prepOverlay = DuetPrepOverlayHandle();
    final layout = await DuetLayoutPickerSheet.show(
      context,
      initialLayout: resolved.defaultLayout,
      onLayoutChosen: () {
        if (!context.mounted) return;
        prepOverlay.show(
          context,
          title: IsrTranslationFile.duetPreparingTitle,
          subtitle: IsrTranslationFile.duetPreparingSubtitle,
        );
      },
    );
    if (layout == null || !context.mounted) {
      prepOverlay.hide();
      return;
    }

    // Sheet may have returned before onLayoutChosen ran in edge cases —
    // ensure the blocker is up before any async prep work.
    if (!prepOverlay.isShowing) {
      prepOverlay.show(
        context,
        title: IsrTranslationFile.duetPreparingTitle,
        subtitle: IsrTranslationFile.duetPreparingSubtitle,
      );
    }

    await start(
      context,
      post: post,
      layout: layout,
      videoUrl: videoUrl,
      config: resolved,
      prepOverlay: prepOverlay,
    );
  }

  static Future<void> start(
    BuildContext context, {
    required TimeLineData post,
    required DuetLayout layout,
    required String videoUrl,
    DuetConfig config = const DuetConfig(),
    DuetPrepOverlayHandle? prepOverlay,
  }) async {
    if (!context.mounted) return;

    final overlay = prepOverlay ?? DuetPrepOverlayHandle();
    if (!overlay.isShowing) {
      overlay.show(
        context,
        title: IsrTranslationFile.duetPreparingTitle,
        subtitle: IsrTranslationFile.duetPreparingSubtitle,
      );
    }

    try {
      // Already gated in [handleFromPost]; re-check in case start() is called
      // directly from another entry.
      if (!await IsrAppNavigator.ensureCanCreateContent()) return;
      if (!context.mounted) return;

      await IsrVideoReelConfig.releaseFeedDecodersForHeavyOverlay();
      if (!context.mounted) return;

      final localOriginal = await _resolveLocalVideo(videoUrl);
      if (!context.mounted) return;
      if (localOriginal == null) {
        Utility.showToastMessage(IsrTranslationFile.duetDownloadFailedMessage);
        return;
      }

      final durationSeconds = ReelDubAudioUtil.reelVideoDurationSecondsForDub(
        post,
        fallback: config.maxDurationSeconds,
      );

      final session = DuetSession(
        sourcePostId: post.id ?? '',
        originalVideoPath: localOriginal,
        layout: layout,
        originalDurationSeconds: durationSeconds,
      );

      // Keep overlay up until capture is on-screen, then remove it.
      final rootNav = Navigator.of(context, rootNavigator: true);
      final capturedFuture = rootNav.push<DuetSession>(
        MaterialPageRoute(
          builder: (_) => DuetCaptureView(
            session: session,
            config: config,
            onComposeClip: (s) => DuetComposer.compose(
              originalPath: s.originalVideoPath,
              userPath: s.userClipPath!,
              layout: s.layout,
              flipUserClipHorizontally: s.userFrontCamera,
              pipNormalizedOffset: s.pipNormalizedOffset,
            ),
          ),
        ),
      );
      // Let capture paint one frame under the overlay, then drop the blocker.
      WidgetsBinding.instance.addPostFrameCallback((_) => overlay.hide());

      final captured = await capturedFuture;
      if (!context.mounted) return;
      if (captured == null) return;

      final composed = captured.composedOutputPath?.trim();
      if (composed == null || composed.isEmpty) {
        if (captured.userClipPath != null &&
            captured.userClipPath!.isNotEmpty) {
          Utility.showToastMessage(IsrTranslationFile.duetComposeFailedMessage);
        }
        return;
      }

      final editItem = me.MediaEditItem(
        originalPath: composed,
        mediaType: me.EditMediaType.video,
        width: DuetLayoutGeometry.outputSize.width,
        height: DuetLayoutGeometry.outputSize.height,
        duration: durationSeconds,
        metaData: {
          'duet_source_post_id': captured.sourcePostId,
          'duet_layout': captured.layout.name,
          'duet_user_source': captured.userSource?.name,
          'duet_pip_nx': captured.pipNormalizedOffset.dx,
          'duet_pip_ny': captured.pipNormalizedOffset.dy,
        },
      );

      final edited = await IsrAppNavigator.presentCreatePostMediaEditor(
        context,
        mediaItems: [editItem],
        allowAddMoreMedia: false,
        onDismissEntireFlow: () =>
            IsrAppNavigator.dismissCreatePostFlow(context),
      );
      if (!context.mounted) return;
      if (edited == null || edited.isEmpty) return;

      final mediaDataList =
          CreatePostFlowCoordinator.mediaDataFromEditItems(edited);
      await IsrAppNavigator.presentCreatePostFromMedia(
        context,
        mediaDataList: mediaDataList,
        dismissEntireFlowOnClose: true,
      );
    } catch (e, st) {
      AppLog.error('DuetCaptureCoordinator editor handoff: $e\n$st');
      Utility.showToastMessage(IsrTranslationFile.duetComposeFailedMessage);
    } finally {
      overlay.hide();
      IsrVideoReelConfig.releasePlaybackSuppression();
    }
  }

  static Future<String?> _resolveLocalVideo(String videoPathOrUrl) async {
    if (!videoPathOrUrl.startsWith('http://') &&
        !videoPathOrUrl.startsWith('https://')) {
      final file = File(videoPathOrUrl);
      if (await file.exists()) return file.path;
      return null;
    }

    final uri = Uri.tryParse(videoPathOrUrl);
    if (uri == null) return null;

    final tempDir = await getTemporaryDirectory();
    final downloaded = File(
      path.join(tempDir.path, 'duet_original_${const Uuid().v4()}.mp4'),
    );
    try {
      final request = http.Request('GET', uri);
      final response = await http.Client().send(request).timeout(
            const Duration(minutes: 2),
          );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final sink = downloaded.openWrite();
      var total = 0;
      await for (final chunk in response.stream) {
        total += chunk.length;
        if (total > _maxDownloadBytes) {
          await sink.close();
          if (await downloaded.exists()) await downloaded.delete();
          return null;
        }
        sink.add(chunk);
      }
      await sink.close();
      if (await downloaded.length() < 64) {
        if (await downloaded.exists()) await downloaded.delete();
        return null;
      }
      return downloaded.path;
    } catch (e, st) {
      AppLog.error('DuetCaptureCoordinator download: $e\n$st');
      try {
        if (await downloaded.exists()) await downloaded.delete();
      } catch (_) {}
      return null;
    }
  }
}

/// Root-overlay blocker for duet prep (decoder release + original download).
///
/// Uses [OverlayEntry] instead of [showDialog] so it appears even while the
/// layout sheet is still dismissing (navigator route pushes race that
/// animation and were invisible).
///
/// Reuse: call [show] as early as the user commits to a layout, keep up
/// through async prep, [hide] only when the next full-screen route is ready.
final class DuetPrepOverlayHandle {
  OverlayEntry? _entry;

  bool get isShowing => _entry != null;

  /// Synchronously inserts a full-screen absorbing blocker on the root overlay.
  void show(
    BuildContext context, {
    required String title,
    required String subtitle,
  }) {
    if (!context.mounted) return;
    hide();

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      AppLog.error(
        'DuetPrepOverlayHandle: no root Overlay — preparing UI skipped',
      );
      return;
    }

    // Same branded visual as compose ("Creating duet / Combining both videos")
    // — host GIF/Lottie via [IsrProcessingOverlay] / processingOverlayLottiePath.
    _entry = OverlayEntry(
      builder: (ctx) => Material(
        type: MaterialType.transparency,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ModalBarrier(dismissible: false, color: Colors.transparent),
            IsrProcessingOverlay(
              title: title,
              subtitle: subtitle,
              primaryColor: IsrColors.appColor,
            ),
          ],
        ),
      ),
    );
    overlay.insert(_entry!);
  }

  void hide() {
    final entry = _entry;
    _entry = null;
    if (entry == null) return;
    try {
      entry.remove();
    } catch (e, st) {
      AppLog.error('DuetPrepOverlayHandle.hide: $e\n$st');
    }
  }
}
