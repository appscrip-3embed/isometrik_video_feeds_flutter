import 'package:flutter/material.dart';

/// Scroll physics for vertical reels [PreloadPageView] feeds.
///
/// [PreloadPageView] wraps this with [PageScrollPhysics] when [pageSnapping] is
/// enabled. Platform parent matches Instagram-style feel: light overscroll on
/// iOS/macOS, clamped edges on Android.
///
/// Reuse anywhere a full-viewport vertical reel pager is built (not post-card
/// lists — those use [AlwaysScrollableScrollPhysics] in [PostFeedListWidget]).
ScrollPhysics reelsFeedScrollPhysics(BuildContext context) {
  final platform = Theme.of(context).platform;
  final parent =
      platform == TargetPlatform.iOS || platform == TargetPlatform.macOS
          ? const BouncingScrollPhysics()
          : const ClampingScrollPhysics();
  return parent;
}

/// One neighbor page on each side — package default; keeps the next reel built
/// during a swipe without warming video decoders (see [PostItemWidget]).
const int kReelsFeedPreloadPagesCount = 1;