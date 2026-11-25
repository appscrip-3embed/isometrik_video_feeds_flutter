import 'package:flutter_test/flutter_test.dart';
import 'package:ism_video_reel_player/domain/models/response/timeline_response.dart';

void main() {
  group('TimeLineBodyData', () {
    test('parses next_cursor string', () {
      final body = TimeLineBodyData.fromMap({
        'posts': [],
        'next_cursor': 'eyJzaWQiOiIxIn0',
      });
      expect(body.nextCursor, 'eyJzaWQiOiIxIn0');
    });

    test('treats null next_cursor as no more pages', () {
      final body = TimeLineBodyData.fromMap({
        'posts': [],
        'next_cursor': null,
      });
      expect(body.nextCursor, isNull);
    });
  });
}