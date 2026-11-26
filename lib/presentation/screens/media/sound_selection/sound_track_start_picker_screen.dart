import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:ism_video_reel_player/domain/domain.dart';
import 'package:ism_video_reel_player/presentation/presentation.dart';
import 'package:ism_video_reel_player/presentation/screens/media/media_edit/model/media_edit_audio_model.dart';
import 'package:ism_video_reel_player/presentation/screens/media/sound_selection/sound_selection_theme.dart';
import 'package:ism_video_reel_player/res/res.dart';
import 'package:ism_video_reel_player/utils/post_sound_util.dart';
import 'package:ism_video_reel_player/utils/sound_picker_preview_audio.dart';
import 'package:ism_video_reel_player/utils/sound_start_time_input_util.dart';
import 'package:ism_video_reel_player/utils/utils.dart';

/// Result of picking a library track and optional start offset (seconds).
class SoundTrackPickResult {
  const SoundTrackPickResult({
    required this.track,
    required this.startTimeSeconds,
  });

  final SoundTrack track;
  /// Fractional seconds (millisecond precision).
  final double startTimeSeconds;
}

/// Full-screen step after choosing a track: scrub start time, preview, confirm.
///
/// Audio is routed through [SoundPickerPreviewAudio] (single instance).
class SoundTrackStartPickerScreen extends StatefulWidget {
  const SoundTrackStartPickerScreen({
    super.key,
    required this.track,
    this.cameraBloc,
  });

  final SoundTrack track;
  final CameraBloc? cameraBloc;

  static Future<MediaEditSoundItem?> pickForMediaEdit(
    BuildContext context,
    SoundTrack track,
  ) async {
    final result = await Navigator.of(context, rootNavigator: true)
        .push<SoundTrackPickResult>(
      MaterialPageRoute(
        builder: (_) => SoundTrackStartPickerScreen(track: track),
      ),
    );
    if (result == null) return null;
    return PostSoundUtil.soundItemFromTrack(
      result.track,
      startTimeSeconds: result.startTimeSeconds,
    );
  }

  static Future<bool> pickForCamera(
    BuildContext context, {
    required SoundTrack track,
    required CameraBloc cameraBloc,
  }) async {
    final result = await Navigator.of(context, rootNavigator: true)
        .push<SoundTrackPickResult>(
      MaterialPageRoute(
        builder: (_) => SoundTrackStartPickerScreen(
          track: track,
          cameraBloc: cameraBloc,
        ),
      ),
    );
    if (result == null) return false;
    cameraBloc.add(
      CameraSetMusicEvent(
        musicId: result.track.id,
        musicName: result.track.title,
        musicArtist: result.track.author,
        musicThumbnailUrl: result.track.thumbnailUrl,
        musicDurationSeconds: result.track.duration.inSeconds,
        musicPreviewUrl: result.track.trackUrl,
        musicStartTimeSeconds: result.startTimeSeconds,
      ),
    );
    return true;
  }

  @override
  State<SoundTrackStartPickerScreen> createState() =>
      _SoundTrackStartPickerScreenState();
}

