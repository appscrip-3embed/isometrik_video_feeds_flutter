import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:ism_video_reel_player/res/res.dart';
import 'package:ism_video_reel_player/utils/processing_overlay_lottie.dart';
import 'package:lottie/lottie.dart';

/// Branded full-screen blocker for sound mux, media prep, and post setup.
class IsrProcessingOverlay extends StatelessWidget {
  const IsrProcessingOverlay({
    super.key,
    required this.title,
    required this.subtitle,
    required this.primaryColor,
    this.textColor = Colors.black,
    this.backgroundColor = Colors.white,
    this.fontFamily,
    this.progress,
    /// When null, uses [ProcessingOverlayLottie.resolve] (SDK or host config).
    this.lottieAsset,
    this.lottiePackage,
    this.useThemeSurfaces = true,
  });

  final String title;
  final String subtitle;
  final Color primaryColor;
  final Color textColor;
  final Color backgroundColor;
  final String? fontFamily;
  final double? progress;
  final String? lottieAsset;
  final String? lottiePackage;

  /// Uses [ThemeData.colorScheme] for card/text when host colors are not passed.
  final bool useThemeSurfaces;

  ProcessingOverlayLottieRef _resolveHeroAsset(BuildContext context) {
    if (lottieAsset != null && lottieAsset!.isNotEmpty) {
      if (lottiePackage != null && lottiePackage!.isNotEmpty) {
        return (path: lottieAsset!, package: lottiePackage);
      }
      if (lottieAsset!.startsWith('packages/')) {
        return AssetConstants.resolveAsset(lottieAsset!);
      }
      return (path: lottieAsset!, package: null);
    }
    return ProcessingOverlayLottie.resolveFromContext(context);
  }

  Widget _buildHeroAnimation(BuildContext context) {
    final resolved = _resolveHeroAsset(context);
    final path = resolved.path;
    final isGif = path.toLowerCase().endsWith('.gif');
    final size = isGif ? 120.h : 88.h;

    if (isGif) {
      return SizedBox(
        height: size,
        width: size,
        child: Image.asset(
          path,
          package: resolved.package,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => Icon(
            Icons.movie_creation_outlined,
            size: 48.sp,
            color: primaryColor,
          ),
        ),
      );
    }

    return SizedBox(
      height: size,
      width: size,
      child: Lottie.asset(
        path,
        package: resolved.package,
        fit: BoxFit.contain,
        repeat: true,
        errorBuilder: (_, __, ___) => Icon(
          Icons.slideshow_rounded,
          size: 48.sp,
          color: primaryColor,
        ),
      ),
    );
  }

  bool _heroUsesAnimatedGif(BuildContext context) {
    return _resolveHeroAsset(context).path.toLowerCase().endsWith('.gif');
  }

  @override
  Widget build(BuildContext context) {
    final showDeterminate = progress != null && progress! > 0 && progress! < 100;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = useThemeSurfaces
        ? scheme.surfaceContainerHigh
        : backgroundColor;
    final titleColor = useThemeSurfaces ? scheme.onSurface : textColor;
    final subtitleColor = useThemeSurfaces
        ? scheme.onSurfaceVariant
        : textColor.withValues(alpha: 0.72);
    final scrimAlpha = isDark ? 0.72 : 0.52;

    return Material(
      color: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: ColoredBox(color: Colors.black.withValues(alpha: scrimAlpha)),
          ),
          Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 28.w),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: cardColor,
                  border: isDark
                      ? Border.all(color: scheme.outline.withValues(alpha: 0.25))
                      : null,
                  boxShadow: [
                    BoxShadow(
                      color: primaryColor.withValues(alpha: isDark ? 0.35 : 0.22),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(24.w, 28.h, 24.w, 24.h),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildHeroAnimation(context),
                      SizedBox(height: 12.h),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: fontFamily,
                          fontSize: 18.sp,
                          fontWeight: FontWeight.w700,
                          color: titleColor,
                          height: 1.25,
                        ),
                      ),
                      SizedBox(height: 8.h),
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: fontFamily,
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w400,
                          color: subtitleColor,
                          height: 1.35,
                        ),
                      ),
                      SizedBox(height: 20.h),
                      if (showDeterminate) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress! / 100,
                            minHeight: 5,
                            backgroundColor: primaryColor.withValues(alpha: 0.15),
                            valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                          ),
                        ),
                        SizedBox(height: 8.h),
                        Text(
                          '${progress!.round()}%',
                          style: TextStyle(
                            fontFamily: fontFamily,
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w600,
                            color: primaryColor,
                          ),
                        ),
                      ] else if (!_heroUsesAnimatedGif(context))
                        SizedBox(
                          width: 36.w,
                          height: 36.w,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: primaryColor,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}