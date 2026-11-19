bool isLikelyImageUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return false;
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
    return false;
  }
  final path = uri.path.toLowerCase();
  const blockedMediaExt = [
    '.mp3',
    '.m4a',
    '.aac',
    '.wav',
    '.ogg',
    '.flac',
    '.mp4',
    '.mov',
    '.mkv',
    '.webm',
    '.m3u8',
  ];
  return !blockedMediaExt.any(path.endsWith);
}

/// Keeps empty path segments in http(s) media URLs.
///
/// The CDN stores some objects under a key with a double slash, for example
/// `image/folder//image_media_0.jpg`. iOS drops the empty segment before it
/// sends the request, so the CDN returns 403. Encoding each extra slash as
/// `%2F` (`image/folder/%2Fimage_media_0.jpg`) keeps the segment on iOS and
/// still resolves to the same object key.
///
/// Only the path is changed. Query, fragment, and non-http URLs are returned
/// unchanged. The function is idempotent: an encoded URL has no `//`, so a
/// second call returns it as is.
String preserveEmptyPathSegments(String rawUrl) {
  final url = rawUrl.trim();
  final lower = url.toLowerCase();
  if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
    return url;
  }

  final authorityStart = url.indexOf('//') + 2;
  final pathStart = url.indexOf('/', authorityStart);
  if (pathStart < 0) return url;

  var pathEnd = url.length;
  final queryStart = url.indexOf('?', pathStart);
  if (queryStart >= 0 && queryStart < pathEnd) pathEnd = queryStart;
  final fragmentStart = url.indexOf('#', pathStart);
  if (fragmentStart >= 0 && fragmentStart < pathEnd) pathEnd = fragmentStart;

  final origin = url.substring(0, pathStart);
  final path = url.substring(pathStart, pathEnd);
  final suffix = url.substring(pathEnd);
  if (!path.contains('//')) return url;

  // Each run of N slashes keeps one leading slash, then N-1 encoded slashes.
  // "//" becomes "/%2F", and "///" becomes "/%2F%2F".
  final fixedPath = path.replaceAllMapped(
    RegExp('/{2,}'),
    (match) => '/${'%2F' * (match.group(0)!.length - 1)}',
  );
  return '$origin$fixedPath$suffix';
}