class _SoundTrackStartPickerScreenState
    extends State<SoundTrackStartPickerScreen> {
  final Object _owner = Object();
  final _manualStartController = TextEditingController();
  final _manualStartFocus = FocusNode();
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<bool>? _preparingSub;

  double _startFraction = 0;
  bool _isPlaying = false;
  bool _previewPreparing = false;
  bool _wasPlayingBeforeScrub = false;
  double _playbackOffsetSec = 0;
  bool _syncingManualField = false;
  /// True after preview play; keeps playhead + clock at pause position.
  bool _previewEngaged = false;

  double get _totalDurationSec {
    final ms = widget.track.duration.inMilliseconds;
    final sec = ms > 0 ? ms / 1000.0 : widget.track.duration.inSeconds.toDouble();
    return sec.clamp(0.001, 86400.0);
  }

  double get _startOffsetSec =>
      (_startFraction * _totalDurationSec).clamp(0, _totalDurationSec);

  String get _previewUrl => widget.track.trackUrl.trim();

  @override
  void initState() {
    super.initState();
    _syncManualFieldFromStart();
    unawaited(_claimPreview());
  }

  Future<void> _claimPreview() async {
    await SoundPickerPreviewAudio.claim(_owner);
    _stateSub = SoundPickerPreviewAudio.stateStream.listen((state) {
      if (!mounted) return;
      setState(() => _isPlaying = state == PlayerState.playing);
    });
    _preparingSub = SoundPickerPreviewAudio.preparingStream.listen((preparing) {
      if (!mounted) return;
      setState(() => _previewPreparing = preparing);
    });
    _positionSub = SoundPickerPreviewAudio.positionStream.listen((position) {
      if (!mounted) return;
      setState(() {
        _previewEngaged = true;
        _playbackOffsetSec =
            (position.inMilliseconds / 1000.0).clamp(0, _totalDurationSec);
      });
    });
  }

  void _syncManualFieldFromStart() {
    _syncingManualField = true;
    _manualStartController.text =
        SoundStartTimeInputUtil.formatSeconds(_startOffsetSec);
    _syncingManualField = false;
  }

  void _applyStartOffset(double seconds) {
    final clamped = seconds.clamp(0.0, _totalDurationSec).toDouble();
    setState(() {
      _startFraction = (clamped / _totalDurationSec).clamp(0.0, 1.0);
    });
    _syncManualFieldFromStart();
  }

  void _setStartToCurrentPlayback() {
    _applyStartOffset(_playbackOffsetSec);
    unawaited(
      SoundPickerPreviewAudio.prepare(
        url: _previewUrl,
        startSeconds: _startOffsetSec,
      ),
    );
  }

  void _commitManualStartField() {
    _dismissSearchKeyboard();
    final parsed = SoundStartTimeInputUtil.parse(
      _manualStartController.text,
      maxSeconds: _totalDurationSec,
    );
    if (parsed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(IsrTranslationFile.soundStartManualInvalid)),
      );
      _syncManualFieldFromStart();
      return;
    }
    _applyStartOffset(parsed);
    unawaited(
      SoundPickerPreviewAudio.prepare(
        url: _previewUrl,
        startSeconds: _startOffsetSec,
      ),
    );
  }

  void _dismissSearchKeyboard() {
    _manualStartFocus.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _preparingSub?.cancel();
    _positionSub?.cancel();
    _manualStartController.dispose();
    _manualStartFocus.dispose();
    unawaited(SoundPickerPreviewAudio.release(_owner));
    super.dispose();
  }

  /// Commits the manual field when valid; returns the start used for "Use sound".
  double _resolveStartTimeForConfirm() {
    final parsed = SoundStartTimeInputUtil.parse(
      _manualStartController.text,
      maxSeconds: _totalDurationSec,
    );
    if (parsed != null) {
      if ((parsed - _startOffsetSec).abs() > 0.0005) {
        _applyStartOffset(parsed);
      }
      return parsed;
    }
    if (_previewEngaged &&
        _startOffsetSec < 0.001 &&
        _playbackOffsetSec > 0.001) {
      return _playbackOffsetSec;
    }
    return _startOffsetSec;
  }

  Future<void> _stopAndPop([SoundTrackPickResult? result]) async {
    await SoundPickerPreviewAudio.stop();
    await SoundPickerPreviewAudio.release(_owner);
    if (!mounted) return;
    Navigator.pop(context, result);
  }

  Future<void> _confirmUseSound() async {
    if (_previewPreparing) return;
    _dismissSearchKeyboard();
    final startSec = _resolveStartTimeForConfirm();
    await _stopAndPop(
      SoundTrackPickResult(
        track: widget.track,
        startTimeSeconds: startSec,
      ),
    );
  }

  String _formatClock(double seconds) =>
      SoundStartTimeInputUtil.formatSeconds(seconds);

  Future<void> _togglePlayback() async {
    if (_previewPreparing) return;
    if (_previewUrl.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(IsrTranslationFile.soundPreviewUnavailable)),
        );
      }
      return;
    }
    try {
      await SoundPickerPreviewAudio.claim(_owner);
      setState(() {
        _previewEngaged = true;
        if (!_isPlaying) {
          _playbackOffsetSec = _startOffsetSec;
        }
      });
      await SoundPickerPreviewAudio.togglePreview(
        url: _previewUrl,
        startSeconds: _startOffsetSec,
      );
    } on SoundPickerPreviewException catch (error) {
      if (!mounted) return;
      final message = error.reason == SoundPickerPreviewFailure.playerNotReady
          ? IsrTranslationFile.soundPreviewInitializing
          : IsrTranslationFile.soundPreviewPlayFailed;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } on TimeoutException catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(IsrTranslationFile.soundPreviewLoadTimeout)),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(IsrTranslationFile.soundPreviewPlayFailed)),
        );
      }
    }
  }

  void _onScrubUpdate(double value) {
    setState(() {
      _startFraction = value;
      _wasPlayingBeforeScrub = _isPlaying;
    });
    _syncManualFieldFromStart();
    if (_wasPlayingBeforeScrub) {
      unawaited(SoundPickerPreviewAudio.pause());
    }
    SoundPickerPreviewAudio.scheduleSeek(startSeconds: _startOffsetSec);
  }

  Future<void> _onScrubEnd(double value) async {
    _applyStartOffset(value * _totalDurationSec);
    await SoundPickerPreviewAudio.prepare(
      url: _previewUrl,
      startSeconds: _startOffsetSec,
    );
    if (_wasPlayingBeforeScrub && _previewUrl.isNotEmpty) {
      await SoundPickerPreviewAudio.playPreview(
        url: _previewUrl,
        startSeconds: _startOffsetSec,
      );
    }
    _wasPlayingBeforeScrub = false;
  }

  @override
  Widget build(BuildContext context) {
    final st = SoundPickerTheme.of(context);
    final cs = Theme.of(context).colorScheme;
    final padBottom = MediaQuery.paddingOf(context).bottom;
    final accent = st.selectionAccent;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          unawaited(SoundPickerPreviewAudio.stop());
        }
      },
      child: Scaffold(
        backgroundColor: st.scaffoldBackground,
        appBar: AppBar(
          backgroundColor: st.appBarBackground,
          elevation: 0,
          foregroundColor: st.onSurface,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => unawaited(_stopAndPop()),
          ),
          title: Text(
            IsrTranslationFile.music,
            style: TextStyle(
              color: st.onSurface,
              fontSize: 17.responsiveDimension,
              fontWeight: FontWeight.w700,
            ),
          ),
          centerTitle: true,
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  20.responsiveDimension,
                  8.responsiveDimension,
                  20.responsiveDimension,
                  24.responsiveDimension,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TrackHeaderCard(track: widget.track, theme: st),
                    SizedBox(height: 28.responsiveDimension),
                    Text(
                      IsrTranslationFile.chooseSoundStart,
                      style: TextStyle(
                        color: st.onSurface,
                        fontSize: 16.responsiveDimension,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 6.responsiveDimension),
                    Text(
                      IsrTranslationFile.dragToSelectSoundStart,
                      style: TextStyle(
                        color: st.onSurfaceSecondary,
                        fontSize: 13.responsiveDimension,
                        height: 1.35,
                      ),
                    ),
                    SizedBox(height: 20.responsiveDimension),
                    _WaveformScrubber(
                      theme: st,
                      startFraction: _startFraction,
                      playbackFraction: _previewEngaged
                          ? (_playbackOffsetSec / _totalDurationSec)
                              .clamp(0.0, 1.0)
                          : null,
                      accentColor: accent,
                      onChanged: _onScrubUpdate,
                      onChangeEnd: _onScrubEnd,
                    ),
                    SizedBox(height: 14.responsiveDimension),
                    Row(
                      children: [
                        Icon(
                          Icons.flag_circle_outlined,
                          size: 18.responsiveDimension,
                          color: accent,
                        ),
                        SizedBox(width: 8.responsiveDimension),
                        Text(
                          '${IsrTranslationFile.startsAt} ${_formatClock(_startOffsetSec)}',
                          style: TextStyle(
                            color: st.onSurface,
                            fontSize: 14.responsiveDimension,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _previewEngaged
                                  ? '${_isPlaying ? IsrTranslationFile.playingAt : IsrTranslationFile.pausedAt} ${_formatClock(_playbackOffsetSec)}'
                                  : '${_formatClock(_startOffsetSec)} / ${_formatClock(_totalDurationSec)}',
                              style: TextStyle(
                                color: st.onSurface,
                                fontSize: 13.responsiveDimension,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (_previewEngaged)
                              Text(
                                '/ ${_formatClock(_totalDurationSec)}',
                                style: TextStyle(
                                  color: st.onSurfaceSecondary,
                                  fontSize: 12.responsiveDimension,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    if (_previewEngaged &&
                        !_isPlaying &&
                        (_playbackOffsetSec - _startOffsetSec).abs() > 0.001)
                      Padding(
                        padding: EdgeInsets.only(top: 10.responsiveDimension),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _setStartToCurrentPlayback,
                            icon: Icon(
                              Icons.flag_outlined,
                              size: 18.responsiveDimension,
                              color: accent,
                            ),
                            label: Text(
                              IsrTranslationFile.soundSetStartToPlayback,
                              style: TextStyle(
                                color: accent,
                                fontSize: 13.responsiveDimension,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    SizedBox(height: 16.responsiveDimension),
                    Text(
                      IsrTranslationFile.soundStartManualLabel,
                      style: TextStyle(
                        color: st.onSurfaceSecondary,
                        fontSize: 12.responsiveDimension,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 8.responsiveDimension),
                    TextField(
                      controller: _manualStartController,
                      focusNode: _manualStartFocus,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _commitManualStartField(),
                      onChanged: (_) {
                        if (_syncingManualField) return;
                      },
                      style: TextStyle(
                        color: st.onSurface,
                        fontSize: 15.responsiveDimension,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: IsrTranslationFile.soundStartManualHint,
                        hintStyle: TextStyle(
                          color: st.onSurfaceHint,
                          fontSize: 14.responsiveDimension,
                        ),
                        filled: true,
                        fillColor: st.searchFieldFill,
                        suffixIcon: IconButton(
                          tooltip: IsrTranslationFile.soundStartManualLabel,
                          icon: Icon(
                            Icons.check_circle_outline_rounded,
                            color: accent,
                            size: 22.responsiveDimension,
                          ),
                          onPressed: _commitManualStartField,
                        ),
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(12.responsiveDimension),
                          borderSide: BorderSide(color: st.chipBorderUnselected),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(12.responsiveDimension),
                          borderSide: BorderSide(color: st.chipBorderUnselected),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(12.responsiveDimension),
                          borderSide: BorderSide(color: accent),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 14.responsiveDimension,
                          vertical: 12.responsiveDimension,
                        ),
                      ),
                    ),
                    SizedBox(height: 20.responsiveDimension),
                    Center(
                      child: Material(
                        color: st.filterChipBackground,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _previewPreparing ? null : _togglePlayback,
                          child: Padding(
                            padding: EdgeInsets.all(18.responsiveDimension),
                            child: _previewPreparing
                                ? SizedBox(
                                    width: 36.responsiveDimension,
                                    height: 36.responsiveDimension,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.8,
                                      color: accent,
                                    ),
                                  )
                                : Icon(
                                    _isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: accent,
                                    size: 36.responsiveDimension,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                20.responsiveDimension,
                0,
                20.responsiveDimension,
                16.responsiveDimension + padBottom,
              ),
              child: SizedBox(
                height: 52.responsiveDimension,
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(14.responsiveDimension),
                    ),
                  ),
                  onPressed: _previewPreparing
                      ? null
                      : () => unawaited(_confirmUseSound()),
                  child: Text(
                    IsrTranslationFile.useThisSound,
                    style: TextStyle(
                      fontSize: 16.responsiveDimension,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Selected track summary card on the start-time step (Dubly purple accent).
class _TrackHeaderCard extends StatelessWidget {
  const _TrackHeaderCard({required this.track, required this.theme});

  final SoundTrack track;
  final SoundPickerTheme theme;

  Widget _placeholderThumb(SoundPickerTheme st, double size) {
    final radius = 12.responsiveDimension;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: st.filterChipBackground,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(
        Icons.music_note_rounded,
        size: size * 0.42,
        color: st.musicThumbnailIcon,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = theme;
    final accent = st.selectionAccent;
    return Container(
      decoration: BoxDecoration(
        color: st.trackSummaryCardFill,
        borderRadius: BorderRadius.circular(16.responsiveDimension),
        border: Border.all(color: st.trackSummaryCardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: st.trackSummaryCardFill == Colors.white ? 0.06 : 0.2),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ColoredBox(
              color: accent,
              child: SizedBox(width: 4.responsiveDimension),
            ),
            Expanded(
              child: Padding(
              padding: EdgeInsets.fromLTRB(
                12.responsiveDimension,
                12.responsiveDimension,
                14.responsiveDimension,
                12.responsiveDimension,
              ),
              child: Row(
                children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12.responsiveDimension),
            child: isLikelyImageUrl(track.thumbnailUrl)
                ? AppImage.network(
                    track.thumbnailUrl,
                    width: 64.responsiveDimension,
                    height: 64.responsiveDimension,
                    fit: BoxFit.cover,
                    placeHolderWidget: (_, __) =>
                        _placeholderThumb(st, 64.responsiveDimension),
                  )
                : _placeholderThumb(st, 64.responsiveDimension),
                  ),
                  SizedBox(width: 14.responsiveDimension),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: st.onSurface,
                            fontSize: 16.responsiveDimension,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 4.responsiveDimension),
                        Text(
                          track.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: st.onSurfaceSecondary,
                            fontSize: 13.responsiveDimension,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          ],
        ),
      ),
    );
  }
}

/// Waveform: grey before start marker, theme accent from marker onward.
class _WaveformScrubber extends StatelessWidget {
  const _WaveformScrubber({
    required this.theme,
    required this.startFraction,
    required this.accentColor,
    required this.onChanged,
    required this.onChangeEnd,
    this.playbackFraction,
  });

  final SoundPickerTheme theme;
  final double startFraction;
  final Color accentColor;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  /// Live playhead while preview is playing (0–1 on full track).
  final double? playbackFraction;

  @override
  Widget build(BuildContext context) {
    final st = theme;
    final fraction = startFraction.clamp(0.0, 1.0);
  final beforeGrey = st.onSurfaceSecondary.withValues(alpha: 0.28);
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final markerX = fraction * w;
        final playFrac = playbackFraction?.clamp(0.0, 1.0);
        final playheadX =
            playFrac != null ? playFrac * w : null;
        return SizedBox(
          height: 88.responsiveDimension,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: st.searchFieldFill,
                    borderRadius:
                        BorderRadius.circular(14.responsiveDimension),
                    border: Border.all(color: st.chipBorderUnselected),
                  ),
                  child: CustomPaint(
                    painter: _FakeWaveformPainter(
                      startFraction: fraction,
                      accent: accentColor,
                      beforeStart: beforeGrey,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: markerX.clamp(0.0, w),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: st.onSurfaceSecondary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.horizontal(
                      left: Radius.circular(14.responsiveDimension),
                      right: Radius.circular(6.responsiveDimension),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: (markerX - 1.5).clamp(0.0, w - 3),
                top: 6.responsiveDimension,
                bottom: 6.responsiveDimension,
                child: Container(
                  width: 3.responsiveDimension,
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: [
                      BoxShadow(
                        color: accentColor.withValues(alpha: 0.4),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
              if (playheadX != null)
                Positioned(
                  left: (playheadX - 1).clamp(0.0, w - 2),
                  top: 4.responsiveDimension,
                  bottom: 4.responsiveDimension,
                  child: Container(
                    width: 2.responsiveDimension,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(1),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x66000000),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ),
              Positioned.fill(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 88.responsiveDimension,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 0),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 0),
                    activeTrackColor: Colors.transparent,
                    inactiveTrackColor: Colors.transparent,
                  ),
                  child: Slider(
                    value: fraction,
                    onChanged: onChanged,
                    onChangeEnd: onChangeEnd,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FakeWaveformPainter extends CustomPainter {
  _FakeWaveformPainter({
    required this.startFraction,
    required this.accent,
    required this.beforeStart,
  });

  final double startFraction;
  final Color accent;
  final Color beforeStart;

  @override
  void paint(Canvas canvas, Size size) {
    const barCount = 48;
    final barWidth = size.width / (barCount * 2.1);
    final midY = size.height / 2;
    final startX = size.width * startFraction.clamp(0.0, 1.0);

    for (var i = 0; i < barCount; i++) {
      final x = i * (barWidth * 2.1) + barWidth;
      final phase = (i % 7) / 7;
      final h = size.height * (0.22 + 0.55 * (0.5 + 0.5 * (phase * 2 - 1).abs()));
      final afterStart = x >= startX;
      final paint = Paint()
        ..color = afterStart ? accent.withValues(alpha: 0.92) : beforeStart
        ..strokeCap = StrokeCap.round
        ..strokeWidth = barWidth;
      canvas.drawLine(
        Offset(x, midY - h / 2),
        Offset(x, midY + h / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FakeWaveformPainter oldDelegate) =>
      oldDelegate.startFraction != startFraction ||
      oldDelegate.accent != accent;
}