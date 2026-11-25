import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ism_video_reel_player/data/data.dart';
import 'package:ism_video_reel_player/domain/domain.dart';
import 'package:ism_video_reel_player/isr_video_reel_config.dart';
import 'package:ism_video_reel_player/presentation/cubits/social_action/social_action_cubit.dart';
import 'package:ism_video_reel_player/presentation/presentation.dart';
import 'package:ism_video_reel_player/presentation/screens/posts/widgets/text_post_thumbnail.dart';
import 'package:ism_video_reel_player/presentation/screens/profile/profile_posts_placeholder.dart';
import 'package:ism_video_reel_player/presentation/screens/profile/profile_text_posts_feed.dart';
import 'package:ism_video_reel_player/presentation/screens/profile/widgets/paid_post_locked_profile_thumbnail.dart';
import 'package:ism_video_reel_player/res/res.dart';
import 'package:ism_video_reel_player/utils/enums.dart';
import 'package:ism_video_reel_player/utils/extensions.dart';
import 'package:ism_video_reel_player/utils/navigator/isr_app_navigator.dart';
import 'package:ism_video_reel_player/utils/profile_media_url_util.dart';
import 'package:ism_video_reel_player/utils/profile_post_type_filter.dart';
import 'package:ism_video_reel_player/utils/timeline_post_type_util.dart';

/// Profile posts tab grid (and optional media/text filter pills).
class IsrProfilePostsTab extends StatelessWidget {
  const IsrProfilePostsTab({
    super.key,
    required this.isLoading,
    required this.posts,
    required this.onRefresh,
    required this.postSectionType,
    this.extractMediaUrl,
    this.emptyIcon,
    this.emptyTitle,
    this.emptySubtitle,
    this.tagValue,
    this.tagType,
    this.onMentionRemoved,
    this.loggedInUserId,
    this.isLoadingMore = false,
    this.profileOwnerUserId,
    this.profileOwnerClientUserId,
    this.lockSeededPostList = false,
  });

  final bool isLoading;
  final bool isLoadingMore;
  final List<dynamic> posts;
  final Future<void> Function() onRefresh;
  final PostSectionType postSectionType;
  final String? Function(dynamic post)? extractMediaUrl;
  final String? emptyIcon;
  final String? emptyTitle;
  final String? emptySubtitle;
  final String? tagValue;
  final TagType? tagType;
  final void Function(String postId, String userId)? onMentionRemoved;
  final String? loggedInUserId;
  final String? profileOwnerUserId;
  final String? profileOwnerClientUserId;
  final bool lockSeededPostList;

  bool get _usePostTypeFilter =>
      IsrVideoReelConfig.postConfig.resolvedProfilePostsConfig
          .enablePostTypeTabs;

  @override
  Widget build(BuildContext context) {
    if (_usePostTypeFilter) {
      return _ProfilePostsTypeFilterTab(
        isLoading: isLoading,
        posts: posts.whereType<TimeLineData>().toList(),
        extractMediaUrl: extractMediaUrl,
        onRefresh: onRefresh,
        emptyIcon: emptyIcon,
        emptyTitle: emptyTitle,
        emptySubtitle: emptySubtitle,
        postSectionType: postSectionType,
        tagValue: tagValue,
        tagType: tagType,
        onMentionRemoved: onMentionRemoved,
        loggedInUserId: loggedInUserId,
        isLoadingMore: isLoadingMore,
        profileOwnerUserId: profileOwnerUserId,
        profileOwnerClientUserId: profileOwnerClientUserId,
        lockSeededPostList: lockSeededPostList,
      );
    }

    return _ProfilePostsSocialListener(
      onRefresh: onRefresh,
      onMentionRemoved: onMentionRemoved,
      postSectionType: postSectionType,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: IsrVideoReelConfig.postConfig
              .resolvedProfilePostsConfig.contentHorizontalPadding,
        ),
        child: _ProfilePostsGrid(
          isLoading: isLoading,
          posts: posts,
          extractMediaUrl: extractMediaUrl,
          emptyIcon: emptyIcon,
          emptyTitle: emptyTitle,
          emptySubtitle: emptySubtitle,
          postSectionType: postSectionType,
          tagValue: tagValue,
          tagType: tagType,
          loggedInUserId: loggedInUserId,
          lockSeededPostList: lockSeededPostList,
        ),
      ),
    );
  }
}

