import 'dart:async';
import 'dart:io' show Platform;

import 'package:ism_video_reel_player/domain/domain.dart';
import 'package:ism_video_reel_player/isr_video_reel_config.dart';
import 'package:ism_video_reel_player/presentation/presentation.dart';
import 'package:ism_video_reel_player/utils/isr_active_video_player_registry.dart';
import 'package:ism_video_reel_player/utils/utils.dart';

/// Instagram-style reels precache: sliding window around the visible index.
///
/// **Data:** Hive / host [FeedCacheRepository] (app layer) supplies post metadata.
/// **Media:** Thumbnails + light cache for [mediaPrecacheAheadCount] reels ahead;
/// full decoders only for [effectiveAheadCount] (Android caps surfaces).
///
/// **Decoder budget (reuse later):** Android keeps at most **one** warm decoder
/// ahead of the visible reel (no behind warm). Combined with the visible player
/// that matches [StandardVideoNonPreloadedManager] soft-cap (~2 live). Warming
/// behind + ahead used to pin 2 extra decoders while the current one played,
/// which starved MediaCodec and looked like "minutes to load" 15–60s clips.
///
/// Reuse from [PostItemWidget] on page change, mid-swipe scroll, and after
/// pagination — not from profile-only players.
class ReelsFeedPrecacheCoordinator {
  ReelsFeedPrecacheCoordinator._();

  /// Native decoders to keep ready just below the current reel (iOS/desktop).
  static const int aheadCount = 2;

  /// Thumbnails + HLS first-segment / light warm for this many reels ahead.
  static const int mediaPrecacheAheadCount = 10;

  /// Begin loading the next feed page when this many reels remain (was 5).
  static const int loadMoreRemainingReels = 10;

  /// Android SurfaceView / MediaCodec budget — only one reel ahead.
  static int get effectiveAheadCount => Platform.isAndroid ? 1 : aheadCount;

  /// Scroll-back warm decoder. Off on Android so live count stays ≤ soft-cap.
  static int get behindCount => Platform.isAndroid ? 0 : 1;

  static bool _isVideoMedia(MediaMetaData media) =>
      media.mediaType == MediaType.video.value &&
      media.mediaUrl.trim().isNotEmpty;

  /// Primary video URL on a reel (first video in carousel).
  static String? primaryVideoUrl(ReelsData reel) {
    for (final media in reel.mediaMetaDataList) {
      if (_isVideoMedia(media)) return media.mediaUrl;
    }
    return null;
  }

  static List<String> _thumbnailUrls(ReelsData reel) {
    final out = <String>[];
    for (final media in reel.mediaMetaDataList) {
      if (_isVideoMedia(media) && media.thumbnailUrl.isNotEmpty) {
        out.add(media.thumbnailUrl);
      } else if (media.mediaUrl.isNotEmpty &&
          media.mediaType != MediaType.video.value) {
        out.add(media.mediaUrl);
      }
    }
    return out;
  }

  /// Reel indices in the warm window for decoder init in [VideoPlayerWidget].
  static bool isWarmAheadSlot({
    required int reelIndex,
    required int currentIndex,
  }) {
    if (reelIndex == currentIndex) return false;
    final diff = reelIndex - currentIndex;
    if (diff >= 1 && diff <= effectiveAheadCount) return true;
    // behindCount == 0 on Android — do not treat current (diff 0) as warm-behind.
    if (behindCount > 0 && diff == -behindCount) return true;
    return false;
  }

  /// Updates pinned decoders and starts thumbnail + video warm-up.
  static void warmWindow({
    required VideoCacheManager cache,
    required List<ReelsData> reels,
    required int currentIndex,
  }) {
    if (!IsrVideoReelConfig.allowsPlayback) return;
    if (reels.isEmpty || currentIndex < 0) return;

    final decoderVideoUrls = <String>{};
    final lightVideoUrls = <String>{};
    final thumbUrls = <String>{};

    final maxOffset = mediaPrecacheAheadCount > effectiveAheadCount
        ? mediaPrecacheAheadCount
        : effectiveAheadCount;

    for (var offset = -behindCount; offset <= maxOffset; offset++) {
      final i = currentIndex + offset;
      if (i < 0 || i >= reels.length) continue;
      final reel = reels[i];
      thumbUrls.addAll(_thumbnailUrls(reel));
      final video = primaryVideoUrl(reel);
      if (video == null) continue;
      // Current reel (offset 0) is owned by the visible VideoPlayerWidget —
      // only pin ahead / optional behind so soft-cap stays at ~2 on Android.
      final needsDecoder =
          (behindCount > 0 && offset == -behindCount) ||
          (offset >= 1 && offset <= effectiveAheadCount);
      if (needsDecoder) {
        decoderVideoUrls.add(video);
      } else if (offset >= 1 && offset <= mediaPrecacheAheadCount) {
        lightVideoUrls.add(video);
      }
    }

    cache.setWarmPinnedReelVideoUrls(decoderVideoUrls);

    if (thumbUrls.isNotEmpty) {
      unawaited(
        MediaCacheFactory.precacheMedia(thumbUrls.toList(), highPriority: true),
      );
    }
    if (decoderVideoUrls.isNotEmpty) {
      unawaited(
        cache.precacheMedia(decoderVideoUrls.toList(), highPriority: true),
      );
    }
    if (lightVideoUrls.isNotEmpty) {
      unawaited(
        cache.precacheMedia(lightVideoUrls.toList(), highPriority: false),
      );
    }

    // Release decoders on reels that scrolled outside the warm window.
    IsrActiveVideoPlayerRegistry.releasePreloadedMemory();
  }

  /// True when the feed should request the next page of posts.
  static bool shouldPrefetchFeedPage({
    required int index,
    required int listLength,
  }) {
    if (listLength <= 0) return false;
    if (index >= listLength - 1) return true;
    return index >= listLength - loadMoreRemainingReels;
  }
}