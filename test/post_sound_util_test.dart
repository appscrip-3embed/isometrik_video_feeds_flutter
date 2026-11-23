import 'package:flutter_test/flutter_test.dart';
import 'package:ism_video_reel_player/presentation/screens/media/media_edit/model/media_edit_audio_model.dart';
import 'package:ism_video_reel_player/utils/post_sound_util.dart';

void main() {
  test('buildSoundSnapshot caps clip length and omits title/artist', () {
    final sound = MediaEditSoundItem(
      soundId: 'snd_test',
      soundDuration: '268',
      soundArtist: 'Artist',
      soundMetadata: {'title': 'Song'},
    );

    final snapshot = PostSoundUtil.buildSoundSnapshot(
      sound: sound,
      videoDurationSeconds: 268,
    );

    expect(snapshot.containsKey('title'), isFalse);
    expect(snapshot.containsKey('artist'), isFalse);
    expect(snapshot['start_time'], 0);
    expect(snapshot['segment_duration'], 60);
    expect(snapshot['end_time'], 60);
    expect(snapshot['fade_in'], 0);
    expect(snapshot['fade_out'], 0);
    expect(snapshot['loop'], isFalse);
    expect(snapshot['captured_at'], isA<String>());
  });

  test('buildSoundSnapshot uses 3 seconds per image for image-only posts', () {
    final sound = MediaEditSoundItem(
      soundId: 'snd_test',
      soundDuration: '300',
    );

    final snapshot = PostSoundUtil.buildSoundSnapshot(
      sound: sound,
      videoDurationSeconds: PostSoundUtil.imagePostSoundDurationSeconds(2),
      maxClipSec: PostSoundUtil.imagePostSoundDurationSeconds(2),
    );

    expect(snapshot['segment_duration'], 6);
    expect(snapshot['end_time'], 6);
  });

  test('imagePostSoundDurationSeconds multiplies image count by 3', () {
    expect(PostSoundUtil.imagePostSoundDurationSeconds(1), 3);
    expect(PostSoundUtil.imagePostSoundDurationSeconds(2), 6);
    expect(PostSoundUtil.imagePostSoundDurationSeconds(4), 12);
  });

  test('playbackDurationSecondsForCarouselMedia uses slide length for images', () {
    expect(
      PostSoundUtil.playbackDurationSecondsForCarouselMedia(
        mediaType: 0,
        durationSeconds: 10,
      ),
      PostSoundUtil.imageSoundSecondsPerSlide,
    );
    expect(
      PostSoundUtil.playbackDurationSecondsForCarouselMedia(
        mediaType: 1,
        durationSeconds: 25,
      ),
      25,
    );
  });

  test('carouselSoundStartOffsetSeconds sums prior slide durations', () {
    final items = ['image', 'video', 'image'];
    int durationFor(String label) {
      if (label == 'image') return 10;
      if (label == 'video') return 19;
      return 1;
    }

    expect(
      PostSoundUtil.carouselSoundStartOffsetSeconds(
        items,
        0,
        durationFor,
      ),
      0,
    );
    expect(
      PostSoundUtil.carouselSoundStartOffsetSeconds(
        items,
        1,
        durationFor,
      ),
      10,
    );
    expect(
      PostSoundUtil.carouselSoundStartOffsetSeconds(
        items,
        2,
        durationFor,
      ),
      29,
    );
  });

  test('imageSlideIndexAtCarouselPage counts only prior images', () {
    final items = ['image', 'video', 'image', 'image'];
    expect(
      PostSoundUtil.imageSlideIndexAtCarouselPage(
        items,
        0,
        (s) => s == 'image',
      ),
      0,
    );
    expect(
      PostSoundUtil.imageSlideIndexAtCarouselPage(
        items,
        2,
        (s) => s == 'image',
      ),
      1,
    );
    expect(
      PostSoundUtil.imageSlideIndexAtCarouselPage(
        items,
        3,
        (s) => s == 'image',
      ),
      2,
    );
  });

  test('buildSoundSnapshot uses shorter video when under 60s', () {
    final sound = MediaEditSoundItem(
      soundId: 'snd_test',
      soundDuration: '120',
    );

    final snapshot = PostSoundUtil.buildSoundSnapshot(
      sound: sound,
      videoDurationSeconds: 15,
    );

    expect(snapshot['segment_duration'], 15);
    expect(snapshot['end_time'], 15);
  });

  test('buildSoundSnapshot includes original_status from metadata', () {
    final sound = MediaEditSoundItem(
      soundId: 'snd_test',
      soundDuration: '30',
      soundMetadata: const {'original_status': 'approved'},
    );

    final snapshot = PostSoundUtil.buildSoundSnapshot(sound: sound);

    expect(snapshot['original_status'], 'approved');
  });
}
