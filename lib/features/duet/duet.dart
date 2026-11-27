/// Standalone Instagram-style Duet feature for the reels SDK.
///
/// Enable via `PostConfig.enableDuet` (host config). Entry is from an existing
/// reel's more-options sheet only — do not wire into create-post gallery.
///
/// Reuse notes for moderators:
/// - [DuetCaptureCoordinator.handleFromPost] is the public entry (mirrors dub-with-audio).
/// - After layout pick, prep uses a root [OverlayEntry] "Preparing for duet"
///   blocker (not a dialog — dialogs race the sheet dismiss and stay hidden).
///   Inserted on layout tap before the sheet pops.
/// - Layouts live in [DuetLayout] / [DuetLayoutGeometry].
/// - Export is [DuetComposer] (FFmpeg hstack / vstack / overlay).
/// - Live stage UI is [DuetStage] + [DuetCaptureView].
library;

export 'duet_capture_coordinator.dart';
export 'duet_capture_view.dart';
export 'duet_composer.dart';
export 'duet_config.dart';
export 'duet_eligibility_util.dart';
export 'duet_layout.dart';
export 'duet_layout_picker_sheet.dart';
export 'duet_session.dart';
export 'widgets/duet_stage.dart';
