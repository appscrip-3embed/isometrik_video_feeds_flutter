import 'package:flutter/material.dart';
import 'package:ism_video_reel_player/isr_video_reel_config.dart';
import 'package:ism_video_reel_player/res/theme/isr_colors.dart';

/// Theme-aware colors for the sound picker flow.
///
/// Reads SDK theme config when primary color is set; otherwise uses host [ThemeData].
class SoundPickerTheme {
  SoundPickerTheme._(this._theme, {required bool usesSdkTheme})
      : _usesSdkTheme = usesSdkTheme;

  factory SoundPickerTheme.of(BuildContext context) {
    final themeConfig = IsrVideoReelConfig.socialConfig.themeConfig;
    if (themeConfig?.primaryColor != null) {
      final brightness = themeConfig?.brightness ?? Brightness.light;
      return SoundPickerTheme._(
        ThemeData(
          brightness: brightness,
          primaryColor: themeConfig!.primaryColor,
          scaffoldBackgroundColor: themeConfig.scaffoldBackgroundColor,
          colorScheme: ColorScheme.fromSeed(
            seedColor: themeConfig.primaryColor!,
            brightness: brightness,
            primary: themeConfig.primaryColor!,
            surface: themeConfig.scaffoldBackgroundColor ?? IsrColors.scaffoldColor,
          ),
        ),
        usesSdkTheme: true,
      );
    }
    return SoundPickerTheme._(Theme.of(context), usesSdkTheme: false);
  }

  final ThemeData _theme;
  final bool _usesSdkTheme;

  ColorScheme get _cs => _theme.colorScheme;

  bool get _isDark => _theme.brightness == Brightness.dark;

  Color get scaffoldBackground => _usesSdkTheme
      ? IsrColors.scaffoldColor
      : (_isDark ? const Color(0xFF0B0B0C) : _cs.surface);

  Color get appBarBackground => scaffoldBackground;

  Color get onSurface =>
      _usesSdkTheme ? IsrColors.primaryTextColor : _cs.onSurface;

  Color get onSurfaceSecondary => _usesSdkTheme
      ? IsrColors.secondaryTextColor
      : _cs.onSurfaceVariant.withValues(alpha: _isDark ? 0.85 : 0.9);

  Color get onSurfaceTertiary => _usesSdkTheme
      ? IsrColors.secondaryTextColor.withValues(alpha: 0.85)
      : _cs.onSurfaceVariant.withValues(alpha: _isDark ? 0.65 : 0.72);

  Color get onSurfaceHint => _usesSdkTheme
      ? IsrColors.secondaryTextColor.withValues(alpha: 0.7)
      : _cs.onSurfaceVariant.withValues(alpha: _isDark ? 0.45 : 0.55);

  Color get searchFieldFill => _usesSdkTheme
      ? AppColorsCompat.searchFieldFill(_isDark)
      : (_isDark
          ? Colors.white.withValues(alpha: 0.08)
          : _cs.surfaceContainerHighest.withValues(alpha: 0.85));

  /// Neutral inset surfaces (never host secondary — Dubly secondary is often red).
  Color get chipSurface => searchFieldFill;

  /// Unselected chips, thumbnails, and controls: light **primary** tint only.
  Color get filterChipBackground => _isDark
      ? Colors.white.withValues(alpha: 0.08)
      : selectionAccent.withValues(alpha: 0.1);

  Color get filterChipOnSelected => Colors.white;

  Color get filterChipOnUnselected => selectionAccent;

  Color get chipBorderUnselected => _isDark
      ? Colors.white.withValues(alpha: 0.15)
      : _cs.outline.withValues(alpha: 0.35);

  Color get selectionAccent =>
      _usesSdkTheme ? IsrColors.appColor : _cs.primary;

  Color get divider => _usesSdkTheme
      ? IsrColors.dividerColor
      : _cs.outlineVariant.withValues(alpha: _isDark ? 0.3 : 0.45);

  Color get cursor => selectionAccent;

  Color get playOverlayFill =>
      Colors.black.withValues(alpha: _isDark ? 0.45 : 0.38);

  Color get playIcon => Colors.white;

  /// Light lavender tile behind list thumbnails (Dubly purple tint).
  Color get musicThumbnailBackground => filterChipBackground;

  Color get musicThumbnailIcon => selectionAccent.withValues(alpha: 0.85);

  /// Elevated card on the start-time picker (white / dark surface, not flat grey).
  Color get trackSummaryCardFill => _isDark
      ? Colors.white.withValues(alpha: 0.06)
      : Colors.white;

  Color get trackSummaryCardBorder =>
      selectionAccent.withValues(alpha: _isDark ? 0.35 : 0.2);
}

/// Thumbnail on the purple bottom “selected sound” bar (high contrast).
class SoundMiniPlayerThumbnail extends StatelessWidget {
  const SoundMiniPlayerThumbnail({required this.size, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    final st = SoundPickerTheme.of(context);
    // ~8px corner at 36dp thumb (same as list mini-player clip radius).
    final radius = size * (8 / 36);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(
        Icons.music_note_rounded,
        size: size * 0.52,
        color: st.selectionAccent,
      ),
    );
  }
}

/// Default music note thumbnail for sound list rows (theme-aware).
class SoundMusicThumbnail extends StatelessWidget {
  const SoundMusicThumbnail({required this.size, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    final st = SoundPickerTheme.of(context);
    final radius = size * (5.71429 / 40);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: st.musicThumbnailBackground,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(
        Icons.music_note_rounded,
        size: size * 0.45,
        color: st.musicThumbnailIcon,
      ),
    );
  }
}

/// Local search-field tint when SDK theme is active.
abstract final class AppColorsCompat {
  static Color searchFieldFill(bool isDark) =>
      isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFF0F0F0);
}
