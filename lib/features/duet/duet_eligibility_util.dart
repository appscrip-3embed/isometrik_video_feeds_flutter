import 'package:ism_video_reel_player/domain/models/reels_data.dart';
import 'package:ism_video_reel_player/domain/models/response/timeline_response.dart';
import 'package:ism_video_reel_player/utils/enums.dart';
import 'package:ism_video_reel_player/utils/reel_dub_audio_util.dart';
import 'package:ism_video_reel_player/utils/timeline_media_type_util.dart';
import 'package:ism_video_reel_player/utils/timeline_post_type_util.dart';

import 'duet_config.dart';

/// When to show Duet in more-options.
///
/// Post `type`: `video` | `image` | `text` | `carousel`. Media items use
/// `media_type: video` or `media_type: image`.
abstract final class DuetEligibilityUtil {
  DuetEligibilityUtil._();

  static const int kVideoMediaMetaType = 1;

  static bool postHasDuetableVideo(TimeLineData post) {
    if (TimelinePostTypeUtil.isTextPost(post)) return false;

    if (ReelDubAudioUtil.reelVideoUrlForDub(post) != null) return true;

    final meta = reelMediaMetaDataFromTimeline(post);
    if (meta.any((m) => m.mediaType == kVideoMediaMetaType)) return true;

    if (TimelineMediaTypeUtil.isVideoPostType(post.type) && meta.isNotEmpty) {
      return meta.any((m) => m.mediaType == kVideoMediaMetaType);
    }

    final media = post.media;
    if (media != null) {
      return media.any(
        (m) =>
            m.postType == PostType.video ||
            TimelineMediaTypeUtil.isVideo(m.mediaType),
      );
    }

    return false;
  }

  /// Fallback when [TimeLineData.media] is sparse but the reels player already
  /// resolved playback metadata (vertical For You / Following feed).
  static bool reelsDataHasVideo(ReelsData reelsData) =>
      reelsData.mediaMetaDataList
          .any((m) => m.mediaType == kVideoMediaMetaType);

  static bool shouldOfferDuet(
    TimeLineData post, {
    required bool enableDuet,
    DuetConfig? duetConfig,
    ReelsData? reelsData,
  }) {
    if (!enableDuet) return false;

    final cfg = duetConfig ?? const DuetConfig();
    if (cfg.respectPostDuetEnabledSetting && post.settings?.duetEnabled == false) {
      return false;
    }

    if (postHasDuetableVideo(post)) return true;
    if (reelsData != null && reelsDataHasVideo(reelsData)) return true;
    return false;
  }
}