import 'dart:async';

import 'package:app_db/app_db.dart';
import 'package:flutter/material.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../feeds/feed_editor_screen.dart';
import '../feeds/feeds_screen.dart' show FeedsController;
import '../feeds/timeline_screen.dart';
import 'channel_list.dart';

/// The main screen: `+`, the "Feeds" tab (list of feeds), one tab per Telegram folder (its
/// channels), and "All channels". Feeds and channels open as timelines of their own.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.db,
    required this.gateway,
    this.actions = const [],
  });
  final AppDatabase db;
  final TelegramGateway gateway;

  /// App-bar actions (Rules, Settings).
  final List<Widget> actions;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final _feeds = FeedsController(db: widget.db, gateway: widget.gateway);
  StreamSubscription<PostEvent>? _posts;
  Timer? _reload;
  List<Channel> _channels = const [];
  List<ChatFolder> _folders = const [];
  String? _error;

  /// Feeds, the folders, All channels.
  late TabController _tabCtl = TabController(length: 2, vsync: this);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // New posts change previews, order and unread counts of the channel lists.
    _posts = widget.gateway.postEvents.listen((e) {
      if (e is! PostAdded) return;
      _reload?.cancel();
      _reload = Timer(const Duration(seconds: 3), _loadChannels);
    });
    unawaited(_loadChannels());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reload?.cancel();
    _posts?.cancel();
    _feeds.dispose();
    _tabCtl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Folders and read counters may have changed in the official app meanwhile.
    if (state == AppLifecycleState.resumed) unawaited(_loadChannels());
  }

  Future<void> _loadChannels() async {
    List<ChatFolder> folders;
    try {
      final channels = await widget.gateway.myChannels();
      folders = await widget.gateway.chatFolders();
      if (!mounted) return;
      _channels = channels;
      _error = null;
    } on TelegramException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
      return;
    }
    // The controller is replaced only when the folders changed; the selected tab stays.
    final before = [for (final f in _folders) f.id];
    final after = [for (final f in folders) f.id];
    if (before.join(',') != after.join(',')) {
      final old = _tabCtl;
      final selectedFolder = old.index >= 1 && old.index <= before.length
          ? before[old.index - 1]
          : null;
      final index = old.index == 0
          ? 0
          : selectedFolder == null
          ? after.length + 1
          : after.indexOf(selectedFolder) +
                1; // 0 (Feeds) when the folder is gone
      _tabCtl = TabController(
        length: after.length + 2,
        vsync: this,
        initialIndex: index,
      );
      // The old controller is still attached to this frame's widgets.
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    setState(() => _folders = folders);
  }

  Future<String?> _askName({String? initial}) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(initial == null ? 'New feed' : 'Rename feed'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text.trim()),
            child: Text(initial == null ? 'Create' : 'Rename'),
          ),
        ],
      ),
    );
  }

  Future<void> _createFeed() async {
    final name = await _askName();
    if (name == null || name.isEmpty) return;
    final feed = await widget.db.createFeed(name);
    if (!mounted) return;
    _tabCtl.animateTo(0);
    // Straight to its channels; an empty feed has nothing to show.
    await _editFeed(feed.id);
  }

  Future<void> _editFeed(int feedId) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => FeedEditorScreen(
        db: widget.db,
        gateway: widget.gateway,
        feedId: feedId,
      ),
    ),
  );

  Future<void> _renameFeed(Feed f) async {
    final name = await _askName(initial: f.name);
    if (name != null && name.isNotEmpty && name != f.name) {
      await widget.db.renameFeed(f.id, name);
    }
  }

  Future<void> _deleteFeed(Feed f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${f.name}"?'),
        content: const Text(
          'The feed and its read positions are removed. Channels stay joined in Telegram.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok ?? false) await widget.db.deleteFeed(f.id);
  }

  void _openFeed(Feed f) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          TimelineScreen(db: widget.db, gateway: widget.gateway, feed: f),
    ),
  );

  void _openChannel(Channel c) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          TimelineScreen(db: widget.db, gateway: widget.gateway, channel: c),
    ),
  );

  /// The list of feeds: tap opens, drag reorders, the menu edits.
  Widget _feedsTab() => ListenableBuilder(
    listenable: _feeds,
    builder: (context, _) {
      final feeds = _feeds.feeds;
      if (feeds.isEmpty) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'No feeds yet. Tap + to create one and add the channels you want to read together.',
              textAlign: TextAlign.center,
            ),
          ),
        );
      }
      return Column(
        children: [
          if (_feeds.error != null)
            MaterialBanner(
              content: Text('Telegram: ${_feeds.error}'),
              actions: [
                TextButton(
                  onPressed: _feeds.refreshChannels,
                  child: const Text('Retry'),
                ),
              ],
            ),
          Expanded(
            child: ReorderableListView.builder(
              itemCount: feeds.length,
              onReorderItem: (from, to) {
                final ids = feeds.map((f) => f.id).toList();
                final id = ids.removeAt(from);
                ids.insert(to, id);
                widget.db.reorderFeeds(ids);
              },
              itemBuilder: (context, i) {
                final f = feeds[i];
                final fresh = _feeds.newSourcesOf(f.id);
                return ListTile(
                  key: ValueKey(f.id),
                  title: Text(f.name),
                  leading: fresh > 0
                      ? Badge.count(
                          count: fresh,
                          child: const Icon(Icons.rss_feed),
                        )
                      : const Icon(Icons.rss_feed),
                  subtitle: fresh > 0
                      ? Text(
                          '$fresh channel${fresh == 1 ? '' : 's'} with new posts',
                        )
                      : null,
                  onTap: () => _openFeed(f),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) => switch (v) {
                      'channels' => _editFeed(f.id),
                      'rename' => _renameFeed(f),
                      'delete' => _deleteFeed(f),
                      _ => null,
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'channels', child: Text('Channels')),
                      PopupMenuItem(value: 'rename', child: Text('Rename')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      );
    },
  );

  Widget _channelsTab(ChatFolder? folder) {
    final byId = {for (final c in _channels) c.chatId: c};
    return ChannelList(
      key: ValueKey(folder == null ? 'all' : 'folder:${folder.id}'),
      channels: folder == null
          ? _channels
          : [for (final id in folder.channelIds) ?byId[id]],
      gateway: widget.gateway,
      onOpen: _openChannel,
      searchable: folder == null,
      onRefresh: _loadChannels,
      emptyText: folder == null
          ? (_error == null
                ? 'No channels yet. Join channels in Telegram and they show up here.'
                : 'Telegram: $_error')
          : 'No channels in this folder.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('telegram-feed'),
        actions: widget.actions,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(kTextTabBarHeight),
          child: Row(
            children: [
              IconButton(
                tooltip: 'New feed',
                icon: const Icon(Icons.add),
                onPressed: _createFeed,
              ),
              Expanded(
                child: TabBar(
                  controller: _tabCtl,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    ListenableBuilder(
                      listenable: _feeds,
                      builder: (context, _) {
                        final fresh = _feeds.feeds
                            .where((f) => _feeds.newSourcesOf(f.id) > 0)
                            .length;
                        return Tab(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Feeds'),
                              if (fresh > 0)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Badge.count(count: fresh),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                    for (final f in _folders) Tab(text: f.title),
                    const Tab(text: 'All channels'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabCtl,
        children: [
          _feedsTab(),
          for (final f in _folders) _channelsTab(f),
          _channelsTab(null),
        ],
      ),
    );
  }
}
