import 'dart:io';

import 'package:ism_video_reel_player/domain/domain.dart';
import 'package:ism_video_reel_player/isr_video_reel_config.dart';
import 'package:ism_video_reel_player/presentation/presentation.dart';
import 'package:ism_video_reel_player/presentation/screens/media/media_edit/model/media_edit_audio_model.dart';
import 'package:ism_video_reel_player/presentation/screens/media/media_edit/model/media_edit_models.dart';
import 'package:ism_video_reel_player/utils/camera_gallery_sound_util.dart';
import 'package:ism_video_reel_player/utils/media_util.dart';
import 'package:ism_video_reel_player/utils/reel_dub_audio_util.dart';
import 'package:ism_video_reel_player/utils/utility.dart';

/// Maps camera / library sounds into post + media-edit models and muxes video.
abstract final class PostSoundUtil {
  /// Seconds of sound used per image slide in carousel / image posts.
  static int get imageSoundSecondsPerSlide =>
      IsrVideoReelConfig.postConfig.resolvedImagePostDurationSeconds;

  /// Legacy cap for image-only sound clips (prefer [imagePostSoundDurationSeconds]).
  static const int photoSoundClipMaxSeconds = 60;

  /// Total sound length for an image-only post: one slide duration per image.
  static int imagePostSoundDurationSeconds(int imageCount) {
    final count = imageCount < 1 ? 1 : imageCount;
    return count * imageSoundSecondsPerSlide;
  }

  static int imageCountFromMediaData(Iterable<MediaData> media) => media
      .where(
        (m) =>
            m.mediaType == 'image' ||
            m.postType?.toString().toLowerCase() == 'image',
      )
      .length;

  static int imageCountFromEditItems(Iterable<MediaEditItem> items) => items
      .where((item) => item.mediaType == EditMediaType.image)
      .length;

  /// Dwell/playback seconds for one carousel item (`mediaType` 0 = image).
  static int playbackDurationSecondsForCarouselMedia({
    required int mediaType,
    required int durationSeconds,
    int pictureMediaType = 0,
  }) {
    if (mediaType == pictureMediaType) {
      return imageSoundSecondsPerSlide;
    }
    return durationSeconds > 0 ? durationSeconds : imageSoundSecondsPerSlide;
  }

  static int imageSlideIndexAtCarouselPage<T>(
    List<T> items,
    int pageIndex,
    bool Function(T item) isImageSlide,
  ) {
    if (items.isEmpty || pageIndex <= 0) return 0;
    final end = pageIndex < items.length ? pageIndex : items.length;
    var imageIndex = 0;
    for (var i = 0; i < end; i++) {
      if (isImageSlide(items[i])) imageIndex++;
    }
    return imageIndex;
  }

  static int carouselItemDurationSecondsForEditItem(MediaEditItem item) {
    if (item.mediaType == EditMediaType.image) {
      return imageSoundSecondsPerSlide;
    }
    final d = item.duration ?? 0;
    return d > 0 ? d : 1;
  }

  static int carouselItemDurationSecondsForMediaMeta(MediaMetaData media) {
    return playbackDurationSecondsForCarouselMedia(
      mediaType: media.mediaType,
      durationSeconds: media.durationSeconds,
    );
  }

  /// Sound track offset (seconds) at the start of carousel page [pageIndex].
  static int carouselSoundStartOffsetSeconds<T>(
    List<T> items,
    int pageIndex,
    int Function(T item) durationSecondsFor,
  ) {
    var seconds = 0;
    for (var i = 0; i < pageIndex && i < items.length; i++) {
      seconds += durationSecondsFor(items[i]);
    }
    return seconds;
  }

  static int carouselSoundStartOffsetSecondsForEditItems(
    List<MediaEditItem> items,
    int pageIndex,
  ) =>
      carouselSoundStartOffsetSeconds(
        items,
        pageIndex,
        carouselItemDurationSecondsForEditItem,
      );

  static int carouselSoundStartOffsetSecondsForMediaMeta(
    List<MediaMetaData> items,
    int pageIndex,
  ) =>
      carouselSoundStartOffsetSeconds(
        items,
        pageIndex,
        carouselItemDurationSecondsForMediaMeta,
      );

  static int carouselPostSoundDurationSecondsFromMedia(List<MediaData> media) {
    var total = 0;
    for (final m in media) {
      if (_isVideoMedia(m)) {
        final sec = m.duration?.toInt() ?? 0;
        total += sec > 0 ? sec : 1;
      } else {
        total += imageSoundSecondsPerSlide;
      }
    }
    return total > 0 ? total : imageSoundSecondsPerSlide;
  }

