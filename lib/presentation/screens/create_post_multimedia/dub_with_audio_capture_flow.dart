import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ism_video_reel_player/ism_video_reel_player.dart';
import 'package:ism_video_reel_player/presentation/screens/media/media_edit/media_edit.dart'
    as me;
import 'package:ism_video_reel_player/res/res.dart';
import 'package:ism_video_reel_player/utils/utils.dart';

class DubWithAudioCaptureCoordinator {
  DubWithAudioCaptureCoordinator._();

  static Future<void> handleFromPost(
    BuildContext context,
    TimeLineData post, {
    DubWithAudioConfig? config,
    Future<void> Function(TimeLineData post)? customHandler,
  }) async {
    if (customHandler != null) {
      await customHandler(post);
      return;
    }

    if (!await IsrAppNavigator.ensureCanCreateContent()) return;
    if (!context.mounted) return;

    if (post.isLocked == true) {
      if (config?.onLockedPost != null) {
        config!.onLockedPost!(context, post);
      } else {
        Utility.showToastMessage(IsrTranslationFile.dubLockedPostMessage);
      }
      return;
    }

    final canStart = config?.canStart;
    if (canStart != null) {
      final allowed = await canStart(context, post);
      if (!allowed || !context.mounted) return;
    }

    final videoUrl = ReelDubAudioUtil.reelVideoUrlForDub(post);
    if (videoUrl == null) {
      Utility.showToastMessage(IsrTranslationFile.dubNoVideoMessage);
      return;
    }

    final audioPath = await _extractAudioWithLoader(context, videoUrl);
    if (!context.mounted) return;

    if (audioPath == null) {
      Utility.showToastMessage(IsrTranslationFile.dubExtractAudioFailedMessage);
      return;
    }

    await start(
      context,
      CreatePostLaunchConfig.dubWithExtractedAudio(
        dubAudioFilePath: audioPath,
        dubSoundTrack: ReelDubAudioUtil.dubSoundTrackForPost(
          audioFilePath: audioPath,
          post: post,
          durationSeconds: ReelDubAudioUtil.reelVideoDurationSecondsForDub(post),
        ),
      ),
    );
  }

  static Future<void> start(
    BuildContext context,
    CreatePostLaunchConfig launchConfig,
  ) async {
    if (!await IsrAppNavigator.ensureCanCreateContent()) return;
    if (!context.mounted) return;
    final track = launchConfig.dubSoundTrack;
    final audioPath = launchConfig.dubAudioFilePath;
    if (track == null || audioPath == null || audioPath.isEmpty) return;

    final musicEvent = CameraSetMusicEvent(
      musicId: track.id,
      musicName: track.title,
      musicArtist: track.author,
      musicThumbnailUrl: track.thumbnailUrl,
      musicDurationSeconds: track.duration.inSeconds,
      musicPreviewUrl: audioPath,
    );

    final capture = await IsrAppNavigator.presentCameraCapture(
      context,
      mediaType: MediaType.video.name,
      dubWithAudioMode: true,
      initialCameraMusic: musicEvent,
      dubSoundPickerTracks: [track],
      onDismissEntireFlow: () => IsrAppNavigator.dismissCreatePostFlow(context),
    );

    if (!context.mounted) return;
    if (capture == null || capture.mediaPath.isEmpty) return;

    // Instagram-style hand-off: the camera returns the raw clip (no mux, see
    // CameraBloc.deferSoundMuxToEditor), the editor opens right away and plays
    // the sound as an overlay, and the real mux runs in the background so Next
    // is near-instant. The editor generates its own single-frame thumbnail.
    final editItem = me.MediaEditItem(
      originalPath: capture.mediaPath,
      mediaType: me.EditMediaType.video,
      width: 0,
      height: 0,
      duration: track.duration.inSeconds,
      sound: PostSoundUtil.soundItemFromTrack(track),
    );
    PostSoundUtil.prewarmMuxVideoWithSound(
      videoPath: editItem.originalPath,
      sound: editItem.sound!,
    );

    try {
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
    } finally {
      // No-op if Next already claimed the result; otherwise frees the file.
      SoundMuxPrewarmCache.discard();
    }
  }

  static Future<String?> _extractAudioWithLoader(
    BuildContext context,
    String videoUrl,
  ) async {
    try {
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          useRootNavigator: true,
          builder: (_) => const PopScope(
            canPop: false,
            child: Center(child: AppLoader()),
          ),
        ),
      );
      return await MediaUtil.extractAudioFromVideoToM4a(videoUrl);
    } finally {
      if (context.mounted) {
        final nav = Navigator.of(context, rootNavigator: true);
        if (nav.canPop()) nav.pop();
      }
    }
  }

}
