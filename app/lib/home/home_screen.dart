import 'dart:async';

import 'package:app_db/app_db.dart';
import 'package:flutter/material.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../host/haptics.dart';
import '../feeds/feed_editor_screen.dart';
import '../feeds/feeds_screen.dart' show FeedsController;
import '../feeds/mark_read.dart';
import '../feeds/recent_searches.dart';
import '../feeds/search_dates.dart';
import '../feeds/timeline_search.dart';
import '../feeds/timeline_screen.dart';
import 'channel_info_screen.dart';
import 'connection_title.dart';
import 'channel_list.dart';
import 'unread_badge.dart';
import '../widgets/destructive_button.dart';
import '../widgets/empty_state.dart';
import '../widgets/menu_item.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/error_state.dart';
import '../app_name.dart';
import '../l10n/l10n.dart';

/// The main screen: the "Feeds" tab (list of feeds, with a button that makes one), one tab
/// per Telegram folder (its channels), and "All channels". Feeds and channels open as timelines of their own.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.db,
    required this.gateway,
    this.actions = const [],
    this.onOpenRules,
  });
  final AppDatabase db;
  final TelegramGateway gateway;

  /// App-bar actions (Rules, Settings).
  final List<Widget> actions;

  /// Opens the rules overview; the first-run card on the Feeds tab points there.
  final VoidCallback? onOpenRules;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final _feeds = FeedsController(db: widget.db, gateway: widget.gateway);
  StreamSubscription<PostEvent>? _posts;
  StreamSubscription<ReadState>? _reads;
  Timer? _reload;
  List<Channel> _channels = const [];

  /// The channels of the archive, known once the search over every channel was opened.
  List<Channel> _archived = const [];

  /// False until the first channel list arrived (or failed), so no tab says "No channels"
  /// while they are still loading.
  bool _channelsLoaded = false;
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

  /// The span of days the search is narrowed to, picked from what the typed words offer.
  DateSpan? _date;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // New posts change previews, order and unread counts of the channel lists.
    _posts = widget.gateway.postEvents.listen((e) {
      if (e is! PostAdded) return;
      // The row goes up at once with the post as its preview, as in the official app;
      // Telegram's own list, read a moment later, confirms the order and the counters.
      _bump(e.post);
      _reload?.cancel();
      _reload = Timer(const Duration(seconds: 3), _loadChannels);
    });
    // Reading, here or in the official app, moves the counters of the rows and of the
    // folder tabs at once.
    _reads = widget.gateway.readUpdates.listen(_onRead);
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
    _reads?.cancel();
    _tagSources?.cancel();
    _tagFeeds?.cancel();
    _feeds.dispose();
    _tabCtl
      ..removeListener(_onTabChanged)
      ..dispose();
    for (final c in _tabScroll.values) {
      c.dispose();
    }
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
    unawaited(_loadArchived());
  }

  /// The archived channels, which the search finds posts of as well: their names and
  /// photos for the results, and the channel itself to open one.
  Future<void> _loadArchived() async {
    try {
      final archived = await widget.gateway.archivedChannels();
      if (mounted) setState(() => _archived = archived);
    } on TelegramException {
      // Their results then show without a name and say why they do not open.
    }
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
      _date = null;
    });
  }

  /// A typed date was picked: it leaves the field and becomes the span that is searched,
  /// as in the official app.
  void _pickDate(DateSpan span) {
    _debounce?.cancel();
    _queryCtl.clear();
    setState(() => _date = span);
    unawaited(_startSearch(''));
  }

  void _clearDate() {
    setState(() => _date = null);
    unawaited(_startSearch(_queryCtl.text));
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
    // What the words may mean as a date is offered as they are typed.
    setState(() {});
  }

  Future<void> _startSearch(String value) async {
    final query = value.trim();
    // A kind of post on its own is a search too: "every file of my channels".
    final date = _date;
    if (query.isEmpty && _searchFilter == HistoryFilter.any && date == null) {
      setState(() => _session = null);
      return;
    }
    final session = GlobalSearchSession(
      gateway: widget.gateway,
      query: query,
      filter: _searchFilter,
      minDate: date?.minDate ?? 0,
      maxDate: date?.maxDate ?? 0,
      chatIds: [
        for (final c in [..._channels, ..._archived]) c.chatId,
      ],
    );
    setState(() => _session = session);
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
    final channel = {
      for (final c in [..._archived, ..._channels]) c.chatId: c,
    }[post.chatId];
    if (channel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.homeSearchChannelNotInList)),
      );
      return;
    }
    // Words are worth offering again once they led somewhere.
    if (session.query.trim().isNotEmpty) {
      unawaited(
        RecentSearches(widget.db).remember(session.query).then((words) {
          if (mounted) setState(() => _recent = words);
        }),
      );
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

  /// A channel got [post]: its row shows it and moves to the top of every list it is in,
  /// under the channels pinned there.
  void _bump(Post post) {
    final i = _channels.indexWhere((c) => c.chatId == post.chatId);
    if (i < 0 || !mounted) return;
    final c = _channels[i];
    // An older post that arrives late (a part of an album, an edit's echo) moves nothing.
    if (post.messageId <= c.lastMessageId && c.lastMessageId != 0) return;
    final channels = [..._channels]..removeAt(i);
    final at = c.pinnedLists.contains(0)
        ? i
        : channels.indexWhere((x) => !x.pinnedLists.contains(0));
    channels.insert(at < 0 ? channels.length : at, c.withNewestPost(post));
    final byId = {for (final x in channels) x.chatId: x};
    setState(() {
      _channels = channels;
      _folders = [
        for (final f in _folders)
          if (!f.channelIds.contains(post.chatId) ||
              c.pinnedLists.contains(f.id))
            f
          else
            ChatFolder(
              id: f.id,
              title: f.title,
              channelIds: () {
                final ids = [...f.channelIds]..remove(post.chatId);
                final first = ids.indexWhere(
                  (id) => !(byId[id]?.pinnedLists.contains(f.id) ?? false),
                );
                return ids..insert(first < 0 ? ids.length : first, post.chatId);
              }(),
            ),
      ];
    });
  }

  void _onRead(ReadState r) {
    final i = _channels.indexWhere((c) => c.chatId == r.chatId);
    if (i < 0 || !mounted) return;
    final c = _channels[i];
    if (c.unreadCount == r.unreadCount &&
        c.lastReadMessageId == r.lastReadMessageId) {
      return;
    }
    setState(() => _channels = [..._channels]..[i] = c.withRead(r));
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
      _channelsLoaded = true;
      _error = null;
    } on TelegramException catch (e) {
      if (!mounted) return;
      setState(() {
        _channelsLoaded = true;
        _error = e.message;
      });
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
        title: Text(
          initial == null
              ? context.l10n.feedsNewFeed
              : context.l10n.feedsRenameFeed,
        ),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: InputDecoration(labelText: context.l10n.feedsNameLabel),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) Navigator.pop(context, v.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.commonCancel),
          ),
          // Enabled once there is a name to give.
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: c,
            builder: (context, v, _) => FilledButton(
              onPressed: v.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(context, v.text.trim()),
              child: Text(
                initial == null
                    ? context.l10n.feedsCreate
                    : context.l10n.commonRename,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The + of the Feeds tab: an empty feed, or one that starts with a folder's channels.
  /// Without folders there is nothing to choose, and the name is asked for at once.
  Future<void> _newFeed() async {
    if (_folders.isEmpty) return _createFeed();
    final byId = {for (final c in _channels) c.chatId: c};
    final choice = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.add),
                title: Text(context.l10n.feedsEmptyFeed),
                subtitle: Text(context.l10n.feedsEmptyFeedSubtitle),
                onTap: () => Navigator.pop(context, 'empty'),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  context.l10n.feedsFromFolder,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(color: Theme.of(context).colorScheme.primary),
                ),
              ),
              for (final f in _folders)
                Builder(
                  builder: (context) {
                    final n = f.channelIds.where(byId.containsKey).length;
                    return ListTile(
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(f.title),
                      subtitle: Text(context.l10n.feedsChannelCount(n)),
                      onTap: () => Navigator.pop(context, f),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'empty':
        await _createFeed();
      case final ChatFolder folder:
        await _createFeedFromFolder(folder);
    }
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
      items: [
        menuItem('feed', Icons.rss_feed, context.l10n.homeFolderCreateFeed),
        menuItem('read', Icons.done_all, context.l10n.homeMarkAllAsRead),
      ],
    );
    if (choice == 'feed') await _createFeedFromFolder(folder);
    if (choice == 'read') await _markChannelsRead(folder.channelIds);
  }

  /// Sets Telegram's "marked as unread" on a channel, or takes it off; the row follows at
  /// once. True when Telegram took it.
  Future<bool> _markUnread(Channel channel, bool unread) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      await widget.gateway.markChannelUnread(channel.chatId, unread: unread);
    } on TelegramException catch (e) {
      showTelegramError(messenger, e, what: l10n.channelsMarkUnreadFailed);
      return false;
    }
    final i = _channels.indexWhere((c) => c.chatId == channel.chatId);
    if (i >= 0 && mounted) {
      setState(
        () =>
            _channels = [..._channels]
              ..[i] = _channels[i].withMarkedUnread(unread),
      );
    }
    return true;
  }

  /// Everything in these channels counts as read, here and in Telegram.
  Future<void> _markChannelsRead(Iterable<int> chatIds) async {
    final messenger = ScaffoldMessenger.of(context);
    final ids = chatIds.toSet();
    var moved = await MarkRead(
      db: widget.db,
      gateway: widget.gateway,
    ).channels(ids);
    // A channel that was only marked as unread has no post to read: the mark goes.
    for (final c in [..._channels]) {
      if (!ids.contains(c.chatId) || !c.isMarkedUnread) continue;
      final had = c.unreadCount > 0;
      if (await _markUnread(c, false) && !had) moved++;
    }
    if (!mounted) return;
    final l10n = context.l10n;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          moved == 0
              ? l10n.homeNothingToMarkRead
              : l10n.homeChannelsMarkedRead(moved),
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
    }
    if (!mounted) return;
    _tabCtl.animateTo(0);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.feedsCreatedFromFolder(folder.title, channels.length),
        ),
        action: SnackBarAction(
          label: context.l10n.commonOpen,
          onPressed: () => _openFeed(feed),
        ),
        // Flutter keeps a snack bar with an action up until it is swiped away.
        persist: false,
      ),
    );
  }

  Future<void> _editFeed(
    int feedId, {
    int tab = FeedEditorScreen.channelsTab,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => FeedEditorScreen(
        db: widget.db,
        gateway: widget.gateway,
        feedId: feedId,
        initialTab: tab,
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
    final l10n = context.l10n;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          moved == 0
              ? l10n.feedsNothingToMarkRead(f.name)
              : l10n.feedsMarkedRead(f.name),
        ),
      ),
    );
  }

  Future<void> _deleteFeed(Feed f) async {
    final rules = (await widget.db.allRules())
        .where((r) => r.feedId == f.id)
        .length;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.feedsDeleteTitle(f.name)),
        content: Text(context.l10n.feedsDeleteMessage(rules)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.commonCancel),
          ),
          DestructiveButton(
            onPressed: () => Navigator.pop(context, true),
            label: context.l10n.commonDelete,
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
    final l10n = context.l10n;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        at & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: [
        // One or the other, as in the official app: a channel with something unread, or
        // marked so, is marked read; a read one can be marked as unread.
        if (channel.unreadCount > 0 || channel.isMarkedUnread)
          menuItem('read', Icons.done_all, l10n.commonMarkAsRead)
        else
          menuItem(
            'unread',
            Icons.mark_chat_unread_outlined,
            l10n.channelsMarkAsUnread,
          ),
        menuItem('info', Icons.info_outline, l10n.channelsInfo),
        // Offered with no feeds too: it then makes the first one, which is exactly what
        // a reader who wants this channel in a feed needs.
        menuItem('add', Icons.playlist_add, l10n.channelsAddToFeed),
      ],
    );
    if (!mounted) return;
    switch (choice) {
      case 'read':
        await _markChannelsRead([channel.chatId]);
      case 'unread':
        await _markUnread(channel, true);
      case 'info':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ChannelInfoScreen(
              gateway: widget.gateway,
              channel: channel,
              onShowInChat: (post) => unawaited(
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
              ),
            ),
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
    final l10n = context.l10n;
    if (feeds.isEmpty) {
      // No feed to add it to: make one, which lands in its channel picker.
      await _createFeed();
      return;
    }
    // By id, not by name: two feeds may carry the same name.
    final inFeeds = {
      for (final f in await widget.db.feedsContaining(channel.chatId)) f.id,
    };
    if (!mounted) return;
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
                subtitle: inFeeds.contains(f.id)
                    ? Text(context.l10n.channelsAlreadyInFeed)
                    : null,
                enabled: !inFeeds.contains(f.id),
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
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.channelsAddedToFeed(channel.title, feed.name)),
        action: SnackBarAction(
          label: l10n.commonUndo,
          onPressed: () =>
              unawaited(widget.db.removeSource(feed.id, channel.chatId)),
        ),
      ),
    );
  }

  void _openChannel(Channel c) {
    // Opening a channel takes its "marked as unread" off, as in the official app.
    if (c.isMarkedUnread) unawaited(_markUnread(c, false));
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TimelineScreen(
            db: widget.db,
            gateway: widget.gateway,
            channel: c,
          ),
        ),
      ),
    );
  }

  /// The line under a feed's name: how many channels it has, and how many have news.
  /// Short enough to stand beside the counter, the menu and the drag handle on one line.
  static String _feedLine(AppLocalizations l10n, int fresh, int channels) =>
      fresh > 0
      ? l10n.feedsChannelsWithNews(fresh, channels)
      : l10n.feedsChannelCount(channels);

  /// The list of feeds: tap opens, drag reorders, the menu edits.
  Widget _feedsTab() => ListenableBuilder(
    listenable: _feeds,
    builder: (context, _) {
      final feeds = _feeds.feeds;
      if (!_feeds.loaded) {
        return const SkeletonList(leadingCircle: false);
      }
      return Column(
        children: [
          if (_feeds.error != null)
            MaterialBanner(
              content: Text(
                telegramErrorLine(
                  _feeds.error!,
                  what: context.l10n.feedsCountersRefreshFailed,
                  l10n: context.l10n,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _feeds.refreshChannels,
                  child: Text(context.l10n.commonRetry),
                ),
              ],
            ),
          if (feeds.isNotEmpty && widget.onOpenRules != null)
            RulesHint(db: widget.db, onOpenRules: widget.onOpenRules!),
          if (feeds.isEmpty)
            Expanded(
              child: EmptyState(
                icon: Icons.rss_feed,
                title: context.l10n.feedsEmptyTitle,
                message: context.l10n.feedsEmptyMessage,
                actionLabel: context.l10n.feedsEmptyAction,
                onAction: () => unawaited(_newFeed()),
                secondary: context.l10n.feedsEmptySecondary,
              ),
            )
          else
            Expanded(
              child: ReorderableListView.builder(
                // The + button floats over the end of the list; the last row stays reachable.
                padding: const EdgeInsets.only(bottom: 88),
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
                    // Always one line, so a row keeps its height as the feed is read.
                    subtitle: Text(
                      _feedLine(context.l10n, fresh, _feeds.channelsIn(f.id)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _openFeed(f),
                    // The counter on the right of the row, as the official app has it in
                    // its chat list: a long number never runs into the name.
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (unread > 0) UnreadBadge(unread),
                        PopupMenuButton<String>(
                          onSelected: (v) => switch (v) {
                            'channels' => _editFeed(f.id),
                            'rules' => _editFeed(
                              f.id,
                              tab: FeedEditorScreen.rulesTab,
                            ),
                            'rename' => _renameFeed(f),
                            'read' => _markFeedRead(f),
                            'delete' => _deleteFeed(f),
                            _ => null,
                          },
                          itemBuilder: (context) => [
                            menuItem(
                              'channels',
                              Icons.playlist_add,
                              context.l10n.feedsEditChannels,
                            ),
                            menuItem(
                              'rules',
                              Icons.notifications_active_outlined,
                              context.l10n.commonRules,
                            ),
                            menuItem(
                              'rename',
                              Icons.edit_outlined,
                              context.l10n.commonRename,
                            ),
                            menuItem(
                              'read',
                              Icons.done_all,
                              context.l10n.homeMarkAllAsRead,
                            ),
                            menuItem(
                              'delete',
                              Icons.delete_outline,
                              context.l10n.commonDelete,
                              danger: true,
                            ),
                          ],
                        ),
                        // Dragging a row by the list itself fights with its tap; the
                        // handle says where to take hold, as the official folder editor
                        // does.
                        ReorderableDragStartListener(
                          index: i,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Icon(Icons.drag_handle),
                          ),
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
    final byId = {
      for (final c in [..._archived, ..._channels]) c.chatId: c,
    };
    final l10n = context.l10n;
    final date = _date;
    // The days the typed words may mean, offered until one is picked.
    final spans = date != null
        ? const <DateSpan>[]
        : dateSpans(
            _queryCtl.text,
            today: l10n.postDayToday,
            yesterday: l10n.postDayYesterday,
            locale: l10n.localeName == 'en' ? 'en_US' : l10n.localeName,
          );
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _closeSearch),
        titleSpacing: 0,
        title: TextField(
          controller: _queryCtl,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: context.l10n.homeSearchHint,
            border: InputBorder.none,
          ),
          onChanged: _onQuery,
        ),
        actions: [
          if (_queryCtl.text.isNotEmpty)
            IconButton(
              tooltip: context.l10n.commonClear,
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
            leading: date == null
                ? null
                : InputChip(
                    avatar: const Icon(Icons.calendar_today, size: 16),
                    label: Text(date.label),
                    onDeleted: _clearDate,
                  ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (spans.isNotEmpty)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  for (final span in spans)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        avatar: const Icon(Icons.calendar_today, size: 16),
                        label: Text(span.label),
                        onPressed: () => _pickDate(span),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: SearchResults(
              results: session?.results ?? const [],
              gateway: widget.gateway,
              look: (chatId) => (
                title: byId[chatId]?.title ?? '',
                photo: byId[chatId]?.photo,
              ),
              onOpen: _openResult,
              onLoadMore: () => unawaited(_loadMoreResults()),
              query: _queryCtl.text,
              kind: _searchFilter,
              searched: session != null,
              loading: session?.loading ?? false,
              exhausted: session?.exhausted ?? false,
              total: session?.total ?? -1,
              error: session?.error,
              recent: _recent,
              onRecent: (words) {
                _queryCtl.text = words;
                unawaited(_startSearch(words));
              },
              onRemoveRecent: (words) async {
                final left = await RecentSearches(widget.db).remove(words);
                if (mounted) setState(() => _recent = left);
              },
              onClearRecent: () async {
                await RecentSearches(widget.db).clear();
                if (mounted) setState(() => _recent = const []);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// What a tab of channels counts: the channels with unread posts, by Telegram's own
  /// counter of each, as the official app's tabs count the chats with unread messages.
  /// [folder] is null for All channels.
  int _unreadChannels(ChatFolder? folder) {
    final inFolder = folder?.channelIds.toSet();
    var channels = 0;
    for (final c in _channels) {
      if (c.unreadCount <= 0 && !c.isMarkedUnread) continue;
      if (inFolder != null && !inFolder.contains(c.chatId)) continue;
      channels++;
    }
    return channels;
  }

  /// The scroll position of each tab's list, by the tab's name: a tap on the tab that is
  /// already open brings its list back to the top, as in the official app.
  final _tabScroll = <String, ScrollController>{};

  ScrollController _scrollOf(String tab) =>
      _tabScroll.putIfAbsent(tab, ScrollController.new);

  /// The name of the tab at [index]: Feeds, the folders, All channels.
  String _tabName(int index) => index == 0
      ? 'feeds'
      : index <= _folders.length
      ? 'folder:${_folders[index - 1].id}'
      : 'all';

  void _onTabTap(int index) {
    // The tab bar has moved its controller already: a tap that changes nothing was on
    // the open tab.
    if (_tabCtl.indexIsChanging) return;
    final scroll = _tabScroll[_tabName(index)];
    if (scroll == null || !scroll.hasClients) return;
    unawaited(
      scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      ),
    );
  }

  /// The list of a tab, scrolled by the tab's own controller.
  Widget _tabList(int index, Widget list) => PrimaryScrollController(
    controller: _scrollOf(_tabName(index)),
    child: list,
  );

  /// A long press on All channels: everything is marked read, as the official app offers
  /// on its tab of all chats.
  Future<void> _allChannelsMenu(Offset at) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        at & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: [menuItem('read', Icons.done_all, context.l10n.homeMarkAllAsRead)],
    );
    if (choice == 'read') {
      await _markChannelsRead([for (final c in _channels) c.chatId]);
    }
  }

  /// The channels the account archived in Telegram, behind a row of their own at the top of
  /// All channels, as the official app keeps its Archive above the chat list.
  Future<void> _openArchive() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final l10n = context.l10n;
    List<Channel> archived;
    try {
      archived = await widget.gateway.archivedChannels();
    } on TelegramException catch (e) {
      showTelegramError(
        messenger,
        e,
        what: l10n.channelsArchiveOpenFailed,
        onRetry: () => unawaited(_openArchive()),
      );
      return;
    }
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text(context.l10n.channelsArchive)),
          body: _LiveChannels(
            channels: archived,
            reads: widget.gateway.readUpdates,
            builder: (context, channels) => ChannelList(
              channels: channels,
              feedsByChat: _feedTags,
              gateway: widget.gateway,
              onOpen: _openChannel,
              onMenu: _channelMenu,
              emptyText: context.l10n.channelsArchiveEmpty,
            ),
          ),
        ),
      ),
    );
  }

  /// The label of a tab of channels: its name, and how many of its channels have unread
  /// posts.
  Widget _channelsTabLabel(String title, ChatFolder? folder) {
    final unread = _unreadChannels(folder);
    return _tabLabel(
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title),
          if (unread > 0)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: UnreadBadge(unread),
            ),
        ],
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
      loading: !_channelsLoaded,
      error: _error,
      emptyText: folder == null
          ? context.l10n.channelsEmptyAll
          : context.l10n.channelsEmptyFolder,
      // Only All channels carries it, as the official app carries its Archive.
      header: folder != null
          ? null
          : ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: Text(context.l10n.channelsArchive),
              subtitle: Text(context.l10n.channelsArchiveSubtitle),
              onTap: () => unawaited(_openArchive()),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_searchOpen) {
      // Back closes the search first, as in the official app.
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _closeSearch();
        },
        child: _searchScaffold(),
      );
    }
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
            tooltip: context.l10n.homeSearchPosts,
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
                  onTap: _onTabTap,
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
                                Text(context.l10n.homeTabFeeds),
                                if (fresh > 0)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 6),
                                    child: UnreadBadge(fresh),
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
                        onLongPressStart: (d) {
                          Haptics.longPress();
                          _folderMenu(f, d.globalPosition);
                        },
                        child: Tab(child: _channelsTabLabel(f.title, f)),
                      ),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onLongPressStart: (d) {
                        Haptics.longPress();
                        unawaited(_allChannelsMenu(d.globalPosition));
                      },
                      child: Tab(
                        child: _channelsTabLabel(
                          context.l10n.homeTabAllChannels,
                          null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      // Only the Feeds tab makes feeds, so the button belongs to it and to no other.
      floatingActionButton: _tabCtl.index == 0
          ? FloatingActionButton.extended(
              label: Text(context.l10n.feedsNewFeed),
              icon: const Icon(Icons.add),
              tooltip: context.l10n.feedsNewFeed,
              onPressed: () => unawaited(_newFeed()),
            )
          : null,
      body: TabBarView(
        controller: _tabCtl,
        children: [
          _tabList(0, _feedsTab()),
          for (final (i, f) in _folders.indexed)
            _tabList(i + 1, _channelsTab(f)),
          _tabList(_folders.length + 1, _channelsTab(null)),
        ],
      ),
    );
  }
}