  static int carouselPostSoundDurationSecondsFromEditItems(
    List<MediaEditItem> items,
  ) {
    if (items.isEmpty) return imageSoundSecondsPerSlide;
    var total = 0;
    for (final item in items) {
      total += carouselItemDurationSecondsForEditItem(item);
    }
    return total;
  }

  /// Post-level soundtrack overlay (no per-video mux) for multi-slide carousels.
  static bool useCarouselPostSoundOverlayForEditItems(List<MediaEditItem> items) =>
      items.length > 1;

  static bool useCarouselPostSoundOverlayForPlayback(List<MediaMetaData> items) =>
      items.length > 1;

  /// First attached soundtrack on any carousel item (e.g. after sound on slide 1).
  static MediaEditSoundItem? firstSoundOnEditItems(Iterable<MediaEditItem> items) {
    for (final item in items) {
      final sound = item.sound;
      if (sound == null) continue;
      final hasId = sound.soundId?.trim().isNotEmpty == true;
      final hasUrl = sound.soundUrl?.trim().isNotEmpty == true;
      if (hasId || hasUrl) return sound;
    }
    return null;
  }

  /// Applies [sound] to every slide when the post uses carousel-level audio.
  static void applySoundToAllEditItems(
    List<MediaEditItem> items,
    MediaEditSoundItem sound,
  ) {
    for (var i = 0; i < items.length; i++) {
      items[i] = items[i].copyWith(sound: sound);
    }
  }

  /// Library sounds from `/api/v1/sounds/*` — not temporary `dub_*` ids.
  static bool isLibrarySoundId(String? soundId) {
    final id = soundId?.trim() ?? '';
    if (id.isEmpty) return false;
    if (id.startsWith('dub_')) return false;
    return true;
  }

  /// Client-side id for “original audio” extracted from another reel (`dub_${postId}`).
  static bool isDubExtractedSoundId(String? soundId) {
    final id = soundId?.trim() ?? '';
    return id.startsWith('dub_');
  }

  /// Reels with no library sound still expose “Original audio” when video is dubbable.
  static bool postOffersOriginalAudioDub(TimeLineData post) {
    if (isLibrarySoundId(post.sound?.id) || isLibrarySoundId(post.soundId)) {
      return false;
    }
    return ReelDubAudioUtil.reelVideoUrlForDub(post) != null;
  }

  /// Synthetic [PostSoundInfo] for the overlay + sound-detail entry (no `sound_id` on API).
  static PostSoundInfo? syntheticOriginalAudioSound(TimeLineData post) {
    if (!postOffersOriginalAudioDub(post)) return null;
    final durationSeconds = ReelDubAudioUtil.reelVideoDurationSecondsForDub(post);
    final track = ReelDubAudioUtil.dubSoundTrackForPost(
      audioFilePath: '',
      post: post,
      durationSeconds: durationSeconds,
    );
    return PostSoundInfo(
      id: track.id,
      title: track.title,
      artist: track.author,
      thumbnailUrl: track.thumbnailUrl.isNotEmpty ? track.thumbnailUrl : null,
      durationSeconds: track.duration.inSeconds.toDouble(),
      usageCount: 1,
    );
  }

  /// Library attribution when present; otherwise synthetic original audio for video reels.
  static PostSoundInfo? effectiveSoundAttribution({
    PostSoundInfo? librarySound,
    TimeLineData? post,
  }) {
    if (librarySound != null && librarySound.hasId) return librarySound;
    if (post == null) return null;
    return syntheticOriginalAudioSound(post);
  }

  static bool showsSoundAttribution({
    PostSoundInfo? librarySound,
    TimeLineData? post,
  }) =>
      effectiveSoundAttribution(librarySound: librarySound, post: post)?.hasId ==
      true;

  static MediaEditSoundItem? soundItemFromCamera(CameraBloc cameraBloc) {
    if (!cameraBloc.hasMusicSelected) return null;
    final id = cameraBloc.selectedMusicId;
    if (id == null || id.isEmpty) return null;
    return MediaEditSoundItem(
      soundId: id,
      soundUrl: cameraBloc.selectedMusicPreviewUrl,
      soundImage: cameraBloc.selectedMusicThumbnailUrl,
      soundArtist: cameraBloc.selectedMusicArtist,
      soundDuration: cameraBloc.selectedMusicDurationSeconds?.toString(),
      soundMetadata: {
        'title': cameraBloc.selectedMusicName,
        'start_time': cameraBloc.selectedMusicStartOffsetSec
            .clamp(0.0, 86400.0),
      },
    );
  }

  /// User-selected offset into the full library track (seconds).
  static int soundTrackStartOffsetSeconds(MediaEditSoundItem? sound) {
    final ms = soundTrackStartOffsetMilliseconds(sound);
    return (ms / 1000).round();
  }

