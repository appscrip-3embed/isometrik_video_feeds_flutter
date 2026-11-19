import 'package:flutter_test/flutter_test.dart';
import 'package:ism_video_reel_player/utils/media_url_util.dart';

void main() {
  group('preserveEmptyPathSegments', () {
    test('encodes the extra slash of a double-slash media key', () {
      expect(
        preserveEmptyPathSegments(
          'https://assets.dubly.xyz/image/folder//image_media_0_1788644402818.jpg',
        ),
        'https://assets.dubly.xyz/image/folder/%2Fimage_media_0_1788644402818.jpg',
      );
    });

    test('encodes the preview thumbnail the same way', () {
      expect(
        preserveEmptyPathSegments(
          'https://assets.dubly.xyz/image/folder//thumbnail_media_0_1788644402823.jpg',
        ),
        'https://assets.dubly.xyz/image/folder/%2Fthumbnail_media_0_1788644402823.jpg',
      );
    });

    test('leaves single-slash URLs unchanged', () {
      const url =
          'https://assets.dubly.xyz/image/folder/image_media_0_1788644402818.jpg';
      expect(preserveEmptyPathSegments(url), url);
    });

    test('is idempotent', () {
      const raw =
          'https://assets.dubly.xyz/image/folder//image_media_0_1788644402818.jpg';
      final once = preserveEmptyPathSegments(raw);
      expect(preserveEmptyPathSegments(once), once);
    });

    test('keeps an already encoded URL unchanged', () {
      const url =
          'https://assets.dubly.xyz/image/folder/%2Fimage_media_0_1788644402818.jpg';
      expect(preserveEmptyPathSegments(url), url);
    });

    test('only changes the path, not the query or fragment', () {
      expect(
        preserveEmptyPathSegments('https://host.dev/a//b.jpg?x=//y#frag//z'),
        'https://host.dev/a/%2Fb.jpg?x=//y#frag//z',
      );
    });

    test('handles a double slash directly after the host', () {
      expect(
        preserveEmptyPathSegments('https://host.dev//b.jpg'),
        'https://host.dev/%2Fb.jpg',
      );
    });

    test('encodes each extra slash in a run of three', () {
      expect(
        preserveEmptyPathSegments('https://host.dev/a///b.jpg'),
        'https://host.dev/a/%2F%2Fb.jpg',
      );
    });

    test('trims surrounding whitespace', () {
      expect(
        preserveEmptyPathSegments('  https://host.dev/a//b.jpg \n'),
        'https://host.dev/a/%2Fb.jpg',
      );
    });

    test('does not touch non-http URLs or local paths', () {
      expect(preserveEmptyPathSegments('file:///a//b.jpg'), 'file:///a//b.jpg');
      expect(preserveEmptyPathSegments('/data//local.jpg'), '/data//local.jpg');
    });

    test('Uri.parse keeps the encoded slash instead of decoding it', () {
      final encoded = preserveEmptyPathSegments(
        'https://assets.dubly.xyz/image/folder//image_media_0.jpg',
      );
      expect(Uri.parse(encoded).toString(), encoded);
    });
  });
}