/// Until the reader has rules, the Feeds tab says once where notifications come from:
/// this app repeats none of Telegram's own, so a feed without rules stays quiet.
class RulesHint extends StatelessWidget {
  const RulesHint({super.key, required this.db, required this.onOpenRules});
  final AppDatabase db;
  final VoidCallback onOpenRules;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<String?>(
      stream: db.watchSetting(SettingKeys.rulesHintDismissed),
      builder: (context, dismissed) {
        if (dismissed.data == 'true') return const SizedBox.shrink();
        return StreamBuilder<List<Rule>>(
          stream: db.watchRules(),
          builder: (context, rules) {
            if ((rules.data ?? const <Rule>[]).isNotEmpty) {
              return const SizedBox.shrink();
            }
            return Card(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              color: theme.colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            context.l10n.homeRulesHintTitle,
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        IconButton(
                          tooltip: context.l10n.homeRulesHintDismiss,
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => unawaited(
                            db.setSetting(
                              SettingKeys.rulesHintDismissed,
                              'true',
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      context.l10n.homeRulesHintBody,
                      style: theme.textTheme.bodyMedium,
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: onOpenRules,
                        child: Text(context.l10n.homeRulesHintAction),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// A list of channels whose counters follow the read state while it is on screen.
class _LiveChannels extends StatefulWidget {
  const _LiveChannels({
    required this.channels,
    required this.reads,
    required this.builder,
  });
  final List<Channel> channels;
  final Stream<ReadState> reads;
  final Widget Function(BuildContext, List<Channel>) builder;

  @override
  State<_LiveChannels> createState() => _LiveChannelsState();
}

class _LiveChannelsState extends State<_LiveChannels> {
  late List<Channel> _channels = widget.channels;
  late final StreamSubscription<ReadState> _sub = widget.reads.listen((r) {
    final i = _channels.indexWhere((c) => c.chatId == r.chatId);
    if (i < 0) return;
    setState(() => _channels = [..._channels]..[i] = _channels[i].withRead(r));
  });

  @override
  void initState() {
    super.initState();
    _sub; // starts listening
  }

  @override
  void dispose() {
    unawaited(_sub.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _channels);
}