  /// Sub-second start offset for preview / seek.
  static int soundTrackStartOffsetMilliseconds(MediaEditSoundItem? sound) {
    if (sound == null) return 0;
    final fromMeta = _readNum(sound.soundMetadata?['start_time']);
    if (fromMeta != null && fromMeta > 0) {
      return (fromMeta * 1000).round();
    }
    return 0;
  }

  /// Track start + carousel slice position (create-post media edit preview).
  static int postSoundPreviewOffsetMilliseconds({
    MediaEditSoundItem? sound,
    int carouselSliceStartSeconds = 0,
  }) =>
      soundTrackStartOffsetMilliseconds(sound) +
      carouselSliceStartSeconds * 1000;

  /// When timeline or post detail returns only `sound_id`, fill display fields
  /// from `GET /api/v1/sounds/*` without dropping snapshot / usage_count.
  static PostSoundInfo mergeLibraryTrack(PostSoundInfo base, SoundTrack track) {
    final titleFromTrack = track.title.trim();
    final artistFromTrack = track.author.trim();
    return PostSoundInfo(
      id: base.id.isNotEmpty ? base.id : track.id,
      title: (base.title ?? '').trim().isNotEmpty
          ? base.title
          : (titleFromTrack.isNotEmpty ? titleFromTrack : null),
      artist: (base.artist ?? '').trim().isNotEmpty
          ? base.artist
          : (artistFromTrack.isNotEmpty ? artistFromTrack : null),
      album: base.album,
      type: base.type,
      usageCount: base.usageCount,
      previewUrl: (base.previewUrl ?? '').trim().isNotEmpty
          ? base.previewUrl
          : (track.trackUrl.trim().isNotEmpty ? track.trackUrl.trim() : null),
      thumbnailUrl: (base.thumbnailUrl ?? '').trim().isNotEmpty
          ? base.thumbnailUrl
          : (track.thumbnailUrl.trim().isNotEmpty
              ? track.thumbnailUrl.trim()
              : null),
      durationSeconds: (base.durationSeconds ?? 0) > 0
          ? base.durationSeconds
          : (track.duration.inSeconds > 0
              ? track.duration.inSeconds.toDouble()
              : null),
      snapshot: base.snapshot,
    );
  }

  /// Maps the post-detail `sound` field into the sound library [SoundTrack]
  /// used by the camera + sound-picker UI.
  static SoundTrack soundTrackFromPostSound(PostSoundInfo sound) {
    final seconds = sound.durationSeconds ?? 0;
    final duration = Duration(
      milliseconds: (seconds * 1000).round().clamp(0, 86400000),
    );
    return SoundTrack(
      id: sound.id,
      thumbnailUrl: sound.thumbnailUrl ?? '',
      trackUrl: sound.previewUrl ?? '',
      title: sound.title?.trim().isNotEmpty == true ? sound.title!.trim() : 'Untitled',
      author: sound.artist?.trim().isNotEmpty == true
          ? sound.artist!.trim()
          : 'Unknown artist',
      duration: duration,
    );
  }

  /// Build a [MediaEditSoundItem] from a post's sound attribution so the
  /// create-post flow can preselect / attribute the audio.
  static MediaEditSoundItem? soundItemFromPostSound(PostSoundInfo? sound) {
    if (sound == null || !sound.hasId) return null;
    return MediaEditSoundItem(
      soundId: sound.id,
      soundUrl: sound.previewUrl,
      soundImage: sound.thumbnailUrl,
      soundArtist: sound.artist,
      soundAlbum: sound.album,
      soundDuration: sound.durationSeconds?.round().toString(),
      soundMetadata: {
        if (sound.title != null) 'title': sound.title,
      },
    );
  }

  static MediaEditSoundItem soundItemFromTrack(
    SoundTrack track, {
    double startTimeSeconds = 0,
    int? segmentDurationSeconds,
  }) =>
      MediaEditSoundItem(
        soundId: track.id,
        soundUrl: track.trackUrl,
        soundImage: track.thumbnailUrl,
        soundArtist: track.author,
        soundDuration: track.duration.inSeconds.toString(),
        soundMetadata: {
          'title': track.title,
          'start_time': startTimeSeconds.clamp(0, 86400).toDouble(),
          if (segmentDurationSeconds != null)
            'segment_duration': segmentDurationSeconds,
          if (track.originalStatus != null && track.originalStatus!.isNotEmpty)
            'original_status': track.originalStatus,
        },
      );

