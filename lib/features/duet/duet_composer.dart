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
///
/// **Encode policy (reuse later):** prefer platform H.264 from the min kit
/// (`h264_mediacodec` / `h264_videotoolbox`). Do **not** use `-c:v mpeg4` as
/// the primary path — MPEG-4 Part 2 (`video/mp4v-es`) stalls MediaTek/ExoPlayer
/// reels decoders. Keep mpeg4 only as a last-resort fallback when HW H.264
/// fails. `libx264` needs a `-gpl` FFmpeg package; stay on min unless product
/// upgrades the dependency.
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

    // Prefer H.264 (playable in reels), then mpeg4 only if HW encode fails.
    // For each encode profile: original audio, then silent if no audio stream.
    final attempts = <String>[];
    for (final encode in _videoEncodeProfiles()) {
      for (final audioMode in _AudioMode.values) {
        attempts.add(
          _buildCommand(
            original.path,
            user.path,
            outPath,
            layout,
            flipUserClipHorizontally: flipUserClipHorizontally,
            pipNormalizedOffset: pipNormalizedOffset,
            audioMode: audioMode,
            videoEncode: encode,
          ),
        );
      }
    }

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

  /// Ordered encode arg strings for the min FFmpeg kit (no libx264).
  ///
  /// Reuse: any offline compose that must stay on `ffmpeg_kit_flutter_new_min`
  /// should call this (or copy the same order) instead of hard-coding mpeg4.
  static List<String> _videoEncodeProfiles() {
    final profiles = <String>[];
    if (Platform.isAndroid) {
      // MediaCodec H.264 — available via Android system libs in the min package.
      profiles.add(
        '-r 30 -c:v h264_mediacodec -b:v 2500k -pix_fmt yuv420p -fps_mode cfr',
      );
    } else if (Platform.isIOS || Platform.isMacOS) {
      // VideoToolbox H.264 — enabled for min on Apple platforms.
      profiles.add(
        '-r 30 -c:v h264_videotoolbox -b:v 2500k -pix_fmt yuv420p -fps_mode cfr',
      );
    }
    // Last resort only: MPEG-4 Part 2 plays poorly in multi-decoder reels feeds.
    profiles.add('-r 30 -c:v mpeg4 -q:v 5 -fps_mode cfr');
    return profiles;
  }

  static String _buildCommand(
    String originalPath,
    String userPath,
    String outPath,
    DuetLayout layout, {
    required bool flipUserClipHorizontally,
    required Offset pipNormalizedOffset,
    required _AudioMode audioMode,
    required String videoEncode,
  }) {
    // Layout graph ends at [vout]; normalize to CFR before encode.
    final layoutGraph = _videoFilter(
      layout,
      flipUserClipHorizontally: flipUserClipHorizontally,
      pipNormalizedOffset: pipNormalizedOffset,
    );
    // Gallery / camera clips often carry microsecond timebases (e.g. 1/1000000
    // or 15360 tbn). Force CFR 30 so HW and mpeg4 encoders get a valid timebase.
    final videoGraph = '$layoutGraph;[vout]fps=30,settb=1/30[vout_cfr]';
    // fps_mode (not legacy -vsync) — this FFmpeg kit is n8.x.
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
