/// Parse / format start offsets for the create-post sound picker (fractional sec).
abstract final class SoundStartTimeInputUtil {
  /// `M:SS.mmm` or `m:ss` (e.g. `0:26.150`, `1:05.500`).
  static String formatSeconds(double seconds, {bool millis = true}) {
    final sec = seconds < 0 ? 0.0 : seconds;
    final m = sec ~/ 60;
    final s = (sec % 60).floor();
    if (!millis) {
      return '$m:${s.toString().padLeft(2, '0')}';
    }
    final ms = ((sec - sec.floor()) * 1000).round().clamp(0, 999);
    return '$m:${s.toString().padLeft(2, '0')}.${ms.toString().padLeft(3, '0')}';
  }

  /// Supports `26.15`, `0:26.150`, `0:26:150` (min:sec:ms), `1:05.5`.
  static double? parse(
    String raw, {
    required double maxSeconds,
  }) {
    final t = raw.trim();
    if (t.isEmpty) return null;

    if (RegExp(r'^-?\d+(\.\d+)?$').hasMatch(t)) {
      final v = double.tryParse(t);
      if (v == null) return null;
      return _clamp(v, maxSeconds);
    }

    final parts = t.split(':');
    if (parts.length == 2) {
      // e.g. `27:300` → 27.3 s (sec + 3-digit millis), not 27:05.
      final head = parts[0].trim();
      final tail = parts[1].trim();
      if (RegExp(r'^\d{1,2}$').hasMatch(head) &&
          RegExp(r'^\d{3}$').hasMatch(tail)) {
        final sec = int.tryParse(head);
        final ms = int.tryParse(tail);
        if (sec != null && ms != null) {
          return _clamp(sec + ms / 1000.0, maxSeconds);
        }
      }
      return _parseMinSecFrac(parts[0], parts[1], maxSeconds);
    }
    if (parts.length == 3) {
      final m = int.tryParse(parts[0].trim()) ?? 0;
      final s = int.tryParse(parts[1].trim()) ?? 0;
      final msPart = parts[2].trim();
      final ms = int.tryParse(msPart.padRight(3, '0').substring(0, 3)) ?? 0;
      final total = m * 60 + s + ms / 1000.0;
      return _clamp(total, maxSeconds);
    }
    return null;
  }

  static double? _parseMinSecFrac(
    String minPart,
    String secPart,
    double maxSeconds,
  ) {
    final m = int.tryParse(minPart.trim()) ?? 0;
    if (secPart.contains('.')) {
      final bits = secPart.split('.');
      final s = int.tryParse(bits[0].trim()) ?? 0;
      final frac = bits[1].trim();
      final ms = int.tryParse(frac.padRight(3, '0').substring(0, 3)) ?? 0;
      return _clamp(m * 60 + s + ms / 1000.0, maxSeconds);
    }
    final s = int.tryParse(secPart.trim()) ?? 0;
    return _clamp(m * 60 + s.toDouble(), maxSeconds);
  }

  static double _clamp(double v, double maxSeconds) {
    if (v < 0) return 0;
    if (v > maxSeconds) return maxSeconds;
    return v;
  }
}