import 'dart:io';

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
        audioMode: _AudioMode.originalOnly,
      ),
      _buildCommand(
        original.path,
        user.path,
        outPath,
        layout,
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
    required _AudioMode audioMode,
  }) {
    final videoGraph = _videoFilter(layout);
    switch (audioMode) {
      case _AudioMode.originalOnly:
        return '-y -i "$originalPath" -i "$userPath" '
            '-filter_complex "$videoGraph" '
            '-map "[vout]" -map 0:a? '
            '-c:v mpeg4 -q:v 5 -c:a aac -b:a 128k -shortest '
            '"$outPath"';
      case _AudioMode.silent:
        return '-y -i "$originalPath" -i "$userPath" '
            '-filter_complex "$videoGraph" '
            '-map "[vout]" -an '
            '-c:v mpeg4 -q:v 5 -shortest '
            '"$outPath"';
    }
  }

  static String _videoFilter(DuetLayout layout) {
    const halfW = _outW ~/ 2;
    const halfH = _outH ~/ 2;
    final pipW = (_outW * DuetLayoutGeometry.pipWidthFraction).round();
    final pipH = (_outH * DuetLayoutGeometry.pipHeightFraction).round();
    final pipMargin = (_outW * DuetLayoutGeometry.pipMarginFraction).round();
    final pipX = _outW - pipW - pipMargin;
    final pipY = _outH - pipH - pipMargin;

    // Letterbox (scale decrease + pad): full frame visible, black bars — no crop.
    const padColor = 'black';
    switch (layout) {
      case DuetLayout.leftRight:
        return '[0:v]scale=$halfW:$_outH:force_original_aspect_ratio=decrease,'
            'pad=$halfW:$_outH:(ow-iw)/2:(oh-ih)/2:color=$padColor,setsar=1[left];'
            '[1:v]scale=$halfW:$_outH:force_original_aspect_ratio=decrease,'
            'pad=$halfW:$_outH:(ow-iw)/2:(oh-ih)/2:color=$padColor,setsar=1[right];'
            '[left][right]hstack=inputs=2[vout]';
      case DuetLayout.topBottom:
        return '[0:v]scale=$_outW:$halfH:force_original_aspect_ratio=decrease,'
            'pad=$_outW:$halfH:(ow-iw)/2:(oh-ih)/2:color=$padColor,setsar=1[top];'
            '[1:v]scale=$_outW:$halfH:force_original_aspect_ratio=decrease,'
            'pad=$_outW:$halfH:(ow-iw)/2:(oh-ih)/2:color=$padColor,setsar=1[bottom];'
            '[top][bottom]vstack=inputs=2[vout]';
      case DuetLayout.pip:
        return '[0:v]scale=$_outW:$_outH:force_original_aspect_ratio=decrease,'
            'pad=$_outW:$_outH:(ow-iw)/2:(oh-ih)/2:color=$padColor,setsar=1[base];'
            '[1:v]scale=$pipW:$pipH:force_original_aspect_ratio=decrease,'
            'pad=$pipW:$pipH:(ow-iw)/2:(oh-ih)/2:color=$padColor,setsar=1[pip];'
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
