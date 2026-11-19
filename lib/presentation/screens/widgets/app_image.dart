import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:ism_video_reel_player/ism_video_reel_player.dart';
import 'package:ism_video_reel_player/presentation/screens/posts/widgets/feed_profile_initials_placeholder.dart';
import 'package:ism_video_reel_player/res/res.dart';
import 'package:ism_video_reel_player/utils/utils.dart';

class AppImage extends StatelessWidget {
  const AppImage.asset(
    this.path, {
    super.key,
    this.name = '',
    this.fit,
    this.isProfileImage = false,
    this.dimensions,
    this.height,
    this.width,
    this.radius,
    this.borderRadius,
    this.border,
    this.padding,
    this.placeHolderName,
    this.fadeAnimationEnable,
    this.filterQuality,
    this.textColor,
    this.blendMode,
    this.placeHolderWidget,
  })  : _imageType = ImageType.asset,
        showError = false,
        color = null,
        cacheKey = null,
        cacheManager = null,
        package = null,
        memCacheWidth = null,
        memCacheHeight = null;

  const AppImage.svg(
    this.path, {
    super.key,
    this.name = '',
    this.fit,
    this.isProfileImage = false,
    this.dimensions,
    this.height,
    this.width,
    this.radius,
    this.color,
    this.borderRadius,
    this.border,
    this.padding,
    this.placeHolderName,
    this.fadeAnimationEnable,
    this.filterQuality,
    this.textColor,
    this.blendMode,
    this.placeHolderWidget,
    this.package,
  })  : _imageType = ImageType.svg,
        showError = false,
        cacheKey = null,
        cacheManager = null,
        memCacheWidth = null,
        memCacheHeight = null;

  const AppImage.network(
    this.path, {
    super.key,
    this.name = '',
    this.fit,
    this.isProfileImage = false,
    this.dimensions,
    this.height,
    this.width,
    this.radius,
    this.borderRadius,
    this.border,
    this.showError = true,
    this.padding,
    this.placeHolderName,
    this.fadeAnimationEnable,
    this.filterQuality,
    this.textColor,
    this.blendMode,
    this.placeHolderWidget,
    this.cacheKey,
    this.cacheManager,
    this.memCacheWidth,
    this.memCacheHeight,
  })  : _imageType = ImageType.network,
        color = null,
        package = null;

  const AppImage.file(
    this.path, {
    super.key,
    this.name = '',
    this.fit,
    this.isProfileImage = false,
    this.dimensions,
    this.height,
    this.width,
    this.radius,
    this.borderRadius,
    this.border,
    this.padding,
    this.placeHolderName,
    this.fadeAnimationEnable,
    this.filterQuality,
    this.textColor,
    this.blendMode,
    this.placeHolderWidget,
  })  : _imageType = ImageType.file,
        showError = false,
        color = null,
        cacheKey = null,
        cacheManager = null,
        package = null,
        memCacheWidth = null,
        memCacheHeight = null;

  final String path;
  final String name;
  final bool isProfileImage;
  final double? dimensions;
  final double? height;
  final double? width;
  final double? radius;
  final Color? color;
  final BorderRadius? borderRadius;
  final ImageType _imageType;
  final Border? border;
  final bool showError;
  final EdgeInsets? padding;
  final String? placeHolderName;
  final Widget? Function(double? height, double? width)? placeHolderWidget;
  /// Stable disk/memory cache id (e.g. original URL). When null, [path] is used.
  final String? cacheKey;
  final BaseCacheManager? cacheManager;
  /// Decode width/height in physical pixels (Flutter image cache).
  final int? memCacheWidth;
  final int? memCacheHeight;
  final BoxFit? fit;
  final bool? fadeAnimationEnable;
  final BlendMode? blendMode;
  final FilterQuality? filterQuality;
  final Color? textColor;
  final String? package;

