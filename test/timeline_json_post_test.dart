import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ism_video_reel_player/domain/models/response/timeline_response.dart';

void main() {
  test('sample post JSON maps to timeline data', () {
    final decoded = jsonDecode(_samplePostJson) as List<dynamic>;
    final posts = decoded
        .whereType<Map<dynamic, dynamic>>()
        .map(Map<String, dynamic>.from)
        .map(TimeLineData.fromMap)
        .toList();

    expect(posts, hasLength(1));
    final post = posts.single;
    expect(post.id, 'post_af199b349a03');
    expect(post.type, 'image');
    expect(post.caption, 'vianda de los Santos ');
    expect(post.userId, 'fd8973c1-f4d6-4951-ad83-7c631d98c439');
    expect(post.user?.username, 'viandadelossantos');
    expect(post.media, hasLength(1));
    expect(
      post.media?.single.url,
      'https://assets.dubly.xyz/image/folder//image_media_0_1788644402818.jpg',
    );
    expect(post.previews, hasLength(1));
    expect(post.settings?.commentsEnabled, isTrue);
    expect(post.engagementMetrics?.views, 24);
  });
}

const _samplePostJson = '''
[
  {
    "user_id": "fd8973c1-f4d6-4951-ad83-7c631d98c439",
    "previews": [
      {
        "media_type": "image",
        "asset_id": "asset_6549c3bad9e9",
        "position": 1,
        "url": "https://assets.dubly.xyz/image/folder//thumbnail_media_0_1788644402823.jpg",
        "description": null
      }
    ],
    "type": "image",
    "published_at": "2026-09-05T21:40:27.850845Z",
    "id": "post_af199b349a03",
    "media": [
      {
        "media_type": "image",
        "asset_id": "asset_c5732cfcdb6b",
        "position": 1,
        "url": "https://assets.dubly.xyz/image/folder//image_media_0_1788644402818.jpg",
        "description": null
      }
    ],
    "caption": "vianda de los Santos ",
    "user": {
      "id": "fd8973c1-f4d6-4951-ad83-7c631d98c439",
      "username": "viandadelossantos",
      "full_name": "Vianda De Los Santos Vianda",
      "display_name": "Vianda De Los Santos Vianda",
      "avatar_url": "https://gficzuoqoghdhgxgupkm.supabase.co/storage/v1/object/public/profile-pictures/d03b9446-1631-4cef-8d71-66e4d04ee261/normal/avatar/avatar.jpg",
      "user_metadata": {
        "isometrik_user_id": "6a35b59df96daa0001788fbd"
      },
      "verification_status": "unverified",
      "profile_type": "contact",
      "is_private": false,
      "gender": null,
      "is_online": false
    },
    "text_formatting": {},
    "interests": [],
    "engagement_metrics": {
      "likes": 0,
      "saves": 0,
      "views": 24,
      "shares": 0,
      "comments": 0,
      "like_types": {
        "sad": 0,
        "wow": 0,
        "haha": 0,
        "like": 0,
        "love": 0,
        "angry": 0
      },
      "tips_count": 0,
      "tips_amount": "0.00",
      "unique_views": 16
    },
    "settings": {
      "comments_enabled": true,
      "duet_enabled": false,
      "stitch_enabled": false,
      "save_enabled": true,
      "download_enabled": true,
      "age_restriction": false,
      "auto_advance": false,
      "advance_interval": 0,
      "audio_settings": null,
      "is_paid": false,
      "subscribers_only": false,
      "price_amount": null,
      "price_currency": "USD"
    },
    "sound_snapshot": {},
    "sound_id": "",
    "visibility": "public",
    "tags": {
      "mentions": [],
      "hashtags": [],
      "places": [],
      "products": [],
      "links": []
    },
    "is_liked": false,
    "is_saved": false,
    "is_following": false,
    "is_locked": false,
    "lock_reason": null
  }
]
''';
