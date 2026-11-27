import 'package:flutter/material.dart';
import 'package:ism_video_reel_player/features/duet/duet_layout.dart';

/// Shared layout shell for duet preview / capture / review.
///
/// Pass any widgets for [originalPane] and [userPane] (video player,
/// camera preview, placeholders). Prefer reusing this over duplicating
/// Row/Column/Stack split logic in other screens.
class DuetStage extends StatelessWidget {
  const DuetStage({
    super.key,
    required this.layout,
    required this.originalPane,
    required this.userPane,
    this.dividerColor = Colors.white24,
    this.dividerThickness = 1.5,
    this.pipBorderRadius = 12,
  });

  final DuetLayout layout;
  final Widget originalPane;
  final Widget userPane;
  final Color dividerColor;
  final double dividerThickness;
  final double pipBorderRadius;

  @override
  Widget build(BuildContext context) {
    switch (layout) {
      case DuetLayout.leftRight:
        return Row(
          children: [
            Expanded(child: _clip(originalPane)),
            Container(width: dividerThickness, color: dividerColor),
            Expanded(child: _clip(userPane)),
          ],
        );
      case DuetLayout.topBottom:
        return Column(
          children: [
            Expanded(child: _clip(originalPane)),
            Container(height: dividerThickness, color: dividerColor),
            Expanded(child: _clip(userPane)),
          ],
        );
      case DuetLayout.pip:
        return LayoutBuilder(
          builder: (context, constraints) {
            final frame = Size(constraints.maxWidth, constraints.maxHeight);
            final pip = DuetLayoutGeometry.pipRect(frame);
            return Stack(
              fit: StackFit.expand,
              children: [
                _clip(originalPane),
                Positioned(
                  left: pip.left,
                  top: pip.top,
                  width: pip.width,
                  height: pip.height,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(pipBorderRadius),
                      border: Border.all(color: Colors.white, width: 1.5),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black54,
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(pipBorderRadius),
                      child: userPane,
                    ),
                  ),
                ),
              ],
            );
          },
        );
    }
  }

  Widget _clip(Widget child) => ClipRect(
        child: ColoredBox(
          color: Colors.black,
          child: child,
        ),
      );
}
