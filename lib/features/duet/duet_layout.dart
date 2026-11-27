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

  /// Default PiP corner: bottom-right within the padded frame (0–1).
  static const Offset pipDefaultNormalizedOffset = Offset(1, 1);

  static Offset clampPipNormalized(Offset offset) => Offset(
        offset.dx.clamp(0.0, 1.0),
        offset.dy.clamp(0.0, 1.0),
      );

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
        return 'You in a corner — drag to move';
    }
  }

  /// PiP size for [frame] (ignores position).
  static Size pipSize(Size frame) => Size(
        frame.width * pipWidthFraction,
        frame.height * pipHeightFraction,
      );

  /// Margin from each edge so the PiP stays inset.
  static double pipMargin(Size frame) => frame.width * pipMarginFraction;

  /// PiP rect in [frame] coordinates.
  ///
  /// [normalizedTopLeft] is 0–1 within the draggable area:
  /// (0,0) top-left inset, (1,1) bottom-right (default).
  static Rect pipRect(
    Size frame, {
    Offset normalizedTopLeft = pipDefaultNormalizedOffset,
  }) {
    final size = pipSize(frame);
    final m = pipMargin(frame);
    final minLeft = m;
    final minTop = m;
    final maxLeft = (frame.width - size.width - m).clamp(minLeft, frame.width);
    final maxTop =
        (frame.height - size.height - m).clamp(minTop, frame.height);
    final n = clampPipNormalized(normalizedTopLeft);
    final left = minLeft + (maxLeft - minLeft) * n.dx;
    final top = minTop + (maxTop - minTop) * n.dy;
    return Rect.fromLTWH(left, top, size.width, size.height);
  }

  /// Maps a desired top-left into a clamped 0–1 offset for [pipRect].
  static Offset pipNormalizedFromTopLeft(Size frame, Offset topLeft) {
    final size = pipSize(frame);
    final m = pipMargin(frame);
    final minLeft = m;
    final minTop = m;
    final maxLeft = (frame.width - size.width - m).clamp(minLeft, frame.width);
    final maxTop =
        (frame.height - size.height - m).clamp(minTop, frame.height);
    final spanX = maxLeft - minLeft;
    final spanY = maxTop - minTop;
    final nx = spanX <= 0 ? 1.0 : ((topLeft.dx - minLeft) / spanX);
    final ny = spanY <= 0 ? 1.0 : ((topLeft.dy - minTop) / spanY);
    return clampPipNormalized(Offset(nx, ny));
  }
}
