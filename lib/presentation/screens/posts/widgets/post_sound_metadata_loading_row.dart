import 'package:flutter/material.dart';
import 'package:ism_video_reel_player/presentation/screens/posts/widgets/post_sound_icon.dart';
import 'package:ism_video_reel_player/res/res.dart';
import 'package:ism_video_reel_player/utils/extensions.dart';
import 'package:shimmer/shimmer.dart';

/// Placeholder while `GET /api/v1/posts/detail` hydrates `sound` title/artist
/// (timeline/reels list often returns only `sound_id`).
class PostSoundMetadataLoadingRow extends StatelessWidget {
  const PostSoundMetadataLoadingRow({
    super.key,
    this.style = PostSoundMetadataLoadingStyle.reels,
    this.textShimmerWidth = 132,
    this.textShimmerHeight,
  });

  final PostSoundMetadataLoadingStyle style;
  final double textShimmerWidth;
  final double? textShimmerHeight;

  static Color _baseOnDark() => IsrColors.white.changeOpacity(0.22);
  static Color _highlightOnDark() => IsrColors.white.changeOpacity(0.42);
  static Color _baseOnLight() => IsrColors.black.changeOpacity(0.08);
  static Color _highlightOnLight() => IsrColors.black.changeOpacity(0.14);

  @override
  Widget build(BuildContext context) {
    final onDark = style == PostSoundMetadataLoadingStyle.reels;
    final base = onDark ? _baseOnDark() : _baseOnLight();
    final highlight = onDark ? _highlightOnDark() : _highlightOnLight();
    final textHeight =
        textShimmerHeight ?? (onDark ? 14.0 : IsrDimens.twelve.toDouble());

    Widget shimmerBar({required double width, required double height}) =>
        Shimmer.fromColors(
          baseColor: base,
          highlightColor: highlight,
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: base,
              borderRadius: BorderRadius.circular(height / 2),
            ),
          ),
        );

    switch (style) {
      case PostSoundMetadataLoadingStyle.reels:
        final discSize = 20.responsiveDimension;
        return IgnorePointer(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Shimmer.fromColors(
                baseColor: base,
                highlightColor: highlight,
                child: Container(
                  width: discSize,
                  height: discSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: base,
                    border: Border.all(
                      color: IsrColors.white.changeOpacity(0.35),
                      width: 1,
                    ),
                  ),
                ),
              ),
              IsrDimens.boxWidth(IsrDimens.six),
              Flexible(
                child: shimmerBar(
                  width: textShimmerWidth,
                  height: textHeight,
                ),
              ),
            ],
          ),
        );
      case PostSoundMetadataLoadingStyle.feedInline:
        return IgnorePointer(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Shimmer.fromColors(
                baseColor: base,
                highlightColor: highlight,
                child: Opacity(
                  opacity: 0.55,
                  child: PostSoundIcon(
                    size: IsrDimens.twelve,
                    style: PostSoundIconStyle.feed,
                    color: IsrColors.black.changeOpacity(0.35),
                  ),
                ),
              ),
              IsrDimens.boxWidth(IsrDimens.four),
              Flexible(
                child: shimmerBar(
                  width: textShimmerWidth,
                  height: textHeight,
                ),
              ),
            ],
          ),
        );
    }
  }
}

enum PostSoundMetadataLoadingStyle {
  reels,
  feedInline,
}