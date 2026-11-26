import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:ism_video_reel_player/res/res.dart';
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
    /// Post/create flows use [AssetConstants.postResponseJson] by default.
    this.lottieAsset,
  });

  final String title;
  final String subtitle;
  final Color primaryColor;
  final Color textColor;
  final Color backgroundColor;
  final String? fontFamily;
  final double? progress;
  final String? lottieAsset;

  Widget _buildHeroAnimation() {
    final asset = lottieAsset ?? AssetConstants.postResponseJson;
    final resolved = AssetConstants.resolveAsset(asset);
    return SizedBox(
      height: 88.h,
      width: 88.w,
      child: Lottie.asset(
        resolved.path,
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

  @override
  Widget build(BuildContext context) {
    final showDeterminate = progress != null && progress! > 0 && progress! < 100;

    return Material(
      color: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.52)),
          ),
          Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 28.w),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: backgroundColor,
                  boxShadow: [
                    BoxShadow(
                      color: primaryColor.withValues(alpha: 0.22),
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
                      _buildHeroAnimation(),
                      SizedBox(height: 12.h),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: fontFamily,
                          fontSize: 18.sp,
                          fontWeight: FontWeight.w700,
                          color: textColor,
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
                          color: textColor.withValues(alpha: 0.72),
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
                      ] else
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