import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:ism_video_reel_player/utils/audio_source_util.dart';

/// One shared preview player for the create-post sound library + start picker.
///
/// List preview, start-time scrubber, and detail preview must call [claim] /
/// [release] so only one route owns playback. Call [shutdown] when the whole
/// picker route is disposed (e.g. leaving create post).
/// Thrown when preview playback cannot start (init race, timeout, platform error).
class SoundPickerPreviewException implements Exception {
  const SoundPickerPreviewException(this.reason);

  final SoundPickerPreviewFailure reason;

  @override
  String toString() => 'SoundPickerPreviewException($reason)';
}

enum SoundPickerPreviewFailure {
  /// [claim] has not finished; caller should await [claim] and retry.
  playerNotReady,
  loadFailed,
}

abstract final class SoundPickerPreviewAudio {
  static AudioPlayer? _player;
  static Object? _owner;
  static String? _loadedUrl;
  static StreamSubscription<PlayerState>? _stateSub;
  static StreamSubscription<Duration>? _positionSub;
  static StreamSubscription<void>? _completeSub;
  static Timer? _seekDebounce;
  static double _loopStartSeconds = 0;
  static bool _loopPreview = false;
  static var _preparing = false;
  static int _prepareGeneration = 0;

  static final StreamController<PlayerState> _stateBroadcast =
      StreamController<PlayerState>.broadcast();
  static final StreamController<Duration> _positionBroadcast =
      StreamController<Duration>.broadcast();
  static final StreamController<bool> _preparingBroadcast =
      StreamController<bool>.broadcast();

  /// Broadcast of [AudioPlayer.onPlayerStateChanged] for the shared instance.
  static Stream<PlayerState> get stateStream => _stateBroadcast.stream;

  /// Current playback position for start-time picker UI.
  static Stream<Duration> get positionStream => _positionBroadcast.stream;

  /// True while a remote preview URL is being prepared (buffering large clips).
  static Stream<bool> get preparingStream => _preparingBroadcast.stream;

  static bool get isPreparing => _preparing;

  static AudioPlayer? get player => _player;

  static bool get isPlaying => _player?.state == PlayerState.playing;

  static bool owns(Object owner) => identical(_owner, owner);

  static void _setPreparing(bool value) {
    if (_preparing == value) return;
    _preparing = value;
    if (!_preparingBroadcast.isClosed) {
      _preparingBroadcast.add(value);
    }
  }

  static AudioPlayer _requirePlayer() {
    final p = _player;
    if (p == null) {
      throw const SoundPickerPreviewException(
        SoundPickerPreviewFailure.playerNotReady,
      );
    }
    return p;
  }

  /// Takes exclusive control; stops any other owner's playback.
  static Future<void> claim(Object owner) async {
    if (!identical(_owner, owner)) {
      await stop();
      _owner = owner;
    }
    _player ??= AudioPlayer();
    _wireSubscriptions();
  }

  /// Stops playback when [owner] leaves (screen dispose / pop). Keeps player
  /// alive for the parent list until [shutdown].
  static Future<void> release(Object owner) async {
    if (!identical(_owner, owner)) return;
    _seekDebounce?.cancel();
    _loopPreview = false;
    await stop();
    _owner = null;
  }

  /// Stops, disposes, and clears the singleton (picker route closed).
  static Future<void> shutdown() async {
    _seekDebounce?.cancel();
    _loopPreview = false;
    _prepareGeneration++;
    _setPreparing(false);
    await _stateSub?.cancel();
    _stateSub = null;
    await _positionSub?.cancel();
    _positionSub = null;
    await _completeSub?.cancel();
    _completeSub = null;
    final p = _player;
    _player = null;
    _owner = null;
    _loadedUrl = null;
    if (p != null) {
      try {
        await p.stop();
        await p.dispose();
      } catch (_) {}
    }
  }