class _ProfilePostsTypeFilterTab extends StatefulWidget {
  const _ProfilePostsTypeFilterTab({
    required this.isLoading,
    required this.posts,
    required this.onRefresh,
    required this.postSectionType,
    this.extractMediaUrl,
    this.emptyIcon,
    this.emptyTitle,
    this.emptySubtitle,
    this.tagValue,
    this.tagType,
    this.onMentionRemoved,
    this.loggedInUserId,
    this.isLoadingMore = false,
    this.profileOwnerUserId,
    this.profileOwnerClientUserId,
    this.lockSeededPostList = false,
  });

  final bool isLoading;
  final bool isLoadingMore;
  final List<TimeLineData> posts;
  final String? Function(dynamic post)? extractMediaUrl;
  final Future<void> Function() onRefresh;
  final String? emptyIcon;
  final String? emptyTitle;
  final String? emptySubtitle;
  final PostSectionType postSectionType;
  final String? tagValue;
  final TagType? tagType;
  final void Function(String postId, String userId)? onMentionRemoved;
  final String? loggedInUserId;
  final String? profileOwnerUserId;
  final String? profileOwnerClientUserId;
  final bool lockSeededPostList;

  @override
  State<_ProfilePostsTypeFilterTab> createState() =>
      _ProfilePostsTypeFilterTabState();
}

class _ProfilePostsTypeFilterTabState extends State<_ProfilePostsTypeFilterTab> {
  ProfilePostTypeFilter _selectedFilter = ProfilePostTypeFilter.media;
  final GlobalKey<_ProfileScheduledPostsSectionState> _scheduledPostsKey =
      GlobalKey<_ProfileScheduledPostsSectionState>();

  bool get _showScheduledTab {
    final profileConfig =
        IsrVideoReelConfig.postConfig.resolvedProfilePostsConfig;
    if (!profileConfig.enableScheduledPostsTab) return false;
    if (widget.postSectionType != PostSectionType.myPost) return false;
    final memberId = (widget.profileOwnerClientUserId ?? '').trim().isNotEmpty
        ? widget.profileOwnerClientUserId!.trim()
        : (widget.profileOwnerUserId ?? '').trim();
    return memberId.isNotEmpty;
  }

  String? get _scheduledMemberId {
    if (!_showScheduledTab) return null;
    final clientId = (widget.profileOwnerClientUserId ?? '').trim();
    if (clientId.isNotEmpty) return clientId;
    return (widget.profileOwnerUserId ?? '').trim();
  }

  bool _onAncestorScrollNotification(ScrollNotification notification) {
    if (_selectedFilter != ProfilePostTypeFilter.scheduled) return false;
    if (notification.metrics.extentAfter > 500) return false;
    if (notification is ScrollUpdateNotification ||
        notification is OverscrollNotification) {
      _scheduledPostsKey.currentState?.maybeLoadMore();
    }
    return false;
  }

  void _selectFilter(ProfilePostTypeFilter filter) {
    if (_selectedFilter == filter) return;
    setState(() => _selectedFilter = filter);
  }

