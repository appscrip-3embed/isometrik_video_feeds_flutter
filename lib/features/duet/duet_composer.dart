import 'dart:io';
import 'dart:ui' show Offset;

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:ism_video_reel_player/features/duet/duet_layout.dart';
import 'package:ism_video_reel_player/utils/app_log.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Composes original + user clips into one Instagram-style duet MP4.
///
/// Uses FFmpeg (`ffmpeg_kit_flutter_new_min`) because the SDK's existing
/// [MediaUtil.mergeVideoSegments] only concatenates — it cannot hstack /
/// vstack / overlay. Keep this class inside `features/duet` so composition
/// stays reusable without touching create-post.
abstract final class DuetComposer {
  DuetComposer._();

  static const int _outW = 720;
  static const int _outH = 1280;

  /// Composes video with [layout]. Audio: original reel only — user clip is muted.
  static Future<String?> compose({
    required String originalPath,
    required String userPath,
    required DuetLayout layout,
    /// Horizontal flip on the user clip (front-camera duet recordings).
    bool flipUserClipHorizontally = false,
    /// PiP only — same 0–1 offset as [DuetStage] (default bottom-right).
    Offset pipNormalizedOffset = DuetLayoutGeometry.pipDefaultNormalizedOffset,
    void Function(double progress)? onProgress,
  }) async {
    final original = File(originalPath);
    final user = File(userPath);
    if (!await original.exists() || !await user.exists()) {
      AppLog.error('DuetComposer: missing input file(s)');
      return null;
    }

    final tempDir = await getTemporaryDirectory();
    final outPath = path.join(
      tempDir.path,
      'duet_${DateTime.now().millisecondsSinceEpoch}.mp4',
    );

    onProgress?.call(0.05);

    // Original reel audio only (camera/gallery track is not mapped). Silent fallback
    // if the source clip has no audio stream.
    final attempts = <String>[
      _buildCommand(
        original.path,
        user.path,
        outPath,
        layout,
        flipUserClipHorizontally: flipUserClipHorizontally,
        pipNormalizedOffset: pipNormalizedOffset,
        audioMode: _AudioMode.originalOnly,
      ),
      _buildCommand(
        original.path,
        user.path,
        outPath,
        layout,
        flipUserClipHorizontally: flipUserClipHorizontally,
        pipNormalizedOffset: pipNormalizedOffset,
        audioMode: _AudioMode.silent,
      ),
    ];

    for (final cmd in attempts) {
      AppLog.info('DuetComposer: $cmd');
      try {
        final session = await FFmpegKit.execute(cmd);
        final returnCode = await session.getReturnCode();
        if (!ReturnCode.isSuccess(returnCode)) {
          final logs = await session.getAllLogsAsString();
          AppLog.error('DuetComposer attempt failed: $logs');
          await _deleteIfExists(File(outPath));
          continue;
        }

        final out = File(outPath);
        if (!await out.exists() || await out.length() < 64) {
          AppLog.error('DuetComposer: output missing or too small');
          await _deleteIfExists(out);
          continue;
        }
        onProgress?.call(1);
        return outPath;
      } catch (e, st) {
        AppLog.error('DuetComposer exception: $e\n$st');
        await _deleteIfExists(File(outPath));
      }
    }
    return null;
  }

  static String _buildCommand(
    String originalPath,
    String userPath,
    String outPath,
    DuetLayout layout, {
    required bool flipUserClipHorizontally,
    required Offset pipNormalizedOffset,
    required _AudioMode audioMode,
  }) {
    // Layout graph ends at [vout]; normalize to CFR before encode.
    final layoutGraph = _videoFilter(
      layout,
      flipUserClipHorizontally: flipUserClipHorizontally,
      pipNormalizedOffset: pipNormalizedOffset,
    );
    // Gallery / camera clips often carry microsecond timebases (e.g. 1/1000000
    // or 15360 tbn). mpeg4 rejects denominators > 65535, which is why some
    // gallery picks failed with "Could not create the duet video" while others
    // worked. Force CFR 30 so the encoder gets a valid timebase.
    // Reuse: keep fps=30 + -r 30 whenever DuetComposer stays on mpeg4 (min kit).
    final videoGraph = '$layoutGraph;[vout]fps=30,settb=1/30[vout_cfr]';
    // fps_mode (not legacy -vsync) — this FFmpeg kit is n8.x.
    const videoEncode = '-r 30 -c:v mpeg4 -q:v 5 -fps_mode cfr';
    switch (audioMode) {
      case _AudioMode.originalOnly:
        return '-y -i "$originalPath" -i "$userPath" '
            '-filter_complex "$videoGraph" '
            '-map "[vout_cfr]" -map 0:a? '
            '$videoEncode -c:a aac -b:a 128k -shortest '
            '"$outPath"';
      case _AudioMode.silent:
        return '-y -i "$originalPath" -i "$userPath" '
            '-filter_complex "$videoGraph" '
            '-map "[vout_cfr]" -an '
            '$videoEncode -shortest '
            '"$outPath"';
    }
  }

  static String _videoFilter(
    DuetLayout layout, {
    required bool flipUserClipHorizontally,
    Offset pipNormalizedOffset = DuetLayoutGeometry.pipDefaultNormalizedOffset,
  }) {
    const halfW = _outW ~/ 2;
    const halfH = _outH ~/ 2;
    final pipRect = DuetLayoutGeometry.pipRect(
      DuetLayoutGeometry.outputSize,
      normalizedTopLeft: pipNormalizedOffset,
    );
    final pipW = pipRect.width.round();
    final pipH = pipRect.height.round();
    final pipX = pipRect.left.round();
    final pipY = pipRect.top.round();

    const padColor = 'black';
    final userFlip = flipUserClipHorizontally ? 'hflip,' : '';

    // Split layouts: letterbox so full frames stay visible.
    String userLetterbox(String w, String h, String label) =>
        '[1:v]$userFlip'
        'scale=$w:$h:force_original_aspect_ratio=decrease,'
        'pad=$w:$h:(ow-iw)/2:(oh-ih)/2:color=$padColor,setsar=1[$label]';

    // PiP: fill + center-crop (no side/top black bars) — Instagram-style.
    String cover(String input, String w, String h, String label) =>
        '$input'
        'scale=$w:$h:force_original_aspect_ratio=increase,'
        'crop=$w:$h,setsar=1[$label]';

    switch (layout) {
      case DuetLayout.leftRight:
        return '[0:v]scale=$halfW:$_outH:force_original_aspect_ratio=decrease,'
            'pad=$halfW:$_outH:(ow-iw)/2:(oh-ih)/2:color=$padColor,setsar=1[left];'
            '${userLetterbox('$halfW', '$_outH', 'right')};'
            '[left][right]hstack=inputs=2[vout]';
      case DuetLayout.topBottom:
        return '[0:v]scale=$_outW:$halfH:force_original_aspect_ratio=decrease,'
            'pad=$_outW:$halfH:(ow-iw)/2:(oh-ih)/2:color=$padColor,setsar=1[top];'
            '${userLetterbox('$_outW', '$halfH', 'bottom')};'
            '[top][bottom]vstack=inputs=2[vout]';
      case DuetLayout.pip:
        return '${cover('[0:v]', '$_outW', '$_outH', 'base')};'
            '${cover('[1:v]$userFlip', '$pipW', '$pipH', 'pip')};'
            '[base][pip]overlay=$pipX:$pipY[vout]';
    }
  }

  static Future<void> _deleteIfExists(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

enum _AudioMode { originalOnly, silent }
