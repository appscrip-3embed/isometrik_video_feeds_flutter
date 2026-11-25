import 'package:ism_video_reel_player/domain/models/models.dart';

class HighlightViewerResolver {
  const HighlightViewerResolver._();

  static String normalizeStoryId(String? id) => (id ?? '').trim();

  static List<String> normalizedStoryIds(Iterable<String?> ids) {
    final seen = <String>{};
    final out = <String>[];
    for (final id in ids) {
      final normalized = normalizeStoryId(id);
      if (normalized.isEmpty || seen.contains(normalized)) continue;
      seen.add(normalized);
      out.add(normalized);
    }
    return out;
  }

  static List<StoryData> storiesFromGroups(List<StoryGroup> groups) =>
      groups.expand((group) => group.stories).toList();

  /// Feed/highlight cache rows often lack `view_count`; highlight detail has it.
  static List<StoryData> applyEngagementMetrics({
    required List<StoryData> resolved,
    required Iterable<StoryData> metricSources,
  }) {
    if (resolved.isEmpty) return resolved;
    final byId = <String, StoryData>{};
    for (final source in metricSources) {
      final id = normalizeStoryId(source.id);
      if (id.isEmpty) continue;
      final existing = byId[id];
      if (existing == null || source.viewCount > existing.viewCount) {
        byId[id] = source;
      }
    }
    if (byId.isEmpty) return resolved;
    return resolved
        .map((story) {
          final metric = byId[normalizeStoryId(story.id)];
          if (metric == null || metric.viewCount <= story.viewCount) {
            return story;
          }
          return story.copyWith(
            viewCount: metric.viewCount,
            engagementMetrics:
                story.engagementMetrics ?? metric.engagementMetrics,
          );
        })
        .toList();
  }

  static List<StoryData> resolveStoriesByIds({
    required List<StoryData> stories,
    required List<String> storyIds,
  }) {
    if (stories.isEmpty || storyIds.isEmpty) return const [];
    final byId = <String, StoryData>{};
    for (final story in stories) {
      final id = normalizeStoryId(story.id);
      if (id.isEmpty) continue;
      byId[id] = story;
    }

    final resolved = <StoryData>[];
    for (final id in normalizedStoryIds(storyIds)) {
      final story = byId[id];
      if (story == null) continue;
      if (story.mediaUrl.trim().isEmpty) continue;
      resolved.add(story);
    }
    return resolved;
  }
}
