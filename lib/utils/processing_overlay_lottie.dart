import 'package:flutter/material.dart';
import 'package:ism_video_reel_player/ism_video_reel_player.dart';
import 'package:ism_video_reel_player/res/res.dart';

/// Resolves the hero asset for [IsrProcessingOverlay] (host override or SDK default).
typedef ProcessingOverlayLottieRef = ({String path, String? package});

abstract final class ProcessingOverlayLottie {
  ProcessingOverlayLottie._();

  static ProcessingOverlayLottieRef resolve() {
    final uiConfig =
        IsrVideoReelConfig.createEditPostConfig.createEditPostUIConfig;
    final hostPath = uiConfig?.processingOverlayLottiePath?.trim();
    if (hostPath != null && hostPath.isNotEmpty) {
      return (path: hostPath, package: uiConfig?.processingOverlayLottiePackage);
    }
    return AssetConstants.resolveAsset(AssetConstants.reelPreparingMinimal);
  }

  static ProcessingOverlayLottieRef resolveFromContext(BuildContext context) =>
      resolve();
}