  Future<void> _handlePostsRefresh() async {
    await widget.onRefresh();
    if (_selectedFilter == ProfilePostTypeFilter.scheduled) {
      await _scheduledPostsKey.currentState?.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileConfig =
        IsrVideoReelConfig.postConfig.resolvedProfilePostsConfig;
    final filteredPosts = filterProfilePostsByType(
      widget.posts,
      _selectedFilter,
    );
    final horizontalPadding = profileConfig.contentHorizontalPadding;
    final isMediaFilter = _selectedFilter == ProfilePostTypeFilter.media;
    final isTextFilter = _selectedFilter == ProfilePostTypeFilter.text;
    final isScheduledFilter =
        _selectedFilter == ProfilePostTypeFilter.scheduled;

    return _ProfilePostsSocialListener(
      onRefresh: _handlePostsRefresh,
      onMentionRemoved: widget.onMentionRemoved,
      postSectionType: widget.postSectionType,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onAncestorScrollNotification,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  _ProfilePostTypePill(
                    title: IsrTranslationFile.profileMediaPostsTab,
                    isSelected: isMediaFilter,
                    onTap: () => _selectFilter(ProfilePostTypeFilter.media),
                  ),
                  const SizedBox(width: 8),
                  _ProfilePostTypePill(
                    title: IsrTranslationFile.profileTextPostsTab,
                    isSelected: isTextFilter,
                    onTap: () => _selectFilter(ProfilePostTypeFilter.text),
                  ),
                  if (_showScheduledTab) ...[
                    const SizedBox(width: 8),
                    _ProfilePostTypePill(
                      title: IsrTranslationFile.scheduled,
                      isSelected: isScheduledFilter,
                      onTap: () =>
                          _selectFilter(ProfilePostTypeFilter.scheduled),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (isMediaFilter)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: _ProfilePostsGrid(
                  isLoading: widget.isLoading,
                  posts: filteredPosts,
                  extractMediaUrl: widget.extractMediaUrl,
                  emptyIcon: profileConfig.resolvedNoMediaPostsIcon,
                  emptyTitle: IsrTranslationFile.profileNoMediaPostsTitle,
                  emptySubtitle: IsrTranslationFile.profileNoMediaPostsSubtitle,
                  postSectionType: widget.postSectionType,
                  tagValue: widget.tagValue,
                  tagType: widget.tagType,
                  loggedInUserId: widget.loggedInUserId,
                  lockSeededPostList: widget.lockSeededPostList,
                ),
              )
            else if (isTextFilter)
              ProfileTextPostsFeed(
                posts: filteredPosts,
                isLoading: widget.isLoading,
                isLoadingMore: widget.isLoadingMore,
                postSectionType: widget.postSectionType,
                loggedInUserId: widget.loggedInUserId,
                profileOwnerUserId: widget.profileOwnerUserId,
                profileOwnerClientUserId: widget.profileOwnerClientUserId,
              )
            else if (isScheduledFilter && _scheduledMemberId != null)
              _ProfileScheduledPostsSection(
                key: _scheduledPostsKey,
                memberId: _scheduledMemberId!,
                postSectionType: widget.postSectionType,
                contentHorizontalPadding: horizontalPadding,
                loggedInUserId: widget.loggedInUserId,
                extractMediaUrl: widget.extractMediaUrl,
              ),
          ],
        ),
      ),
    );
  }
}

