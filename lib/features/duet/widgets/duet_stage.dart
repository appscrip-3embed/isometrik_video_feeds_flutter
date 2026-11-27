import 'package:flutter/material.dart';
import 'package:ism_video_reel_player/features/duet/duet_layout.dart';

/// Shared layout shell for duet preview / capture / review.
///
/// Pass any widgets for [originalPane] and [userPane] (video player,
/// camera preview, placeholders). Prefer reusing this over duplicating
/// Row/Column/Stack split logic in other screens.
///
/// PiP: [pipNormalizedOffset] is 0–1 within the padded frame (default bottom
/// right). When [pipDraggable] is true, the user inset can be dragged; report
/// via [onPipNormalizedOffsetChanged] so compose can match.
class DuetStage extends StatelessWidget {
  const DuetStage({
    super.key,
    required this.layout,
    required this.originalPane,
    required this.userPane,
    this.dividerColor = Colors.white24,
    this.dividerThickness = 1.5,
    this.pipBorderRadius = 12,
    this.pipNormalizedOffset = DuetLayoutGeometry.pipDefaultNormalizedOffset,
    this.pipDraggable = false,
    this.onPipNormalizedOffsetChanged,
  });

  final DuetLayout layout;
  final Widget originalPane;
  final Widget userPane;
  final Color dividerColor;
  final double dividerThickness;
  final double pipBorderRadius;

  /// 0,0 = top-left inset; 1,1 = bottom-right (default).
  final Offset pipNormalizedOffset;
  final bool pipDraggable;
  final ValueChanged<Offset>? onPipNormalizedOffsetChanged;

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
        return _DraggablePipStack(
          originalPane: _clip(originalPane),
          userPane: userPane,
          pipBorderRadius: pipBorderRadius,
          pipNormalizedOffset: pipNormalizedOffset,
          pipDraggable: pipDraggable,
          onPipNormalizedOffsetChanged: onPipNormalizedOffsetChanged,
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

class _DraggablePipStack extends StatefulWidget {
  const _DraggablePipStack({
    required this.originalPane,
    required this.userPane,
    required this.pipBorderRadius,
    required this.pipNormalizedOffset,
    required this.pipDraggable,
    this.onPipNormalizedOffsetChanged,
  });

  final Widget originalPane;
  final Widget userPane;
  final double pipBorderRadius;
  final Offset pipNormalizedOffset;
  final bool pipDraggable;
  final ValueChanged<Offset>? onPipNormalizedOffsetChanged;

  @override
  State<_DraggablePipStack> createState() => _DraggablePipStackState();
}

class _DraggablePipStackState extends State<_DraggablePipStack> {
  late Offset _normalized;

  @override
  void initState() {
    super.initState();
    _normalized = DuetLayoutGeometry.clampPipNormalized(
      widget.pipNormalizedOffset,
    );
  }

  @override
  void didUpdateWidget(covariant _DraggablePipStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pipNormalizedOffset != widget.pipNormalizedOffset) {
      _normalized = DuetLayoutGeometry.clampPipNormalized(
        widget.pipNormalizedOffset,
      );
    }
  }

  void _onPanUpdate(DragUpdateDetails details, Size frame) {
    if (!widget.pipDraggable) return;
    final current = DuetLayoutGeometry.pipRect(
      frame,
      normalizedTopLeft: _normalized,
    );
    final nextTopLeft = Offset(
      current.left + details.delta.dx,
      current.top + details.delta.dy,
    );
    final next = DuetLayoutGeometry.pipNormalizedFromTopLeft(frame, nextTopLeft);
    if (next == _normalized) return;
    setState(() => _normalized = next);
    widget.onPipNormalizedOffsetChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final frame = Size(constraints.maxWidth, constraints.maxHeight);
        final pip = DuetLayoutGeometry.pipRect(
          frame,
          normalizedTopLeft: _normalized,
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            widget.originalPane,
            Positioned(
              left: pip.left,
              top: pip.top,
              width: pip.width,
              height: pip.height,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: widget.pipDraggable
                    ? (d) => _onPanUpdate(d, frame)
                    : null,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(widget.pipBorderRadius),
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
                    borderRadius:
                        BorderRadius.circular(widget.pipBorderRadius),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        widget.userPane,
                        if (widget.pipDraggable)
                          const Positioned(
                            right: 6,
                            top: 6,
                            child: IgnorePointer(
                              child: Icon(
                                Icons.open_with,
                                color: Colors.white70,
                                size: 18,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
