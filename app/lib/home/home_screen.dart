import 'dart:async';

import 'package:app_db/app_db.dart';
import 'package:flutter/material.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../feeds/feed_editor_screen.dart';
import '../feeds/feeds_screen.dart' show FeedsController;
import '../feeds/mark_read.dart';
import '../feeds/recent_searches.dart';
import '../feeds/timeline_search.dart';
import '../feeds/timeline_screen.dart';
import 'channel_info_screen.dart';
import 'connection_title.dart';
import 'channel_list.dart';
import '../app_name.dart';

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
  Map<int, List<String>> _feedTags = const {};
  StreamSubscription<void>? _tagSources;
  StreamSubscription<void>? _tagFeeds;
  String? _error;

  /// Feeds, the folders, All channels.
  late TabController _tabCtl = TabController(length: 2, vsync: this);

  /// Search over every channel (H-25): open, the query, the running search.
  bool _searchOpen = false;
  final _queryCtl = TextEditingController();
  Timer? _debounce;
  GlobalSearchSession? _session;
  HistoryFilter _searchFilter = HistoryFilter.any;
  List<String> _recent = const [];

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
    // The tags say which feeds a channel is in: they change with the feeds and with their
    // sources, which the feeds screen and the editor write.
    _tabCtl.addListener(_onTabChanged);
    _tagSources = widget.db.watchSourceChanges().listen((_) => _loadTags());
    _tagFeeds = widget.db.watchFeeds().listen((_) => _loadTags());
    unawaited(_loadChannels());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    _queryCtl.dispose();
    _reload?.cancel();
    _posts?.cancel();
    _tagSources?.cancel();
    _tagFeeds?.cancel();
    _feeds.dispose();
    _tabCtl
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Folders and read counters may have changed in the official app meanwhile.
    if (state == AppLifecycleState.resumed) unawaited(_loadChannels());
  }

  void _openSearch() {
    setState(() => _searchOpen = true);
    unawaited(_loadRecent());
  }

  Future<void> _loadRecent() async {
    final words = await RecentSearches(widget.db).load();
    if (mounted) setState(() => _recent = words);
  }

  void _closeSearch() {
    _debounce?.cancel();
    _queryCtl.clear();
    setState(() {
      _searchOpen = false;
      _session = null;
      _searchFilter = HistoryFilter.any;
    });
  }

  void _setSearchFilter(HistoryFilter filter) {
    if (filter == _searchFilter) return;
    setState(() => _searchFilter = filter);
    unawaited(_startSearch(_queryCtl.text));
  }

  void _onQuery(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(_startSearch(value)),
    );
  }

  Future<void> _startSearch(String value) async {
    final query = value.trim();
    // A kind of post on its own is a search too: "every file of my channels".
    if (query.isEmpty && _searchFilter == HistoryFilter.any) {
      setState(() => _session = null);
      return;
    }
    final session = GlobalSearchSession(
      gateway: widget.gateway,
      query: query,
      filter: _searchFilter,
    );
    setState(() => _session = session);
    if (query.isNotEmpty) {
      final words = await RecentSearches(widget.db).remember(query);
      if (mounted) setState(() => _recent = words);
    }
    await session.loadMore();
    if (mounted && identical(_session, session)) setState(() {});
  }

  Future<void> _loadMoreResults() async {
    final session = _session;
    if (session == null) return;
    final changed = await session.loadMore();
    if (changed && mounted && identical(_session, session)) setState(() {});
  }

  /// A result opens the channel it came from, at that post.
  void _openResult(int index) {
    final session = _session;
    if (session == null || index >= session.results.length) return;
    final post = session.results[index];
    final channel = {for (final c in _channels) c.chatId: c}[post.chatId];
    if (channel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That channel is not in your list.')),
      );
      return;
    }
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TimelineScreen(
            db: widget.db,
            gateway: widget.gateway,
            channel: channel,
            focusChatId: post.chatId,
            focusMessageId: post.messageId,
          ),
        ),
      ),
    );
  }

  /// The floating button belongs to the Feeds tab, so a change of tab rebuilds it.
  void _onTabChanged() {
    if (mounted && !_tabCtl.indexIsChanging) setState(() {});
  }

  Future<void> _loadTags() async {
    final tags = await widget.db.feedNamesByChat();
    if (mounted) setState(() => _feedTags = tags);
  }

  Future<void> _loadChannels() async {
    List<ChatFolder> folders;
    try {
      // Folders first: they tell the gateway which chat lists hold channels, and a channel
      // joined through a folder invite link is in no other list.
      folders = await widget.gateway.chatFolders();
      final channels = await widget.gateway.myChannels();
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
      )..addListener(_onTabChanged);
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

  /// Tabs carry their own padding, because the bar's `labelPadding` is set to zero: a
  /// folder tab's long press then covers the whole tab instead of its label alone. A
  /// folder named with one emoji is a few pixels wide, and its menu was next to
  /// impossible to call; [_tabMinWidth] keeps such a tab a comfortable target.
  static const _tabLabelPadding = EdgeInsets.symmetric(horizontal: 16);
  static const _tabMinWidth = 72.0;

  Widget _tabLabel(Widget child) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: _tabMinWidth),
    child: Padding(
      padding: _tabLabelPadding,
      child: Center(widthFactor: 1, child: child),
    ),
  );

  /// Long press on a folder tab: a feed with the folder's name and the channels it has now.
  /// A one-time copy; afterwards the feed is edited like any other.
  Future<void> _folderMenu(ChatFolder folder, Offset at) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        at & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(
          value: 'feed',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.rss_feed),
            title: Text('Create feed from folder'),
          ),
        ),
        PopupMenuItem(
          value: 'read',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.done_all),
            title: Text('Mark all read'),
          ),
        ),
      ],
    );
    if (choice == 'feed') await _createFeedFromFolder(folder);
    if (choice == 'read') await _markChannelsRead(folder.channelIds);
  }

  /// Everything in these channels counts as read, here and in Telegram.
  Future<void> _markChannelsRead(Iterable<int> chatIds) async {
    final messenger = ScaffoldMessenger.of(context);
    final moved = await MarkRead(
      db: widget.db,
      gateway: widget.gateway,
    ).channels(chatIds);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          moved == 0
              ? 'Nothing to mark read.'
              : '$moved channel${moved == 1 ? '' : 's'} marked read.',
        ),
      ),
    );
    await _loadChannels();
  }

  Future<void> _createFeedFromFolder(ChatFolder folder) async {
    final byId = {for (final c in _channels) c.chatId: c};
    final channels = [for (final id in folder.channelIds) ?byId[id]];
    final feed = await widget.db.createFeed(folder.title);
    for (final c in channels) {
      await widget.db.addSource(
        feed.id,
        c.chatId,
        title: c.title,
        username: c.username,
      );
      // As in the feed editor: the feed starts at Telegram's own read position.
      if (c.lastReadMessageId > 0) {
        await widget.db.markRead(feed.id, c.chatId, c.lastReadMessageId);
      }
    }
    if (!mounted) return;
    _tabCtl.animateTo(0);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Feed "${folder.title}" created with ${channels.length} '
          'channel${channels.length == 1 ? '' : 's'}.',
        ),
        action: SnackBarAction(label: 'Open', onPressed: () => _openFeed(feed)),
        // Flutter keeps a snack bar with an action up until it is swiped away.
        persist: false,
      ),
    );
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

  /// Every channel of the feed up to its newest post, as the official app's action does.
  Future<void> _markFeedRead(Feed f) async {
    final messenger = ScaffoldMessenger.of(context);
    final moved = await MarkRead(
      db: widget.db,
      gateway: widget.gateway,
    ).feed(f.id);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          moved == 0
              ? 'Nothing to mark read in "${f.name}".'
              : '"${f.name}" marked read.',
        ),
      ),
    );
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

  /// Long press on a channel row, as in the official app: mark it read, open its info, or
  /// put it into one of the reader's feeds.
  Future<void> _channelMenu(Channel channel, Offset at) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final feeds = await widget.db.allFeeds();
    if (!mounted) return;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        at & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem(
          value: 'read',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.done_all),
            title: Text('Mark all read'),
          ),
        ),
        const PopupMenuItem(
          value: 'info',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.info_outline),
            title: Text('Channel info'),
          ),
        ),
        if (feeds.isNotEmpty)
          const PopupMenuItem(
            value: 'add',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.playlist_add),
              title: Text('Add to a feed'),
            ),
          ),
      ],
    );
    if (!mounted) return;
    switch (choice) {
      case 'read':
        await _markChannelsRead([channel.chatId]);
      case 'info':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                ChannelInfoScreen(gateway: widget.gateway, channel: channel),
          ),
        );
      case 'add':
        await _addToFeed(channel, feeds);
    }
  }

  /// Picks one of the reader's feeds and puts the channel in it, starting at Telegram's own
  /// read position as the feed editor does.
  Future<void> _addToFeed(Channel channel, List<Feed> feeds) async {
    final messenger = ScaffoldMessenger.of(context);
    final inFeeds = (_feedTags[channel.chatId] ?? const []).toSet();
    final feed = await showModalBottomSheet<Feed>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final f in feeds)
              ListTile(
                leading: const Icon(Icons.rss_feed),
                title: Text(f.name),
                subtitle: inFeeds.contains(f.name)
                    ? const Text('Already in this feed')
                    : null,
                enabled: !inFeeds.contains(f.name),
                onTap: () => Navigator.pop(context, f),
              ),
          ],
        ),
      ),
    );
    if (feed == null) return;
    await widget.db.addSource(
      feed.id,
      channel.chatId,
      title: channel.title,
      username: channel.username,
    );
    if (channel.lastReadMessageId > 0) {
      await widget.db.markRead(
        feed.id,
        channel.chatId,
        channel.lastReadMessageId,
      );
    }
    messenger.showSnackBar(
      SnackBar(content: Text('${channel.title} added to "${feed.name}".')),
    );
  }

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
                // Posts or channels, as the Badge counter switch says (J-1); the line
                // under the name always names the channels.
                final unread = _feeds.unreadOf(f.id);
                final fresh = _feeds.unreadChannelsOf(f.id);
                return ListTile(
                  key: ValueKey(f.id),
                  title: Text(f.name),
                  leading: const Icon(Icons.rss_feed),
                  subtitle: fresh > 0
                      ? Text(
                          '$fresh channel${fresh == 1 ? '' : 's'} with new posts',
                        )
                      : null,
                  onTap: () => _openFeed(f),
                  // The counter on the right of the row, as the official app has it in
                  // its chat list: a long number never runs into the name.
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (unread > 0) Badge.count(count: unread),
                      PopupMenuButton<String>(
                        onSelected: (v) => switch (v) {
                          'channels' => _editFeed(f.id),
                          'rename' => _renameFeed(f),
                          'read' => _markFeedRead(f),
                          'delete' => _deleteFeed(f),
                          _ => null,
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'channels',
                            child: Text('Channels'),
                          ),
                          PopupMenuItem(value: 'rename', child: Text('Rename')),
                          PopupMenuItem(
                            value: 'read',
                            child: Text('Mark all read'),
                          ),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
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

  /// The search over every channel: the bar takes the app bar, the results the screen.
  Widget _searchScaffold() {
    final session = _session;
    final byId = {for (final c in _channels) c.chatId: c};
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _closeSearch),
        titleSpacing: 0,
        title: TextField(
          controller: _queryCtl,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Search all channels',
            border: InputBorder.none,
          ),
          onChanged: _onQuery,
        ),
        actions: [
          if (_queryCtl.text.isNotEmpty)
            IconButton(
              tooltip: 'Clear',
              icon: const Icon(Icons.close),
              onPressed: () {
                _queryCtl.clear();
                _onQuery('');
              },
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: SearchFilterChips(
            filter: _searchFilter,
            onChanged: _setSearchFilter,
          ),
        ),
      ),
      body: SearchResults(
        results: session?.results ?? const [],
        gateway: widget.gateway,
        look: (chatId) =>
            (title: byId[chatId]?.title ?? '', photo: byId[chatId]?.photo),
        onOpen: _openResult,
        onLoadMore: () => unawaited(_loadMoreResults()),
        query: _queryCtl.text,
        loading: session?.loading ?? false,
        exhausted: session?.exhausted ?? false,
        error: session?.error,
        recent: _recent,
        onRecent: (words) {
          _queryCtl.text = words;
          unawaited(_startSearch(words));
        },
        onClearRecent: () async {
          await RecentSearches(widget.db).clear();
          if (mounted) setState(() => _recent = const []);
        },
      ),
    );
  }

  /// What the folder's tab counts, from Telegram's own counter of each channel: its
  /// unread posts together, or the channels that have any, as the Badge counter switch
  /// says (J-1) — the two ways the official app counts on its tabs.
  int _unreadInFolder(ChatFolder folder) {
    final inFolder = folder.channelIds.toSet();
    var channels = 0;
    var posts = 0;
    for (final c in _channels) {
      if (c.unreadCount <= 0 || !inFolder.contains(c.chatId)) continue;
      channels++;
      posts += c.unreadCount;
    }
    return _feeds.countPosts ? posts : channels;
  }

  /// The channels the account archived in Telegram, behind a row of their own at the top of
  /// All channels, as the official app keeps its Archive above the chat list.
  Future<void> _openArchive() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    List<Channel> archived;
    try {
      archived = await widget.gateway.archivedChannels();
    } on TelegramException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Telegram: ${e.message}')));
      return;
    }
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Archive')),
          body: ChannelList(
            channels: archived,
            feedsByChat: _feedTags,
            gateway: widget.gateway,
            onOpen: _openChannel,
            onMenu: _channelMenu,
            emptyText: 'No archived channels.',
          ),
        ),
      ),
    );
  }

  Widget _channelsTab(ChatFolder? folder) {
    final byId = {for (final c in _channels) c.chatId: c};
    return ChannelList(
      key: ValueKey(folder == null ? 'all' : 'folder:${folder.id}'),
      feedsByChat: _feedTags,
      channels: folder == null
          ? _channels
          : [for (final id in folder.channelIds) ?byId[id]],
      gateway: widget.gateway,
      onOpen: _openChannel,
      onMenu: _channelMenu,
      searchable: folder == null,
      onRefresh: _loadChannels,
      emptyText: folder == null
          ? (_error == null
                ? 'No channels yet. Join channels in Telegram and they show up here.'
                : 'Telegram: $_error')
          : 'No channels in this folder.',
      // Only All channels carries it, as the official app carries its Archive.
      header: folder != null
          ? null
          : ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: const Text('Archive'),
              subtitle: const Text('Channels you archived in Telegram'),
              onTap: () => unawaited(_openArchive()),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_searchOpen) return _searchScaffold();
    return Scaffold(
      appBar: AppBar(
        title: ConnectionTitle(
          gateway: widget.gateway,
          // The whole name, made smaller on a narrow phone rather than cut off.
          title: const FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(appName),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Search posts',
            icon: const Icon(Icons.search),
            onPressed: _openSearch,
          ),
          ...widget.actions,
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(kTextTabBarHeight),
          // The tab bar carries tabs only; the new feed button belongs to the Feeds tab
          // itself (H-36).
          child: Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: _tabCtl,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelPadding: EdgeInsets.zero,
                  tabs: [
                    ListenableBuilder(
                      listenable: _feeds,
                      builder: (context, _) {
                        final fresh = _feeds.unreadOnTab;
                        return Tab(
                          child: _tabLabel(
                            Row(
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
                          ),
                        );
                      },
                    ),
                    for (final f in _folders)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onLongPressStart: (d) =>
                            _folderMenu(f, d.globalPosition),
                        child: Tab(
                          // The switch of the Badge counter lives in the feeds' controller.
                          child: ListenableBuilder(
                            listenable: _feeds,
                            builder: (context, _) {
                              final unread = _unreadInFolder(f);
                              return _tabLabel(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(f.title),
                                    if (unread > 0)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 6),
                                        child: Badge.count(count: unread),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    Tab(child: _tabLabel(const Text('All channels'))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      // Only the Feeds tab makes feeds, so the button belongs to it and to no other.
      floatingActionButton: _tabCtl.index == 0
          ? FloatingActionButton(
              tooltip: 'New feed',
              onPressed: _createFeed,
              child: const Icon(Icons.add),
            )
          : null,
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
