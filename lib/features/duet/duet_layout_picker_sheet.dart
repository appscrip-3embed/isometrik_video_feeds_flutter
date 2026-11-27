import 'package:flutter/material.dart';
import 'package:ism_video_reel_player/features/duet/duet_layout.dart';
import 'package:ism_video_reel_player/isr_video_reel_config.dart';
import 'package:ism_video_reel_player/res/res.dart';

/// Bottom sheet to pick left-right / top-bottom / PiP before duet capture.
///
/// Returns the chosen [DuetLayout], or null if dismissed.
class DuetLayoutPickerSheet extends StatelessWidget {
  const DuetLayoutPickerSheet({
    super.key,
    this.initialLayout = DuetLayout.leftRight,
  });

  final DuetLayout initialLayout;

  static Future<DuetLayout?> show(
    BuildContext context, {
    DuetLayout initialLayout = DuetLayout.leftRight,
  }) {
    return showModalBottomSheet<DuetLayout>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DuetLayoutPickerSheet(initialLayout: initialLayout),
    );
  }

  Color get _backgroundColor =>
      IsrVideoReelConfig
          .socialConfig.colorsConfig?.bottomSheetBackgroundColor ??
      IsrColors.white;

  Color get _textColor => IsrColors.primaryTextColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _backgroundColor,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _textColor.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                IsrTranslationFile.duetChooseLayout,
                textAlign: TextAlign.center,
                style: IsrStyles.primaryText18.copyWith(
                  fontWeight: FontWeight.w600,
                  color: _textColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                IsrTranslationFile.duetChooseLayoutSubtitle,
                textAlign: TextAlign.center,
                style: IsrStyles.primaryText14.copyWith(
                  color: _textColor.withValues(alpha: 0.65),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  for (final layout in DuetLayout.values) ...[
                    if (layout != DuetLayout.values.first)
                      const SizedBox(width: 10),
                    Expanded(
                      child: _LayoutOption(
                        layout: layout,
                        selected: layout == initialLayout,
                        textColor: _textColor,
                        onTap: () => Navigator.pop(context, layout),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  IsrTranslationFile.cancel,
                  style: IsrStyles.primaryText16.copyWith(color: _textColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LayoutOption extends StatelessWidget {
  const _LayoutOption({
    required this.layout,
    required this.selected,
    required this.textColor,
    required this.onTap,
  });

  final DuetLayout layout;
  final bool selected;
  final Color textColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? IsrColors.appColor
                : textColor.withValues(alpha: 0.2),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            SizedBox(
              height: 64,
              child: _LayoutPreviewIcon(layout: layout, color: textColor),
            ),
            const SizedBox(height: 8),
            Text(
              DuetLayoutGeometry.label(layout),
              textAlign: TextAlign.center,
              style: IsrStyles.primaryText12.copyWith(
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              DuetLayoutGeometry.subtitle(layout),
              textAlign: TextAlign.center,
              style: IsrStyles.primaryText10.copyWith(
                color: textColor.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LayoutPreviewIcon extends StatelessWidget {
  const _LayoutPreviewIcon({required this.layout, required this.color});

  final DuetLayout layout;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fill = color.withValues(alpha: 0.15);
    final border = color.withValues(alpha: 0.45);
    switch (layout) {
      case DuetLayout.leftRight:
        return Row(
          children: [
            Expanded(child: _box(fill, border)),
            const SizedBox(width: 3),
            Expanded(child: _box(fill, border)),
          ],
        );
      case DuetLayout.topBottom:
        return Column(
          children: [
            Expanded(child: _box(fill, border)),
            const SizedBox(height: 3),
            Expanded(child: _box(fill, border)),
          ],
        );
      case DuetLayout.pip:
        return Stack(
          children: [
            Positioned.fill(child: _box(fill, border)),
            Positioned(
              right: 4,
              bottom: 4,
              width: 22,
              height: 28,
              child: _box(fill, border, radius: 4),
            ),
          ],
        );
    }
  }

  Widget _box(Color fill, Color border, {double radius = 6}) => Container(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: border),
        ),
      );
}
