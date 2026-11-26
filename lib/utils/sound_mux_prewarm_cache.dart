import 'dart:async';
import 'dart:io';

/// Starts a "replace video audio with selected sound" mux in the background
/// so the result is (usually) ready by the time the user taps Next.
///
/// Instagram-style "Use audio": the editor previews the clip instantly with the
/// sound played as a separate overlay (see `VideoPreviewWidget`), and the real
/// mux runs in parallel here. When `PostSoundUtil.muxVideoWithSound` is later
/// called with the same video + sound, it awaits this in-flight job instead of
/// re-encoding from scratch.
///
/// Reuse: any flow that already knows its final video + sound before the user
/// reaches Next can call [prewarm]. Nothing else needs to change — the lookup
/// in `PostSoundUtil.muxVideoWithSound` is automatic and falls back to a normal
/// mux on a miss (e.g. user trimmed/filtered the clip or picked another sound).
///
/// Only one job is kept at a time; starting a new one or calling [discard]
/// deletes the previous unused output once it finishes.
abstract final class SoundMuxPrewarmCache {
  static String? _key;
  static Future<String>? _job;

  /// Same identity the mux depends on: input video, sound source, start offset.
  static String keyFor({
    required String videoPath,
    required String soundUrl,
    required double startTimeSec,
  }) =>
      '${videoPath.trim()}|${soundUrl.trim()}|${startTimeSec.toStringAsFixed(3)}';

  /// Begins [mux] in the background for [key], replacing any previous job.
  static void prewarm({
    required String key,
    required String videoPath,
    required Future<String> Function() mux,
  }) {
    if (_key == key && _job != null) return;
    discard();
    _key = key;
    _job = mux().catchError((Object _) => videoPath);
  }

  /// Returns the in-flight/finished job for [key] and hands ownership of the
  /// output file to the caller. Returns null on a miss.
  static Future<String>? take(String key) {
    if (_key != key || _job == null) return null;
    final job = _job;
    _key = null;
    _job = null;
    return job;
  }

  /// Drops the current job (if unclaimed) and deletes its output when done.
  static void discard() {
    final job = _job;
    final key = _key;
    _key = null;
    _job = null;
    if (job == null || key == null) return;
    final inputVideo = key.split('|').first;
    unawaited(job.then((out) async {
      if (out.isEmpty || out == inputVideo) return;
      try {
        final f = File(out);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }));
  }
}
