import 'package:ism_video_reel_player/features/duet/duet_layout.dart';

/// How the user half of a duet was obtained.
enum DuetUserSource {
  camera,
  gallery,
}

/// In-flight duet state from layout pick through compose.
///
/// Kept in the standalone `features/duet` module so moderators can follow
/// the session without digging through create-post code.
class DuetSession {
  const DuetSession({
    required this.sourcePostId,
    required this.originalVideoPath,
    required this.layout,
    required this.originalDurationSeconds,
    this.userClipPath,
    this.userSource,
    this.userFrontCamera = false,
    this.composedOutputPath,
  });

  final String sourcePostId;
  final String originalVideoPath;
  final DuetLayout layout;
  final int originalDurationSeconds;
  final String? userClipPath;
  final DuetUserSource? userSource;

  /// Front-camera recording: live preview is platform-mirrored, but the file is
  /// not — set true so [DuetComposer] applies hflip and the editor matches.
  final bool userFrontCamera;
  final String? composedOutputPath;

  DuetSession copyWith({
    String? sourcePostId,
    String? originalVideoPath,
    DuetLayout? layout,
    int? originalDurationSeconds,
    String? userClipPath,
    DuetUserSource? userSource,
    bool? userFrontCamera,
    String? composedOutputPath,
  }) =>
      DuetSession(
        sourcePostId: sourcePostId ?? this.sourcePostId,
        originalVideoPath: originalVideoPath ?? this.originalVideoPath,
        layout: layout ?? this.layout,
        originalDurationSeconds:
            originalDurationSeconds ?? this.originalDurationSeconds,
        userClipPath: userClipPath ?? this.userClipPath,
        userSource: userSource ?? this.userSource,
        userFrontCamera: userFrontCamera ?? this.userFrontCamera,
        composedOutputPath: composedOutputPath ?? this.composedOutputPath,
      );
}