  /// Builds `sound_snapshot` for POST `/api/v1/posts` (see API docs / stories).
  ///
  /// Timing fields describe the **sound clip** used on the post, not the full
  /// uploaded video length. Values are capped to a typical reel length (60s).
  static Map<String, dynamic> buildSoundSnapshot({
    required MediaEditSoundItem sound,
    int? videoDurationSeconds,
    int maxClipSec = 60,
  }) {
    const defaultSegmentSec = 30;

    final meta = sound.soundMetadata ?? {};
    final soundSec = int.tryParse(sound.soundDuration ?? '') ??
        _readInt(meta['duration_seconds']) ??
        0;
    final videoSec = videoDurationSeconds ?? 0;

    var startTime = _readNum(meta['start_time']) ?? 0.0;
    if (startTime < 0) startTime = 0.0;

    var segmentDuration = _readInt(meta['segment_duration']) ??
        (soundSec > 0 ? soundSec : defaultSegmentSec);
    if (segmentDuration > maxClipSec) segmentDuration = maxClipSec;
    if (videoSec > 0 && segmentDuration > videoSec) {
      segmentDuration = videoSec > maxClipSec ? maxClipSec : videoSec;
    }
    if (segmentDuration <= 0) segmentDuration = defaultSegmentSec;

    var endTime = _readNum(meta['end_time']) ?? startTime + segmentDuration;
    if (endTime <= startTime) endTime = startTime + segmentDuration;
    if (soundSec > 0 && endTime > soundSec) {
      endTime = soundSec.toDouble();
      final span = endTime - startTime;
      segmentDuration = span.clamp(1.0, segmentDuration.toDouble()).round();
    }

    final snapshot = <String, dynamic>{
      'captured_at': DateTime.now().toUtc().toIso8601String(),
      'start_time': startTime,
      'end_time': endTime,
      'segment_duration': segmentDuration,
      'volume': 1,
      'fade_in': 0,
      'fade_out': 0,
      'loop': false,
    };

    final originalStatus = meta['original_status'] as String?;
    if (originalStatus != null && originalStatus.trim().isNotEmpty) {
      snapshot['original_status'] = originalStatus.trim();
    }

    final title = (meta['title'] as String?)?.trim();
    if (title != null && title.isNotEmpty) {
      snapshot['title'] = title;
    }
    final artist = sound.soundArtist?.trim();
    if (artist != null && artist.isNotEmpty) {
      snapshot['artist'] = artist;
    }

    return snapshot;
  }

  /// Merges `sound_id` + `sound_snapshot` into POST `/api/v1/posts` body.
  static void mergeSoundIntoCreatePostJson({
    required Map<String, dynamic> body,
    required MediaEditSoundItem? sound,
    required List<MediaData> media,
  }) {
    if (sound == null || !isLibrarySoundId(sound.soundId)) return;

    final totalCarouselSec = carouselPostSoundDurationSecondsFromMedia(media);
    final clipCap = totalCarouselSec > 60 ? 60 : totalCarouselSec;

    body['sound_id'] = sound.soundId!.trim();
    body['sound_snapshot'] = buildSoundSnapshot(
      sound: sound,
      videoDurationSeconds: totalCarouselSec,
      maxClipSec: clipCap,
    );
  }

  static bool _isVideoMedia(MediaData m) =>
      m.mediaType == 'video' ||
      m.postType?.toString().toLowerCase().contains('video') == true;

  static int? _readInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static double? _readNum(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  /// Replaces video audio with the selected sound URL/path.
  static Future<String> muxVideoWithSound({
    required String videoPath,
    required MediaEditSoundItem sound,
    bool showLoader = true,
  }) async {
    final musicUrl = sound.soundUrl?.trim() ?? '';
    if (musicUrl.isEmpty) return videoPath;

    if (showLoader) await Utility.showLoader();
    try {
      final videoDurationSec = await MediaUtil.videoDurationSeconds(videoPath);
      final musicStart =
          (_readNum(sound.soundMetadata?['start_time']) ?? 0).clamp(0.0, 86400.0);
      final muxed = await MediaUtil.muxVideoWithMusicFromUrl(
        videoPath: videoPath,
        musicUrlOrPath: musicUrl,
        maxDurationSeconds:
            videoDurationSec > 0 ? videoDurationSec : null,
        musicStartOffsetSeconds: musicStart,
      );
      if (muxed != null &&
          muxed != videoPath &&
          await File(muxed).exists() &&
          await File(muxed).length() > 64) {
        return muxed;
      }
      return videoPath;
    } finally {
      if (showLoader) Utility.closeProgressDialog();
    }
  }

  static Future<String> applySoundToVideoWithCameraBloc({
    required CameraBloc cameraBloc,
    required String videoPath,
  }) async {
    final result = await CameraGallerySoundUtil.applySelectedSoundToVideo(
      cameraBloc: cameraBloc,
      videoPath: videoPath,
    );
    return result.videoPath;
  }
}
