import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ism_video_reel_player/ism_video_reel_player.dart' as isr;
import 'package:ism_video_reel_player_example/di/di.dart';
import 'package:ism_video_reel_player_example/presentation/presentation.dart';

class ProfileView extends StatefulWidget {
  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  @override
  void initState() {
    super.initState();
    InjectionUtils.getBloc<ProfileBloc>().add(InitializeProfileEvent());
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<ProfileBloc, ProfileState>(
      builder: (context, state) => ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              // Profile Tile
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text('View Profile'),
                onTap: () => ProfileScreen.show(context),
              ),
              const Divider(),

              // creat post Tile
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Create Post'),
                onTap: () {
                  _createPost(context);
                },
              ),
              const Divider(),

              if (isr.IsrVideoReelConfig.storyConfig != null) ...[
                ListTile(
                  leading: const Icon(Icons.auto_stories_outlined),
                  title: const Text('Add your story'),
                  subtitle: const Text('Photo or video'),
                  onTap: () => _addYourStory(context),
                ),
                const Divider(),
              ],

              ListTile(
                leading: const Icon(Icons.data_object),
                title: const Text('JSON post'),
                onTap: () => _showJsonPostSheet(context),
              ),
              const Divider(),

              // search Tile
              ListTile(
                leading: const Icon(Icons.search),
                title: const Text('Search'),
                onTap: () {
                  _search(context);
                },
              ),
              const Divider(),

              // scheduled post listing Tile
              ListTile(
                leading: const Icon(Icons.timelapse),
                title: const Text('Scheduled Posts'),
                onTap: () {
                  _schedulePostListing(context);
                },
              ),
              const Divider(),

              // Settings Tile
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('Settings'),
                onTap: () {},
              ),
              const Divider(),

              // Help Tile
              ListTile(
                leading: const Icon(Icons.help),
                title: const Text('Help & Support'),
                onTap: () {
                  // Handle help action
                },
              ),
              const Divider(),

              // Logout Tile
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title:
                    const Text('Logout', style: TextStyle(color: Colors.red)),
                onTap: () {
                  // Handle logout action
                  _showLogoutConfirmation(context);
                },
              ),
            ],
          ));

  void _createPost(BuildContext context) {
    isr.IsrAppNavigator.goToCreatePostView(context);
  }

  Future<void> _addYourStory(BuildContext context) async {
    final config = isr.IsrVideoReelConfig.storyConfig;
    if (config == null) return;
    final custom = config.storyCallbackConfig.navigateToCreateStory;
    if (custom != null) {
      await custom(context);
      return;
    }
    await isr.IsrAppNavigator.goToCreateStoryView(context);
  }

  void _schedulePostListing(BuildContext context) {
    isr.IsrAppNavigator.navigateToSchedulePostListing(context);
  }

  Future<void> _showJsonPostSheet(BuildContext context) async {
    final posts = await showModalBottomSheet<List<isr.TimeLineData>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _JsonPostSheet(),
    );
    if (!mounted || posts == null || posts.isEmpty) return;
    // Wait until the sheet route has left the tree before pushing reels.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await isr.IsrAppNavigator.navigateToReelsPlayer(
      context,
      postDataList: posts,
      startingPostIndex: 0,
      postSectionType: isr.PostSectionType.singlePost,
    );
  }

  void _search(BuildContext context) {
    isr.IsrAppNavigator.navigateToSearch(
      context,
      tabList: [
        isr.SearchTabType.account,
        isr.SearchTabType.posts,
        isr.SearchTabType.tags,
        isr.SearchTabType.places,
      ],

      // search: 'app',
      // tabList: [
      //   isr.SearchTabType.posts,
      //   isr.SearchTabType.account,
      // ],
    );
  }

  void _showLogoutConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
                foregroundColor: Colors.blue, backgroundColor: Colors.white),
            onPressed: () {
              Navigator.of(context).pop(); // Close the dialog
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
                foregroundColor: Colors.red, backgroundColor: Colors.white),
            onPressed: () {
              InjectionUtils.getBloc<ProfileBloc>().add(LogoutEvent());
              // Handle logout logic here
              Navigator.of(context).pop(); // Close the dialog
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}

class _JsonPostSheet extends StatefulWidget {
  const _JsonPostSheet();

  @override
  State<_JsonPostSheet> createState() => _JsonPostSheetState();
}

class _JsonPostSheetState extends State<_JsonPostSheet> {
  final _controller = TextEditingController();
  var _errorText = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _open() {
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) {
      setState(() => _errorText = 'Paste post JSON first');
      return;
    }

    List<isr.TimeLineData> posts;
    try {
      posts = _timelinePostsFromJson(trimmed);
    } catch (_) {
      setState(() => _errorText = 'That JSON could not be read');
      return;
    }

    if (posts.isEmpty) {
      setState(() => _errorText = 'No posts found in that JSON');
      return;
    }

    Navigator.of(context).pop(posts);
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxHeight =
        (screenHeight * 0.85 - viewInsets.bottom).clamp(180.0, screenHeight);

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'JSON post',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _controller,
                  minLines: 6,
                  maxLines: 8,
                  autofocus: true,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    hintText:
                        'Paste a post JSON array, a single post, or a timeline response',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                if (_errorText.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    _errorText,
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _open,
                  child: const Text('Open'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

List<isr.TimeLineData> _timelinePostsFromJson(String raw) {
  final decoded = jsonDecode(raw);
  return _postMaps(decoded)
      .map(isr.TimeLineData.fromMap)
      .where(
        (post) =>
            post.id?.trim().isNotEmpty == true ||
            post.media?.isNotEmpty == true,
      )
      .toList();
}

List<Map<String, dynamic>> _postMaps(dynamic decoded) {
  if (decoded is List) {
    return decoded
        .whereType<Map<dynamic, dynamic>>()
        .map(Map<String, dynamic>.from)
        .toList();
  }
  if (decoded is! Map) return const [];

  final map = Map<String, dynamic>.from(decoded);
  final data = map['data'];
  if (data is List || data is Map) {
    final nested = _postMaps(data);
    if (nested.isNotEmpty) return nested;
    if (data is Map) {
      final posts = Map<String, dynamic>.from(data)['posts'];
      if (posts != null) return _postMaps(posts);
    }
  }

  if (map.containsKey('posts')) return _postMaps(map['posts']);
  if (map.containsKey('id') ||
      map.containsKey('media') ||
      map.containsKey('user_id')) {
    return [map];
  }
  return const [];
}
