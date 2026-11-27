import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;

/// Network / HLS helpers shared by reel video players.
///
/// Reuse [networkHttpHeaders] from every `VideoPlayerController.networkUrl`
/// create path (standard, non-preload, cached) so iOS AVPlayer behavior stays
/// consistent. Do not invent a second header map in a player file.
class VideoMediaUtil {
  static final CacheManager _cache = DefaultCacheManager();

  /// Prevent duplicate parallel downloads
  static final Set<String> _inFlightSegments = {};

  /// Headers for progressive MP4 / HLS via `video_player`.
  ///
  /// **iOS/macOS:** return an empty map for progressive MP4 so avfoundation
  /// does **not** set `AVURLAssetHTTPHeaderFieldsKey`. Custom headers (especially
  /// `Accept-Encoding: gzip, deflate, br`) commonly make AVPlayer download most
  /// of the file before `initialize` completes — multi-minute waits for short
  /// clips while Android ExoPlayer stays fine. HLS may keep a session id only.
  ///
  /// **Android:** keep the previous header set unchanged (already smooth).
  static Map<String, String> networkHttpHeaders({required bool isHls}) {
    if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
      if (!isHls) return const <String, String>{};
      return <String, String>{
        'X-Playback-Session-Id':
            DateTime.now().millisecondsSinceEpoch.toString(),
      };
    }
    return <String, String>{
      'Accept': '*/*',
      'Accept-Language': 'en-US,en;q=0.9',
      'Accept-Encoding': 'gzip, deflate, br',
      'Connection': 'keep-alive',
      'Cache-Control': 'no-cache',
      if (isHls)
        'X-Playback-Session-Id':
            DateTime.now().millisecondsSinceEpoch.toString(),
    };
  }

  static Future<void> precacheFirstSegment(String m3u8Url) async {
    if (!m3u8Url.endsWith('.m3u8')) return;

    try {
      // 1️⃣ Fetch playlist
      final response = await http.get(Uri.parse(m3u8Url));
      if (response.statusCode != 200) return;

      final lines = const LineSplitter().convert(response.body);

      // 2️⃣ Find first .ts segment
      final firstSegment = lines.firstWhere(
            (line) => line.isNotEmpty && !line.startsWith('#'),
        orElse: () => '',
      );

      if (firstSegment.isEmpty) return;

      // 3️⃣ Resolve absolute URL
      final segmentUrl =
      Uri.parse(m3u8Url).resolve(firstSegment).toString();

      // 🔒 Prevent duplicate parallel downloads
      if (_inFlightSegments.contains(segmentUrl)) return;
      _inFlightSegments.add(segmentUrl);

      // 4️⃣ Check disk cache FIRST
      final cached = await _cache.getFileFromCache(segmentUrl);
      if (cached != null) {
        debugPrint('♻️ First HLS segment already cached: $segmentUrl');
        _inFlightSegments.remove(segmentUrl);
        return;
      }

      // 5️⃣ Download & cache
      await _cache.downloadFile(segmentUrl, key: segmentUrl);
      debugPrint('✅ Cached first HLS segment: $segmentUrl');
    } catch (e) {
      debugPrint('⚠️ Failed to cache first HLS segment: $e');
    } finally {
      _inFlightSegments.clear();
    }
  }
}