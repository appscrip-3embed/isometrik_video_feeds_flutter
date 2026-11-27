import 'package:ism_video_reel_player/utils/enums.dart';

/// Timeline `media_type` values from the API (`video`, `image`, …).
///
/// Reuse for duet/dub eligibility, [MediaData.fromMap], and download — do not
/// invent types like `reel` at the media level; post-level `type` may be
/// `video` / `image` / `text` / `carousel` separately.
abstract final class TimelineMediaTypeUtil {
  TimelineMediaTypeUtil._();

  static bool isVideo(String? mediaType) {
    final t = (mediaType ?? '').trim().toLowerCase();
    if (t.isEmpty) return false;
    return t == 'video' || t.contains('video');
  }

  static bool isImage(String? mediaType) {
    final t = (mediaType ?? '').trim().toLowerCase();
    if (t.isEmpty) return false;
    return t == 'image' || t.contains('image');
  }

  static PostType postTypeFromMediaType(String? mediaType) =>
      isVideo(mediaType) ? PostType.video : PostType.photo;

  /// Post-level `type` field (`video`, `image`, `text`, `carousel`, …).
  static bool isVideoPostType(String? postType) {
    final t = (postType ?? '').trim().toLowerCase();
    return t == 'video' || t == 'carousel';
  }
}