class _ProfilePostTypePill extends StatelessWidget {
  const _ProfilePostTypePill({
    required this.title,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = IsrVideoReelConfig.socialConfig.themeConfig;
    final isDark = (theme?.brightness ?? Brightness.light) == Brightness.dark;
    final primary = theme?.primaryColor ?? IsrColors.appColor;
    final background =
        theme?.scaffoldBackgroundColor ?? IsrColors.scaffoldColor;
    final selectedFill = Color.alphaBlend(
      primary.withValues(alpha: 0.12),
      background,
    );
    final textColor = IsrColors.primaryTextColor;
    final borderColor = isSelected
        ? primary
        : (isDark
            ? IsrColors.primaryTextColor.withValues(alpha: 0.28)
            : const Color(0xFFD8DEF3));

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? selectedFill : background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: borderColor),
        ),
        child: Text(
          title,
          style: TextStyle(
            inherit: false,
            textBaseline: TextBaseline.alphabetic,
            color: textColor,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
            height: 1.2,
            fontFamily: AppConstants.primaryFontFamily,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

class _ProfilePostsSocialListener extends StatelessWidget {
  const _ProfilePostsSocialListener({
    required this.onRefresh,
    required this.postSectionType,
    required this.child,
    this.onMentionRemoved,
  });

  final Future<void> Function() onRefresh;
  final PostSectionType postSectionType;
  final Widget child;
  final void Function(String postId, String userId)? onMentionRemoved;

  bool get _isTaggedPostSection =>
      postSectionType == PostSectionType.myTaggedPost ||
      postSectionType == PostSectionType.tagPost;

  @override
  Widget build(BuildContext context) {
    return context.attachBlocIfNeeded<IsmSocialActionCubit>(
      bloc: context.getOrCreateBloc<IsmSocialActionCubit>(),
      child: BlocListener<IsmSocialActionCubit, IsmSocialActionState>(
        listenWhen: (previous, current) =>
            current is IsmDeletedPostActionListenerState ||
            current is IsmEditPostActionListenerState ||
            current is IsmCreatePostActionListenerState ||
            (current is IsmMentionRemovedActionListenerState &&
                _isTaggedPostSection),
        listener: (context, state) {
          if (state is IsmDeletedPostActionListenerState ||
              state is IsmEditPostActionListenerState ||
              state is IsmCreatePostActionListenerState) {
            onRefresh();
          } else if (state is IsmMentionRemovedActionListenerState) {
            final removed = onMentionRemoved;
            if (removed != null) {
              removed(state.postId, state.userId);
            } else {
              onRefresh();
            }
          }
        },
        child: child,
      ),
    );
  }
}

class _ProfilePostsGrid extends StatelessWidget {
  const _ProfilePostsGrid({
    required this.isLoading,
    required this.posts,
    required this.postSectionType,
    this.extractMediaUrl,
    this.emptyIcon,
    this.emptyTitle,
    this.emptySubtitle,
    this.tagValue,
    this.tagType,
    this.loggedInUserId,
    this.lockSeededPostList = false,
  });

  final bool isLoading;
  final List<dynamic> posts;
  final String? Function(dynamic post)? extractMediaUrl;
  final String? emptyIcon;
  final String? emptyTitle;
  final String? emptySubtitle;
  final PostSectionType postSectionType;
  final String? tagValue;
  final TagType? tagType;
  final String? loggedInUserId;
  final bool lockSeededPostList;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: Column(children: [SizedBox(height: 100), AppLoader()]),
      );
    }

    if (posts.isEmpty) {
      return ProfilePostsPlaceholder(
        icon: emptyIcon ?? AssetConstants.icNoProfilePosts,
        title: emptyTitle ?? IsrTranslationFile.noPostAvailable,
        subtitle: emptySubtitle ?? '',
      );
    }

    final profileConfig =
        IsrVideoReelConfig.postConfig.resolvedProfilePostsConfig;
    final cardsBg =
        IsrVideoReelConfig.socialConfig.themeConfig?.scaffoldBackgroundColor ??
            const Color(0xFFF5F5F5);
    final resolveMediaUrl =
        extractMediaUrl ?? ProfileMediaUrlUtil.extractMediaUrl;

    return GridView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 30),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: posts.length,
      itemBuilder: (context, index) {
        final postDataList = posts.whereType<TimeLineData>().toList();
        final post = posts[index] is TimeLineData
            ? posts[index] as TimeLineData
            : null;
        final mediaUrl = resolveMediaUrl(posts[index]) ?? '';
        final isPaidLocked = lockSeededPostList
            ? false
            : shouldShowPaidLockedProfileThumbnailForPost(post);
        return DecoratedBox(
          decoration: BoxDecoration(
            color: cardsBg,
            borderRadius: BorderRadius.circular(4),
          ),
          child: TapHandler(
            onTap: () {
              final tappedPost = posts[index];
              final startIndex = tappedPost is TimeLineData
                  ? postDataList.indexOf(tappedPost)
                  : index;
              if (startIndex < 0) return;
              final postConfig = IsrVideoReelConfig.postConfig;
              final overlayPadding = profileConfig.reelsPlayerOverlayPadding;
              final playerPostConfig = overlayPadding != null
                  ? postConfig.copyWith(
                      postUIConfig: (postConfig.postUIConfig ??
                              const PostUIConfig())
                          .copyWith(overlayPadding: overlayPadding),
                    )
                  : postConfig;
              IsrAppNavigator.navigateToReelsPlayer(
                context,
                postDataList: postDataList,
                startingPostIndex: startIndex,
                postSectionType: postSectionType,
                tagValue: tagValue,
                tagType: tagType,
                postConfig: playerPostConfig,
                tabConfig: profileConfig.tabConfig,
                lockSeededPostList: lockSeededPostList,
              );
            },
            child: PaidPostLockedProfileThumbnail(
              isLocked: isPaidLocked,
              child: _ProfilePostThumbnail(
                post: post,
                mediaUrl: mediaUrl,
                isPaidLocked: isPaidLocked,
                views: post?.engagementMetrics?.views?.toInt() ?? 0,
                placeholderColor: cardsBg,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProfilePostThumbnail extends StatelessWidget {
  const _ProfilePostThumbnail({
    required this.post,
    required this.mediaUrl,
    required this.isPaidLocked,
    required this.views,
    required this.placeholderColor,
  });

  final TimeLineData? post;
  final String mediaUrl;
  final bool isPaidLocked;
  final int views;
  final Color placeholderColor;

  @override
  Widget build(BuildContext context) {
    if (post?.isTextOnlyPost == true) {
      return TextPostThumbnail.fromPost(post!);
    }

    if (mediaUrl.isEmpty) {
      return ColoredBox(
        color: placeholderColor,
        child: const Center(
          child: Icon(Icons.image, color: Color(0xFF979797)),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: AppImage.network(
            mediaUrl,
            fit: BoxFit.cover,
          ),
        ),
        if (!isPaidLocked)
          Positioned(
            bottom: 4,
            left: 4,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.play_arrow, color: Colors.white, size: 14),
                const SizedBox(width: 3),
                Text(
                  '$views',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Own-profile scheduled sub-tab (`scheduled_only=true` on user posts API).
class _ProfileScheduledPostsSection extends StatefulWidget {
  const _ProfileScheduledPostsSection({
    super.key,
    required this.memberId,
    required this.postSectionType,
    required this.contentHorizontalPadding,
    this.loggedInUserId,
    this.extractMediaUrl,
    this.pageSize = 20,
  });

  final String memberId;
  final PostSectionType postSectionType;
  final double contentHorizontalPadding;
  final String? loggedInUserId;
  final String? Function(dynamic post)? extractMediaUrl;
  final int pageSize;

  @override
  State<_ProfileScheduledPostsSection> createState() =>
      _ProfileScheduledPostsSectionState();
}

class _ProfileScheduledPostsSectionState
    extends State<_ProfileScheduledPostsSection> {
  final List<TimeLineData> _posts = [];
  var _page = 0;
  var _hasMore = true;
  var _isLoading = false;
  var _isLoadingMore = false;
  var _hasLoadedOnce = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load(refresh: true));
  }

  Future<void> refresh() => _load(refresh: true);

  void maybeLoadMore() {
    if (!_hasMore || _isLoading || _isLoadingMore) return;
    unawaited(_load(refresh: false));
  }

  Future<void> _load({required bool refresh}) async {
    if (_isLoading || _isLoadingMore) return;
    if (!refresh && (!_hasMore || _page < 1)) return;

    final nextPage = refresh ? 1 : _page + 1;
    if (!mounted) return;
    setState(() {
      if (refresh) {
        _isLoading = true;
        _isLoadingMore = false;
      } else {
        _isLoadingMore = true;
      }
    });

    final completer = Completer<void>();
    await IsmDataProvider.instance.getUserPosts(
      userId: widget.memberId,
      page: nextPage,
      pageSize: widget.pageSize,
      scheduledOnly: true,
      isLoading: false,
      onSuccess: (result, responseCode) {
        if (!mounted) {
          if (!completer.isCompleted) completer.complete();
          return;
        }
        final timeline = timelineResponseFromJson(result);
        final incoming = timeline.data ?? <TimeLineData>[];
        setState(() {
          _hasLoadedOnce = true;
          if (refresh) {
            _posts
              ..clear()
              ..addAll(incoming);
          } else {
            _posts.addAll(incoming);
          }
          _page = nextPage;
          final total = timeline.total?.toInt();
          _hasMore = total != null && total > 0
              ? _posts.length < total
              : incoming.length >= widget.pageSize;
          _isLoading = false;
          _isLoadingMore = false;
        });
        if (!completer.isCompleted) completer.complete();
      },
      onError: (_, __) {
        if (!mounted) {
          if (!completer.isCompleted) completer.complete();
          return;
        }
        setState(() {
          _hasLoadedOnce = true;
          if (refresh) {
            _posts.clear();
            _page = 0;
            _hasMore = true;
          }
          _isLoading = false;
          _isLoadingMore = false;
        });
        if (!completer.isCompleted) completer.complete();
      },
    );
    await completer.future;
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<IsmSocialActionCubit, IsmSocialActionState>(
      listenWhen: (previous, current) =>
          current is IsmDeletedPostActionListenerState ||
          current is IsmEditPostActionListenerState ||
          current is IsmCreatePostActionListenerState,
      listener: (_, __) => unawaited(_load(refresh: true)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: widget.contentHorizontalPadding,
            ),
            child: _ProfilePostsGrid(
              isLoading: _isLoading,
              posts: _posts,
              extractMediaUrl: widget.extractMediaUrl,
              emptyIcon: AssetConstants.icNoScheduledPost,
              emptyTitle: IsrTranslationFile.noScheduledPosts,
              emptySubtitle: IsrTranslationFile.addNewScheduledPosts,
              postSectionType: widget.postSectionType,
              loggedInUserId: widget.loggedInUserId,
            ),
          ),
          if (_isLoadingMore)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator.adaptive()),
            ),
        ],
      ),
    );
  }
}