  @override
  Widget build(BuildContext context) => Container(
        height: height ?? dimensions,
        width: width ?? dimensions,
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: isProfileImage
              ? null
              : borderRadius ?? BorderRadius.circular(radius ?? 0),
          shape: isProfileImage ? BoxShape.circle : BoxShape.rectangle,
          border: border,
        ),
        clipBehavior: Clip.antiAlias,
        child: switch (_imageType) {
          ImageType.asset =>
            _Asset(path, fit: fit, height: height, width: width),
          ImageType.svg =>
            _Svg(path, fit: fit, color: color, height: height, width: width, blendMode: blendMode, package: package,),
          ImageType.file => _File(
              path,
              fit: fit,
              height: height,
              width: width,
            ),
          ImageType.network => _Network(
              path,
              height: height,
              width: width,
              fit: fit,
              isProfileImage: isProfileImage,
              placeHolderWidget: placeHolderWidget ??
                  ((isProfileImage && name.trim().isNotEmpty)
                      ? null
                      : IsrVideoReelConfig
                          .socialConfig
                          .socialCallBackConfig
                          ?.placeHolderGenerator),
              name: name,
              showError: showError,
              placeHolderName: placeHolderName,
              borderRadius: borderRadius,
              fadeAnimationEnable: fadeAnimationEnable,
              filterQuality: filterQuality,
              textColor: textColor,
              cacheKey: cacheKey,
              cacheManager: cacheManager,
              memCacheWidth: memCacheWidth,
              memCacheHeight: memCacheHeight,
            ),
        },
      );
}

class _Asset extends StatelessWidget {
  const _Asset(
    this.path, {
    this.fit,
    this.height,
    this.width,
  });

  final String path;
  final BoxFit? fit;
  final double? height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final resolved = AssetConstants.resolveAsset(path);
    return Image.asset(
      resolved.path,
      package: resolved.package,
      fit: fit,
      height: height,
      width: width,
    );
  }
}

class _File extends StatelessWidget {
  const _File(
    this.path, {
    this.fit,
    this.height,
    this.width,
  });

  final String path;
  final BoxFit? fit;
  final double? height;
  final double? width;

  @override
  Widget build(BuildContext context) => Image.file(
        File(path),
        fit: fit ?? BoxFit.cover,
        height: height,
        width: width,
      );
}

class _Network extends StatefulWidget {
  const _Network(
    this.imageUrl, {
    required this.name,
    required this.isProfileImage,
    required this.showError,
    this.placeHolderWidget,
    this.fit,
    this.placeHolderName,
    this.height,
    this.width,
    this.borderRadius,
    this.fadeAnimationEnable = false,
    this.filterQuality,
    this.textColor,
    this.cacheKey,
    this.cacheManager,
    this.memCacheWidth,
    this.memCacheHeight,
  });

  final String imageUrl;
  final String? cacheKey;
  final BaseCacheManager? cacheManager;
  final String name;
  final String? placeHolderName;
  final Widget? Function(double? height, double? width)? placeHolderWidget;
  final bool isProfileImage;
  final bool showError;
  final BoxFit? fit;
  final double? height;
  final double? width;
  final BorderRadius? borderRadius;
  final bool? fadeAnimationEnable;
  final FilterQuality? filterQuality;
  final Color? textColor;
  final int? memCacheWidth;
  final int? memCacheHeight;

  @override
  State<_Network> createState() => _NetworkState();
}

class _NetworkState extends State<_Network> {
  bool _usedOriginalFallback = false;

