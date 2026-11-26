import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:ism_video_reel_player/domain/domain.dart';
import 'package:ism_video_reel_player/isr_video_reel_config.dart';
import 'package:ism_video_reel_player/presentation/presentation.dart';
import 'package:ism_video_reel_player/res/res.dart';
import 'package:ism_video_reel_player/utils/utils.dart';

/// Tag-people UI uses **cover/preview stills** for video items — not [VideoPlayer].
/// Playback on this route conflicted with create-post's hidden controllers on the
/// same local file and triggered framework errors when popping back (video only).
class TagPeopleScreen extends StatefulWidget {
  const TagPeopleScreen({
    Key? key,
    required this.mentionDataList,
    required this.mediaDataList,
    this.postId,
    /// Same still as upload / create-post cover preview ([CreatePostCoverStillUtil]).
    this.postCoverStillPath,
  }) : super(key: key);

  final List<MentionData> mentionDataList;
  final List<MediaData> mediaDataList;
  final String? postId;
  final String? postCoverStillPath;

  @override
  State<TagPeopleScreen> createState() => _TagPeopleScreenState();
}

class _TagPeopleScreenState extends State<TagPeopleScreen> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;
  final Map<int, List<MentionData>> _mediaMentionedMap =
      {}; // Mentioned for each media item
  final Map<int, List<MentionData>> _mediaTaggedMap =
      {}; // Tagged for each media item
  final Map<int, GlobalKey> _mentionedImageKeys =
      {}; // Unique keys for each image
  final Map<int, GlobalKey> _mentionedVideoKeys =
      {}; // Unique keys for each video
  var _mediaDataList = <MediaData>[];
  var _mentionDataList = <MentionData>[];

  // Configuration getters
  TagPeopleScreenConfig? get _tagPeopleConfig => IsrVideoReelConfig
      .createEditPostConfig
      .createEditPostUIConfig
      ?.tagPeopleUIConfig
      ?.tagPeopleScreenConfig;

  bool get _isDark =>
      (IsrVideoReelConfig.socialConfig.themeConfig?.brightness ??
          Brightness.light) ==
      Brightness.dark;

  Color get _scaffoldBg => IsrColors.scaffoldColor;

  Color get _surfaceCard => _isDark
      ? (IsrVideoReelConfig.socialConfig.colorsConfig?.dialogColor ??
          const Color(0xFF2C2C2E))
      : Colors.grey[100]!;

  Color get _dividerColor => _isDark
      ? IsrColors.primaryTextColor.withValues(alpha: 0.18)
      : '#DBDBDB'.toColor();

  /// Prevents [setState] while the route is tearing down.
  bool _isRouteClosing = false;

  @override
  void initState() {
    _onStartInit();
    super.initState();
  }

  void _onStartInit() {
    _mentionDataList = widget.mentionDataList;
    _mediaDataList = widget.mediaDataList;

    _mediaMentionedMap.clear();
    for (final mention in _mentionDataList) {
      final pos = mention.mediaPosition?.position?.toInt() ?? 1;
      _mediaMentionedMap.putIfAbsent(pos, () => []).add(mention);
    }

    updateMentionListWithPostMentionListFromAPI();
  }

  var _isPostMentionedApiLoading = false;

  bool get _hasMentionsMissingProfileData => _mentionDataList
      .any((mention) => mention.name?.trim().isNotEmpty != true);

  /// if the mention list is from edit post they will not have all mention data
  /// so we call a separate api to update the mention list with the post mention list
  void updateMentionListWithPostMentionListFromAPI({int page = 1}) {
    if (widget.postId?.trim().isNotEmpty != true) {
      return;
    }
    if (page == 1 && !_hasMentionsMissingProfileData) {
      return;
    }

    final socialPostBloc = context.getOrCreateBloc<SocialPostBloc>();
    if (page == 1) {
      _isPostMentionedApiLoading = true;
    }

    socialPostBloc.add(GetMentionedUserEvent(
      postId: widget.postId ?? '',
      page: page,
      onComplete: (userList, hasMore) {
        if (mounted && !_isRouteClosing) {
          setState(() {
            for (final user in userList) {
              final mention = _mentionDataList
                  .where((element) => element.userId == user.id)
                  .firstOrNull;
              mention?.name = user.fullName;
              mention?.avatarUrl = user.avatarUrl;
            }
          });
        }

        final shouldFetchNextPage =
            hasMore && _hasMentionsMissingProfileData && mounted;
        if (shouldFetchNextPage) {
          updateMentionListWithPostMentionListFromAPI(page: page + 1);
          return;
        }

        _isPostMentionedApiLoading = false;
        if (mounted && !_isRouteClosing) {
          setState(() {});
        }
      },
    ));
  }

  Future<void> _popRoute<T>([T? result]) async {
    if (_isRouteClosing) return;
    _isRouteClosing = true;
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop<T>(result);
  }

  /// Check if the mention data is loading
  bool _isMentionLoading(MentionData mention) => _isPostMentionedApiLoading && mention.name?.trim().isEmpty == true && _mentionDataList.any((element) => element.userId == mention.userId);

  // List<MentionData> get currentMentions => _mediaMentionedMap[_currentIndex + 1] ?? [];

  List<MentionData> get currentMentions => _mediaMentionedMap.values.expand((list) => list).toSet().toList();

  List<MentionData> get currentTags => _mediaTaggedMap[_currentIndex] ?? [];

  @override
  void dispose() {
    _isRouteClosing = true;
    _pageController.dispose();
    super.dispose();
  }

  bool _isVideoMedia(MediaData mediaData) =>
      mediaData.mediaType?.mediaType == MediaType.video ||
      mediaData.mediaType == 'video';

  String? _previewImageUrl(MediaData mediaData) {
    if (_isVideoMedia(mediaData)) {
      final postCover = widget.postCoverStillPath?.trim();
      if (postCover != null && postCover.isNotEmpty) return postCover;
      final onMediaCover = mediaData.coverFileLocalPath?.trim();
      if (onMediaCover != null && onMediaCover.isNotEmpty) return onMediaCover;
      final autoPreview = mediaData.previewUrl?.trim();
      if (autoPreview != null && autoPreview.isNotEmpty) return autoPreview;
      return null;
    }
    if (mediaData.previewUrl?.isNotEmpty == true) {
      return mediaData.previewUrl;
    }
    if (mediaData.coverFileLocalPath?.isNotEmpty == true) {
      return mediaData.coverFileLocalPath;
    }
    return _getMediaUrl(mediaData);
  }

  Widget _buildVideoThumbnailPlaceholder(MediaData mediaData) {
    final previewUrl = _previewImageUrl(mediaData);
    if (previewUrl?.isNotEmpty == true) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Utility.isLocalUrl(previewUrl!)
              ? AppImage.file(
                  previewUrl,
                  fit: BoxFit.cover,
                  borderRadius: BorderRadius.circular(12),
                )
              : AppImage.network(
                  previewUrl,
                  fit: BoxFit.cover,
                  borderRadius: BorderRadius.circular(12),
                ),
          const Center(
            child: Icon(Icons.play_circle_fill, size: 64, color: Colors.white70),
          ),
        ],
      );
    }

    return Container(
      color: Colors.black,
      child: const Center(
        child: Icon(Icons.videocam, size: 64, color: Colors.white70),
      ),
    );
  }

  /// Get media URL (local or remote) with proper priority
  String _getMediaUrl(MediaData mediaData) {
    // Check for local path first (for new uploads)
    if (mediaData.localPath?.isNotEmpty == true) {
      return mediaData.localPath!;
    }
    // Check for remote URL (for existing/edited posts)
    else if (mediaData.url?.isNotEmpty == true) {
      return mediaData.url!;
    }
    // Return empty string if no valid URL found
    return '';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _scaffoldBg,
        appBar: IsmCustomAppBarWidget(
          backgroundColor:
              _tagPeopleConfig?.appBarConfig?.backgroundColor ?? _scaffoldBg,
          leading: IconButton(
            icon: Icon(
              Icons.close,
              color: IsrColors.appBarIconTextColor,
              size: 24.responsiveDimension,
            ),
            onPressed: _closeWithoutSaving,
          ),
          titleText: 'Tag people',
          isCrossIcon: true,
          centerTitle: true,
          showActions: true,
          titleStyle: _tagPeopleConfig?.appBarConfig?.titleStyle ??
              IsrStyles.primaryText16.copyWith(
                color: IsrColors.primaryTextColor,
                fontWeight: FontWeight.w600,
              ),
          actions: [
            IconButton(
              onPressed: _completeTagging,
              icon: Icon(
                Icons.check,
                color: IsrColors.appBarIconTextColor,
                size: 24.responsiveDimension,
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Media Carousel Section with Tagging
              Expanded(
                flex: 2,
                child: Container(
                  margin: const EdgeInsets.all(16),
                  decoration: _tagPeopleConfig
                          ?.mediaCarouselConfig?.containerDecoration ??
                      BoxDecoration(
                        color: _surfaceCard,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.changeOpacity(_isDark ? 0.35 : 0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      children: [
                        // Media PageView
                        PageView.builder(
                          controller: _pageController,
                          onPageChanged: (index) {
                            setState(() {
                              _currentIndex = index;
                            });
                          },
                          itemCount: _mediaDataList.length,
                          itemBuilder: (context, index) {
                            final mediaData = _mediaDataList[index];
                            if (_isVideoMedia(mediaData)) {
                              return _buildTaggableVideoView(mediaData, index);
                            } else {
                              // Get image URL (local or remote)
                              final imageUrl = _getMediaUrl(mediaData);
                              return _buildTaggableImageView(imageUrl, index);
                            }
                          },
                        ),

                        // Page Indicators (only show if multiple items)
                        if (_mediaDataList.length > 1)
                          Positioned(
                            bottom: 16,
                            left: 0,
                            right: 0,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(
                                _mediaDataList.length,
                                (index) => AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  margin: EdgeInsets.symmetric(
                                      horizontal: _tagPeopleConfig
                                              ?.mediaCarouselConfig
                                              ?.pageIndicatorConfig
                                              ?.spacing ??
                                          4),
                                  width: _currentIndex == index
                                      ? (_tagPeopleConfig
                                              ?.mediaCarouselConfig
                                              ?.pageIndicatorConfig
                                              ?.activeWidth ??
                                          24)
                                      : (_tagPeopleConfig
                                              ?.mediaCarouselConfig
                                              ?.pageIndicatorConfig
                                              ?.inactiveWidth ??
                                          8),
                                  height: _tagPeopleConfig?.mediaCarouselConfig
                                          ?.pageIndicatorConfig?.height ??
                                      8,
                                  decoration: BoxDecoration(
                                    color: _currentIndex == index
                                        ? (_tagPeopleConfig
                                                ?.mediaCarouselConfig
                                                ?.pageIndicatorConfig
                                                ?.activeColor ??
                                            Colors.white)
                                        : (_tagPeopleConfig
                                                ?.mediaCarouselConfig
                                                ?.pageIndicatorConfig
                                                ?.inactiveColor ??
                                            Colors.white.changeOpacity(0.5)),
                                    borderRadius: BorderRadius.circular(
                                        _tagPeopleConfig
                                                ?.mediaCarouselConfig
                                                ?.pageIndicatorConfig
                                                ?.borderRadius ??
                                            4),
                                  ),
                                ),
                              ),
                            ),
                          ),

                        // Media counter (top right)
                        if (_mediaDataList.length > 1)
                          Positioned(
                            top: 16,
                            right: 16,
                            child: Container(
                              padding: _tagPeopleConfig?.mediaCarouselConfig
                                      ?.mediaCounterConfig?.padding ??
                                  const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: _tagPeopleConfig?.mediaCarouselConfig
                                        ?.mediaCounterConfig?.backgroundColor ??
                                    Colors.black.applyOpacity(0.7),
                                borderRadius: BorderRadius.circular(
                                    _tagPeopleConfig
                                            ?.mediaCarouselConfig
                                            ?.mediaCounterConfig
                                            ?.borderRadius ??
                                        16),
                              ),
                              child: Text(
                                '${_currentIndex + 1}/${_mediaDataList.length}',
                                style: _tagPeopleConfig?.mediaCarouselConfig
                                        ?.mediaCounterConfig?.textStyle ??
                                    const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                              ),
                            ),
                          ),

                        // Tag count indicator (top left)
                        if (currentMentions.isNotEmpty)
                          Positioned(
                            top: 16,
                            left: 16,
                            child: Container(
                              padding: _tagPeopleConfig?.mediaCarouselConfig
                                      ?.tagCountIndicatorConfig?.padding ??
                                  const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: _tagPeopleConfig
                                        ?.mediaCarouselConfig
                                        ?.tagCountIndicatorConfig
                                        ?.backgroundColor ??
                                    Colors.blue.applyOpacity(0.9),
                                borderRadius: BorderRadius.circular(
                                    _tagPeopleConfig
                                            ?.mediaCarouselConfig
                                            ?.tagCountIndicatorConfig
                                            ?.borderRadius ??
                                        16),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.person,
                                      color: _tagPeopleConfig
                                              ?.mediaCarouselConfig
                                              ?.tagCountIndicatorConfig
                                              ?.iconColor ??
                                          Colors.white,
                                      size: 16),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${currentMentions.length}',
                                    style: _tagPeopleConfig
                                            ?.mediaCarouselConfig
                                            ?.tagCountIndicatorConfig
                                            ?.textStyle ??
                                        const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

              // Invite Collaborators Section
              // _buildInviteCollaboratorsSection(),

              // Instructions and Tagged People
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      AppButton(
                        title: IsrTranslationFile.tagPeople,
                        type: ButtonType.secondary,
                        borderColor:
                            _tagPeopleConfig?.tagButtonConfig?.borderColor ??
                                IsrColors.appColor,
                        textColor: _tagPeopleConfig
                                ?.tagButtonConfig?.textStyle?.color ??
                            IsrColors.appColor,
                        borderWidth:
                            _tagPeopleConfig?.tagButtonConfig?.borderWidth ??
                                1.responsiveDimension,
                        borderRadius:
                            _tagPeopleConfig?.tagButtonConfig?.borderRadius,
                        height: _tagPeopleConfig?.tagButtonConfig?.height,
                        backgroundColor:
                            _tagPeopleConfig?.tagButtonConfig?.backgroundColor ??
                                (_isDark ? _surfaceCard : Colors.transparent),
                        onPress: () {
                          _handleImageTap(null, null, 0);
                        },
                      ),
                      if (currentMentions.isEmpty) ...[
                        // // Instructions
                        // const SizedBox(height: 20),
                        // Icon(
                        //   Icons.touch_app_outlined,
                        //   size: 48,
                        //   color: Colors.grey[400],
                        // ),
                        // const SizedBox(height: 16),
                        // Text(
                        //   'Tap photo to tag people',
                        //   style: TextStyle(
                        //     fontSize: 16,
                        //     color: Colors.grey[600],
                        //     fontWeight: FontWeight.w400,
                        //   ),
                        //   textAlign: TextAlign.center,
                        // ),
                      ] else ...[
                        // Tagged People List
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              24.verticalSpace,

                              // Header
                              Text(
                                IsrTranslationFile.taggedPeople,
                                style: _tagPeopleConfig?.taggedPeopleListConfig
                                        ?.headerTitleStyle ??
                                    IsrStyles.primaryText14.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: IsrColors.primaryTextColor,
                                    ),
                              ),
                              4.verticalSpace,
                              Text(
                                IsrTranslationFile.listOfPeopleLinkedToThePost,
                                style: _tagPeopleConfig?.taggedPeopleListConfig
                                        ?.headerSubtitleStyle ??
                                    IsrStyles.primaryText12.copyWith(
                                      color: IsrColors.secondaryTextColor,
                                    ),
                              ),
                              16.verticalSpace,

                              // Tagged people list
                              Expanded(
                                child: ListView.separated(
                                  itemCount: currentMentions.length,
                                  separatorBuilder: (context, index) => Divider(
                                    height: 1,
                                    thickness: 1,
                                    indent: 16.responsiveDimension,
                                    endIndent: 16.responsiveDimension,
                                    color: _dividerColor,
                                  ),
                                  itemBuilder: (context, index) {
                                    final person = currentMentions[index];
                                    return ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: _isMentionLoading(person)
                                          ? CircularProgressIndicator(
                                              color: Theme.of(context)
                                                  .primaryColor,
                                            )
                                          : (!person.avatarUrl.isEmptyOrNull
                                              ? AppImage.network(
                                                  person.avatarUrl ?? '',
                                                  height:
                                                      48.responsiveDimension,
                                                  width: 48.responsiveDimension,
                                                  border: Border.all(
                                                      color: _dividerColor),
                                                  name: person.name ??
                                                      person.username ??
                                                      'User',
                                                  isProfileImage: true,
                                                )
                                              : CircleAvatar(
                                                  radius: IsrDimens.twentyFour,
                                                  backgroundColor: _isDark
                                                      ? IsrColors.appColor
                                                          .withValues(alpha: 0.2)
                                                      : '#E5F0FB'.color,
                                                  child: Text(
                                                    Utility.getInitials(
                                                      firstName: person.name
                                                              ?.split(' ')
                                                              .firstOrNull ??
                                                          '',
                                                      lastName: person.name
                                                              ?.split(' ')
                                                              .lastOrNull ??
                                                          '',
                                                    ),
                                                    style: IsrStyles
                                                        .primaryText14
                                                        .copyWith(
                                                      color: IsrColors.appColor,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                )),
                                      title: Text(
                                        person.name ??
                                            person.username ??
                                            'Unknown User',
                                        style: IsrStyles.primaryText14.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: IsrColors.primaryTextColor,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: person.username != null
                                          ? Text(
                                              person.username!,
                                              style: IsrStyles.secondaryText12
                                                  .copyWith(
                                                color:
                                                    IsrColors.secondaryTextColor,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            )
                                          : null,
                                      trailing: TapHandler(
                                        onTap: () {
                                          setState(() {
                                            _removeMentionFromAllMedia(person);
                                          });
                                        },
                                        child: Icon(
                                          Icons.close,
                                          color: IsrColors.secondaryTextColor,
                                          size: 20,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (currentTags.isNotEmpty) ...[
                        24.verticalSpace,
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Tagged in this photo:',
                            style: TextStyle(
                              inherit: false,
                              textBaseline: TextBaseline.alphabetic,
                              fontSize: 16,
                              color: IsrColors.primaryTextColor,
                              fontWeight: FontWeight.w600,
                              fontFamily: AppConstants.primaryFontFamily,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                        12.verticalSpace,
                        ...currentTags
                            .map((tag) => Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 4),
                                    tileColor: _isDark
                                        ? IsrColors.appColor
                                            .withValues(alpha: 0.15)
                                        : Colors.blue[50],
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    leading: AppImage.network(
                                      tag.avatarUrl ?? '',
                                      height: 30.responsiveDimension,
                                      width: 30.responsiveDimension,
                                      name: tag.name ?? '',
                                      isProfileImage: true,
                                    ),
                                    title: Text(
                                      tag.tag!,
                                      style: TextStyle(
                                        inherit: false,
                                        textBaseline: TextBaseline.alphabetic,
                                        fontWeight: FontWeight.w500,
                                        color: IsrColors.primaryTextColor,
                                        fontFamily:
                                            AppConstants.primaryFontFamily,
                                        decoration: TextDecoration.none,
                                      ),
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.close,
                                          color: Colors.red, size: 20),
                                      onPressed: () {
                                        setState(() {
                                          _mediaTaggedMap[_currentIndex]
                                              ?.remove(tag);
                                        });
                                      },
                                    ),
                                  ),
                                ))
                            .toList(),
                      ],
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildTaggableImageView(String imageUrl, int mediaIndex) {
    // Ensure we have a unique key for this media index
    _mentionedImageKeys.putIfAbsent(mediaIndex, GlobalKey.new);

    // Return empty container if no valid image URL
    if (imageUrl.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Icon(Icons.image_not_supported, size: 64, color: Colors.grey),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        onTapUp: (TapUpDetails details) {
          // _handleImageTap(details, constraints, mediaIndex);
        },
        child: Utility.isLocalUrl(imageUrl)
            ? AppImage.file(
                imageUrl,
                fit: BoxFit.cover,
                borderRadius: BorderRadius.circular(12),
                key: _mentionedImageKeys[
                    mediaIndex], // Use unique key for each image
              )
            : AppImage.network(
                imageUrl,
                fit: BoxFit.cover,
                borderRadius: BorderRadius.circular(12),
                key: _mentionedImageKeys[
                    mediaIndex], // Use unique key for each image
              ),
      ),
    );
  }

  Widget _buildTaggableVideoView(MediaData mediaData, int mediaIndex) {
    _mentionedVideoKeys.putIfAbsent(mediaIndex, GlobalKey.new);
    final videoUrl = _getMediaUrl(mediaData);
    if (videoUrl.isEmpty) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.videocam_off, size: 64, color: Colors.white),
              16.verticalSpace,
              const Text(
                'No video available',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      key: _mentionedVideoKeys[mediaIndex],
      builder: (context, constraints) => GestureDetector(
        onTapUp: (TapUpDetails details) {
          // _handleVideoTap(details, constraints, mediaIndex);
        },
        child: _buildVideoThumbnailPlaceholder(mediaData),
      ),
    );
  }

  void _handleImageTap(TapUpDetails? details, BoxConstraints? constraints,
      int mediaIndex) async {
    // Calculate relative position (0.0 to 1.0)
    final relativePosition = constraints == null || details == null
        ? null
        : Offset(
            (details.localPosition.dx / constraints.maxWidth) * 100,
            (details.localPosition.dy / constraints.maxHeight) * 100,
          );

    // Convert MentionData to SocialUserData (only for current media position)
    final currentMediaPosition = mediaIndex + 1;
    final currentMentions = _mediaMentionedMap[currentMediaPosition] ?? [];
    final selectedUsers = currentMentions
        .map((mentionData) => SocialUserData(
              id: mentionData.userId,
              username: mentionData.username,
              fullName: mentionData.name,
              avatarUrl: mentionData.avatarUrl,
              displayName: mentionData.name,
            ))
        .toList();

    final configMax = _tagPeopleConfig?.maxTaggedPeople ?? 20;
    final mentionsOnOtherMedia = _mediaMentionedMap.entries
        .where((e) => e.key != currentMediaPosition)
        .fold<int>(0, (sum, e) => sum + e.value.length);
    final maxSelectableThisSession =
        (configMax - mentionsOnOtherMedia).clamp(0, configMax);

    final taggedUserList = await IsrAppNavigator.goToSearchUserScreen(
      context,
      socialUserList: selectedUsers,
      maxSelectablePeople: maxSelectableThisSession,
    );

    if (!mounted) return;

    if (taggedUserList.isEmptyOrNull) return;
    _setMentionedUserPosition(taggedUserList, mediaIndex, relativePosition);
  }

  void _setMentionedUserPosition(
      List<SocialUserData> taggedUserList, int mediaIndex, Offset? position) {
    final pos = mediaIndex + 1;

    // Remove existing mentions for this media position completely
    _mediaMentionedMap.remove(pos);

    // Add new mentions from the updated user list
    if (taggedUserList.isNotEmpty) {
      final mentionList = <MentionData>[];
      for (var element in taggedUserList) {
        final mentionData = MentionData(
          mediaPosition: MediaPosition(
            position: pos,
            x: position?.dx.toInt() ?? 0,
            y: position?.dy.toInt() ?? 0,
          ),
          userId: element.id,
          username: element.username,
          name: element.fullName,
          avatarUrl: element.avatarUrl,
        );
        mentionList.add(mentionData);
      }
      _mediaMentionedMap[pos] = mentionList;
    }

    debugPrint(
        'Updated media mentions for position $pos: ${taggedUserList.length} users');
    debugPrint(
        'media mentions....${jsonEncode(_mediaMentionedMap.values.map((list) => list.map((mention) => mention.toJson()).toList()).toList())}');
    setState(() {});
  }

  void _removeMentionFromAllMedia(MentionData person) {
    for (final list in _mediaMentionedMap.values) {
      list.removeWhere((m) => m.userId == person.userId);
    }
    _mediaMentionedMap.removeWhere((_, list) => list.isEmpty);
  }

  void _closeWithoutSaving() {
    if (!mounted) return;
    unawaited(_popRoute<void>());
  }

  void _completeTagging() {
    if (!mounted) return;

    final finalMentionDataList = _mediaMentionedMap.values
        .expand((list) => list)
        .toList(growable: false);

    unawaited(_popRoute<List<MentionData>>(finalMentionDataList));
  }
}
