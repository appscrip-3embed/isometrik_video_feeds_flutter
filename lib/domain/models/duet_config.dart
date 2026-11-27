import 'package:flutter/widgets.dart';
import 'package:ism_video_reel_player/domain/models/response/response.dart';

/// Instagram-style duet pane arrangements.
///
/// Standalone duet — enable via [PostConfig.enableDuet].
/// Layout geometry helpers live in `features/duet/duet_layout.dart`.
enum DuetLayout {
  /// Original on the left, user on the right.
  leftRight,

  /// Original on top, user on the bottom.
  topBottom,

  /// Original full-bleed; user in a fixed corner PiP.
  pip,
}

/// Host overrides for the standalone Instagram-style duet flow.
///
/// Enable with [PostConfig.enableDuet]. Entry is from an existing reel's
/// more-options only — never from the create-post gallery flow.
class DuetConfig {
  const DuetConfig({
    this.canStart,
    this.onLockedPost,
    this.defaultLayout = DuetLayout.leftRight,
    this.maxDurationSeconds = 60,
    this.allowGalleryPick = true,
    /// When false (default), show Duet on video reels whenever the host enables
    /// the feature — even if the API sends `settings.duet_enabled: false`
    /// (common backend default). Set true to honor per-post duet off.
    this.respectPostDuetEnabledSetting = false,
  });

  /// Optional gate before layout picker / capture (e.g. paywall).
  final Future<bool> Function(BuildContext context, TimeLineData post)?
      canStart;

  /// Called when the source reel is locked and duet cannot start.
  final void Function(BuildContext context, TimeLineData post)? onLockedPost;

  /// Pre-selected layout in the picker sheet.
  final DuetLayout defaultLayout;

  /// Cap for camera recording / gallery trim (seconds).
  final int maxDurationSeconds;

  /// When true, capture UI shows a gallery button for the user half.
  final bool allowGalleryPick;

  /// See [DuetConfig.respectPostDuetEnabledSetting] in the constructor.
  final bool respectPostDuetEnabledSetting;
}
