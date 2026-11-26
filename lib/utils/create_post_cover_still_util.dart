import 'package:ism_video_reel_player/domain/domain.dart';
import 'package:ism_video_reel_player/utils/enums.dart';
import 'package:ism_video_reel_player/utils/extensions.dart';

/// Resolves the cover still shown on create-post / upload ([PostAttributeView]).
///
/// Keeps Tag People and other child routes aligned with the user-picked
/// **Change cover** image (`createPostRequest.previews`), not auto video thumbs.
abstract final class CreatePostCoverStillUtil {
  static String? resolve({
    CreatePostRequest? request,
    List<PreviewMedia>? previews,
    List<MediaData>? media,
  }) {
    final preview = previews?.firstOrNull ?? request?.previews?.firstOrNull;
    final local = preview?.localFilePath?.trim();
    if (local != null && local.isNotEmpty) return local;

    final remote = preview?.url?.trim();
    if (remote != null && remote.isNotEmpty) return remote;

    final mediaList = media ?? request?.media;
    final firstMedia = mediaList?.firstOrNull;
    final mediaPreview = firstMedia?.previewUrl?.trim();
    if (mediaPreview != null && mediaPreview.isNotEmpty) return mediaPreview;

    final coverOnMedia = firstMedia?.coverFileLocalPath?.trim();
    if (coverOnMedia != null && coverOnMedia.isNotEmpty) return coverOnMedia;

    final photoInCarousel = mediaList
        ?.where((m) => m.mediaType?.mediaType == MediaType.photo)
        .firstOrNull;
    final photoPath = photoInCarousel?.localPath?.trim() ??
        photoInCarousel?.url?.trim();
    if (photoPath != null && photoPath.isNotEmpty) return photoPath;

    return null;
  }

  static String? fromPostAttribute(PostAttributeClass? attribute) =>
      resolve(
        request: attribute?.createPostRequest,
        media: attribute?.mediaDataList,
      );
}