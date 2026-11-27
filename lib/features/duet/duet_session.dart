import 'package:flutter/painting.dart';
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
    this.pipNormalizedOffset = DuetLayoutGeometry.pipDefaultNormalizedOffset,
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

  /// PiP only: 0–1 position within the padded frame (default bottom-right).
  /// Drag on [DuetStage] updates this; [DuetComposer] uses the same offset.
  final Offset pipNormalizedOffset;

  final String? composedOutputPath;

  DuetSession copyWith({
    String? sourcePostId,
    String? originalVideoPath,
    DuetLayout? layout,
    int? originalDurationSeconds,
    String? userClipPath,
    DuetUserSource? userSource,
    bool? userFrontCamera,
    Offset? pipNormalizedOffset,
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
        pipNormalizedOffset:
            pipNormalizedOffset ?? this.pipNormalizedOffset,
        composedOutputPath: composedOutputPath ?? this.composedOutputPath,
      );
}
