import 'package:flutter/widgets.dart';
import 'package:ism_video_reel_player/domain/models/duet_config.dart'
    show DuetLayout;

export 'package:ism_video_reel_player/domain/models/duet_config.dart'
    show DuetLayout;

/// Geometry helpers for live preview and FFmpeg export.
///
/// Reuse this instead of hard-coding split ratios in capture / compose.
abstract final class DuetLayoutGeometry {
  DuetLayoutGeometry._();

  /// Output canvas size used by the composer (9:16 reel).
  static const Size outputSize = Size(720, 1280);

  /// PiP inset as a fraction of the full frame (width / height).
  static const double pipWidthFraction = 0.35;
  static const double pipHeightFraction = 0.28;
  static const double pipMarginFraction = 0.04;

  /// Title shown in the layout picker sheet.
  static String label(DuetLayout layout) {
    switch (layout) {
      case DuetLayout.leftRight:
        return 'Left · Right';
      case DuetLayout.topBottom:
        return 'Top · Bottom';
      case DuetLayout.pip:
        return 'Picture in Picture';
    }
  }

  /// Short subtitle under each layout option.
  static String subtitle(DuetLayout layout) {
    switch (layout) {
      case DuetLayout.leftRight:
        return 'Side by side';
      case DuetLayout.topBottom:
        return 'Stacked';
      case DuetLayout.pip:
        return 'You in the corner';
    }
  }

  /// PiP rect in [frame] coordinates (bottom-right with margin).
  static Rect pipRect(Size frame) {
    final w = frame.width * pipWidthFraction;
    final h = frame.height * pipHeightFraction;
    final m = frame.width * pipMarginFraction;
    return Rect.fromLTWH(
      frame.width - w - m,
      frame.height - h - m,
      w,
      h,
    );
  }
}