  @override
  void didUpdateWidget(covariant _Network oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _usedOriginalFallback = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fullName =
        widget.name.isStringEmptyOrNull == false ? widget.name.trim() : '';
    final words =
        fullName.split(RegExp(r'\s+')).where((word) => word.isNotEmpty);
    final initials =
        words.take(2).map((word) => word[0]).join().toUpperCase();

    final cleanedUrl = preserveEmptyPathSegments(
      widget.imageUrl.trim().replaceAll(RegExp(r'[",]+$'), ''),
    );
    if (widget.isProfileImage && _isUnusableAvatarUrl(cleanedUrl)) {
      return _buildNetworkPlaceholder(
        context: context,
        initials: initials,
        customPlaceholder:
            widget.placeHolderWidget?.call(widget.height, widget.width),
      );
    }
    final originalUrl = Utility.resolveOriginalMediaUrl(cleanedUrl);
    final shouldConvertToGumlet = Utility.isGumletConversionEnabled() &&
        cleanedUrl.isNotEmpty &&
        !Utility.isLocalUrl(cleanedUrl) &&
        !Utility.isVideoMediaUrl(cleanedUrl) &&
        (Utility.isGcsMediaUrl(originalUrl) ||
            Utility.isAlreadyGumletUrl(cleanedUrl) ||
            Utility.findGumletMapping(originalUrl) != null);
    final optimizedImageUrl = shouldConvertToGumlet
        ? Utility.buildGumletImageUrl(
            imageUrl: originalUrl,
            width: widget.width,
            height: widget.height,
          )
        : originalUrl;
    final loadUrl = _usedOriginalFallback && originalUrl != optimizedImageUrl
        ? originalUrl
        : optimizedImageUrl;

    final urlPath =
        Uri.tryParse(loadUrl)?.path.toLowerCase() ?? loadUrl.toLowerCase();
    final isSvgUrl =
        urlPath.endsWith('.svg') || loadUrl.toLowerCase().contains('.svg?');
    if (isSvgUrl) {
      return _buildNetworkSvg(loadUrl, initials);
    }

    final diskCacheKey = widget.cacheKey ?? originalUrl;

    // Cap decode size: explicit memCache* wins; else derive from layout + DPR
    // so full-screen reel thumbs don't keep multi‑MB bitmaps in imageCache.
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    var resolvedMemWidth = widget.memCacheWidth;
    var resolvedMemHeight = widget.memCacheHeight;
    if (resolvedMemWidth == null &&
        widget.width != null &&
        widget.width!.isFinite &&
        widget.width! > 0) {
      resolvedMemWidth = (widget.width! * dpr).round().clamp(64, 1080);
    }
    if (resolvedMemHeight == null &&
        widget.height != null &&
        widget.height!.isFinite &&
        widget.height! > 0) {
      resolvedMemHeight = (widget.height! * dpr).round().clamp(64, 1920);
    }

    return CachedNetworkImage(
      width: widget.width,
      imageUrl: loadUrl,
      cacheManager: widget.cacheManager,
      filterQuality: widget.filterQuality ?? FilterQuality.high,
      fit: widget.fit ?? BoxFit.cover,
      alignment: Alignment.center,
      cacheKey: diskCacheKey,
      memCacheWidth: resolvedMemWidth,
      memCacheHeight: resolvedMemHeight,
      useOldImageOnUrlChange: true,
      fadeInDuration: widget.fadeAnimationEnable ?? false
          ? const Duration(milliseconds: 300)
          : Duration.zero,
      fadeOutDuration: widget.fadeAnimationEnable ?? false
          ? const Duration(milliseconds: 300)
          : Duration.zero,
      placeholderFadeInDuration: Duration.zero,
      imageBuilder: (_, image) => ClipRRect(
        borderRadius: widget.borderRadius ?? BorderRadius.zero,
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            shape: widget.isProfileImage ? BoxShape.circle : BoxShape.rectangle,
            image: DecorationImage(image: image, fit: widget.fit ?? BoxFit.cover),
          ),
        ),
      ),
      placeholder: (context, url) => _buildNetworkPlaceholder(
        context: context,
        initials: initials,
        customPlaceholder:
            widget.placeHolderWidget?.call(widget.height, widget.width),
      ),
      errorWidget: (context, url, error) {
        if (!_usedOriginalFallback &&
            originalUrl.isNotEmpty &&
            originalUrl != loadUrl) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _usedOriginalFallback = true);
            }
          });
        }
        return _buildNetworkPlaceholder(
          context: context,
          initials: initials,
          customPlaceholder:
              widget.placeHolderWidget?.call(widget.height, widget.width),
        );
      },
    );
  }

  bool _isUnusableAvatarUrl(String url) {
    final value = url.trim().toLowerCase();
    if (value.isEmpty) return true;
    return value.contains('gravatar.com') ||
        value.contains('picsum.photos') ||
        value.contains('unjected.com/defaultpic') ||
        value.contains('d=identicon');
  }

  Widget _buildInitialsPlaceholder(String initials) => Container(
        width: widget.width,
        height: widget.height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: widget.isProfileImage ? BoxShape.circle : BoxShape.rectangle,
          color: const Color(0xFFE5F0FB),
          borderRadius: widget.isProfileImage ? null : widget.borderRadius,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              initials,
              style: IsrStyles.secondaryText14.copyWith(
                fontWeight: FontWeight.w600,
                color: IsrColors.appColor,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
            ),
          ),
        ),
      );

  /// Builds a network SVG image using SvgPicture.network
  Widget _buildNetworkSvg(String svgUrl, String initials) => ClipRRect(
        borderRadius: widget.borderRadius ?? BorderRadius.zero,
        child: SvgPicture.network(
          svgUrl,
          height: widget.height,
          width: widget.width,
          fit: widget.fit ?? BoxFit.cover,
          placeholderBuilder: (context) => widget.showError
              ? ImagePlaceHolder(
                  width: widget.width,
                  height: widget.height,
                  borderRadius: widget.borderRadius,
                  placeHolderName: widget.placeHolderName,
                  boxShape: widget.isProfileImage
                      ? BoxShape.circle
                      : BoxShape.rectangle,
                  child: widget.placeHolderWidget
                          ?.call(widget.height, widget.width) ??
                      (widget.name.isStringEmptyOrNull == false &&
                              widget.isProfileImage
                          ? FeedProfileInitialsPlaceholder(
                              initials: initials,
                              size: widget.height ?? widget.width ?? 36,
                              seed: widget.name,
                            )
                          : null),
                )
              : Container(
                  width: widget.width,
                  height: widget.height,
                  decoration: BoxDecoration(
                    color: Colors.black.changeOpacity(0.3),
                    borderRadius: widget.borderRadius,
                    shape: widget.isProfileImage
                        ? BoxShape.circle
                        : BoxShape.rectangle,
                  ),
                ),
        ),
      );

  Widget _buildNetworkPlaceholder({
    required BuildContext context,
    required String initials,
    Widget? customPlaceholder,
  }) {
    if (widget.isProfileImage && initials.isNotEmpty) {
      return _buildInitialsPlaceholder(initials);
    }
    if (customPlaceholder != null && widget.showError) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: customPlaceholder,
      );
    }
    if (widget.showError) {
      if (widget.name.isStringEmptyOrNull == false && widget.isProfileImage) {
        final avatarSize = widget.height ?? widget.width ?? 36;
        return FeedProfileInitialsPlaceholder(
          initials: initials,
          size: avatarSize,
          seed: widget.name,
        );
      }
      return ImagePlaceHolder(
        width: widget.width,
        height: widget.height,
        borderRadius: widget.borderRadius,
        placeHolderName: widget.placeHolderName,
        boxShape:
            widget.isProfileImage ? BoxShape.circle : BoxShape.rectangle,
        borderColor: widget.isProfileImage
            ? (Theme.of(context).brightness == Brightness.dark
                ? Colors.white.withValues(alpha: 0.9)
                : Colors.black.withValues(alpha: 0.12))
            : null,
        child: widget.name.isStringEmptyOrNull == false && widget.isProfileImage
            ? FeedProfileInitialsPlaceholder(
                initials: initials,
                size: widget.height ?? widget.width ?? 36,
                seed: widget.name,
              )
            : null,
      );
    }
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.black.changeOpacity(0.3),
        borderRadius: widget.borderRadius,
        shape: widget.isProfileImage ? BoxShape.circle : BoxShape.rectangle,
      ),
    );
  }
}

class _Svg extends StatelessWidget {
  const _Svg(
    this.path, {
    this.color,
    this.fit,
    this.height,
    this.width,
    this.blendMode,
    this.package,
  });

  final String path;
  final Color? color;
  final BoxFit? fit;
  final double? height;
  final double? width;
  final BlendMode? blendMode;
  final String? package;

  @override
  Widget build(BuildContext context) {
    final ({String path, String? package}) resolved = package != null
        ? (path: path, package: package)
        : AssetConstants.resolveAsset(path);
    return SvgPicture.asset(
      resolved.path,
      height: height,
      width: width,
      fit: fit ?? BoxFit.contain,
      package: resolved.package,
      colorFilter: color != null
          ? ColorFilter.mode(
              color!,
              blendMode ?? BlendMode.srcIn,
            )
          : null,
    );
  }
}