  static void _wireSubscriptions() {
    final p = _player;
    if (p == null) return;
    if (_stateSub != null) return;
    _stateSub = p.onPlayerStateChanged.listen((state) {
      if (!_stateBroadcast.isClosed) {
        _stateBroadcast.add(state);
      }
    });
    _positionSub = p.onPositionChanged.listen((position) {
      if (!_positionBroadcast.isClosed) {
        _positionBroadcast.add(position);
      }
    });
    _completeSub = p.onPlayerComplete.listen((_) async {
      if (!_loopPreview || _player == null) return;
      try {
        await _player!.seek(
          Duration(milliseconds: (_loopStartSeconds * 1000).round()),
        );
        await _player!.resume();
      } catch (_) {}
    });
  }

  static Future<void> stop() async {
    _seekDebounce?.cancel();
    _loopPreview = false;
    try {
      await _player?.stop();
    } catch (_) {}
  }

  static Future<void> pause() async {
    _loopPreview = false;
    try {
      await _player?.pause();
    } catch (_) {}
  }

  /// Load URL if needed and seek (no play).
  static Future<void> prepare({
    required String url,
    required double startSeconds,
  }) async {
    final player = _requirePlayer();
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    final gen = ++_prepareGeneration;
    _setPreparing(true);
    try {
      if (_loadedUrl != trimmed) {
        await player.stop();
        await player.setSource(audioSourceFromUrlOrPath(trimmed));
        await player.setReleaseMode(ReleaseMode.stop);
        _loadedUrl = trimmed;
      }
      await player.seek(
        Duration(milliseconds: (startSeconds * 1000).round()),
      );
    } catch (_) {
      throw const SoundPickerPreviewException(
        SoundPickerPreviewFailure.loadFailed,
      );
    } finally {
      if (gen == _prepareGeneration) {
        _setPreparing(false);
      }
    }
  }

  /// Debounced seek while dragging the start marker (avoids overlapping seeks).
  static void scheduleSeek({
    required double startSeconds,
    Duration delay = const Duration(milliseconds: 150),
  }) {
    _seekDebounce?.cancel();
    _seekDebounce = Timer(delay, () async {
      if (_player == null) return;
      try {
        await _player!.seek(
          Duration(milliseconds: (startSeconds * 1000).round()),
        );
      } catch (_) {}
    });
  }

  /// Preview from [startSeconds], looping back to that offset on complete.
  static Future<void> playPreview({
    required String url,
    required double startSeconds,
  }) async {
    _loopStartSeconds = startSeconds;
    final player = _requirePlayer();
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    final gen = ++_prepareGeneration;
    _setPreparing(true);
    try {
      if (_loadedUrl != trimmed) {
        await player.stop();
        await player.setSource(audioSourceFromUrlOrPath(trimmed));
        await player.setReleaseMode(ReleaseMode.stop);
        _loadedUrl = trimmed;
      }
      await player.seek(
        Duration(milliseconds: (startSeconds * 1000).round()),
      );
      _loopPreview = true;
      await player.resume();
    } catch (_) {
      throw const SoundPickerPreviewException(
        SoundPickerPreviewFailure.loadFailed,
      );
    } finally {
      if (gen == _prepareGeneration) {
        _setPreparing(false);
      }
    }
  }

  static Future<void> togglePreview({
    required String url,
    required double startSeconds,
  }) async {
    if (isPlaying) {
      await pause();
      return;
    }
    await playPreview(
      url: url,
      startSeconds: startSeconds,
    );
  }

  /// List row preview (no loop segment).
  static Future<void> playListPreview(String url) async {
    final player = _requirePlayer();
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    final gen = ++_prepareGeneration;
    _loopPreview = false;
    _setPreparing(true);
    try {
      if (_loadedUrl != trimmed) {
        await player.stop();
        await player.setSource(audioSourceFromUrlOrPath(trimmed));
        await player.setReleaseMode(ReleaseMode.stop);
        _loadedUrl = trimmed;
      } else {
        await player.stop();
      }
      await player.resume();
    } catch (_) {
      throw const SoundPickerPreviewException(
        SoundPickerPreviewFailure.loadFailed,
      );
    } finally {
      if (gen == _prepareGeneration) {
        _setPreparing(false);
      }
    }
  }

  static Future<void> resumeIfPaused() async {
    if (_player == null) return;
    if (_player!.state == PlayerState.playing) return;
    await _player!.resume();
  }

  static Future<void> pauseIfPlaying() async {
    if (!isPlaying) return;
    await pause();
  }
}