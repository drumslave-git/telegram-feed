import 'dart:async';

import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:share_plus/share_plus.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../home/channel_info_screen.dart';
import '../settings/settings_screen.dart' show showAutoplaySettings;
import 'feed_editor_screen.dart';
import 'open_links.dart';
import 'post_card.dart';
import 'read_marker.dart';
import 'thread_screen.dart';
import 'timeline_search.dart';

export 'post_card.dart' show PostCard;

/// A timeline with its own app bar: a feed opened from a notification, or one channel
/// opened from a folder tab or the channel list. The app bar also carries the search of
/// ARCHITECTURE.md 5.10: the magnifier turns it into a search field, the results cover the
/// timeline, and a tapped result opens the timeline at that post.
class TimelineScreen extends StatefulWidget {
  const TimelineScreen({
    super.key,
    required this.db,
    required this.gateway,
    this.feed,
    this.channel,
    this.focusChatId,
    this.focusMessageId,
    this.share = TimelineView.shareWithSystemSheet,
  }) : assert((feed == null) != (channel == null));
  final AppDatabase db;
  final TelegramGateway gateway;
  final Feed? feed;
  final Channel? channel;
  final int? focusChatId;
  final int? focusMessageId;
  final Future<void> Function(String text, {required String subject}) share;

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  final _view = GlobalKey<TimelineViewState>();
  final _queryCtl = TextEditingController();
  final _queryFocus = FocusNode();
  Timer? _debounce;

  /// The running search; null until the first query.
  SearchSession? _session;
  bool _searchOpen = false;

  /// True while the results cover the timeline; false once a result was opened.
  bool _listOpen = false;

  /// Result the timeline stands on, -1 before one was opened.
  int _current = -1;
  bool _jumping = false;

  /// What the timeline reads, handed up by [TimelineView] as it loads.
  TimelineSources _sources = (
    chatIds: const [],
    filter: FeedFilter.none,
    titles: const {},
    photos: const {},
  );

  @override
  void dispose() {
    _debounce?.cancel();
    _queryCtl.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  void _onSources(TimelineSources sources) {
    if (!mounted) return;
    setState(() => _sources = sources);
    // A search that started before the sources were known covers them now.
    final session = _session;
    if (session != null && session.chatIds.length != sources.chatIds.length) {
      unawaited(_startSearch(session.query));
    }
  }

  void _openSearch() => setState(() {
    _searchOpen = true;
    _listOpen = true;
  });

  void _closeSearch() {
    _debounce?.cancel();
    _queryCtl.clear();
    setState(() {
      _searchOpen = false;
      _listOpen = false;
      _session = null;
      _current = -1;
    });
  }

  void _onQuery(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(_startSearch(value)),
    );
    setState(() {
      _listOpen = true;
      _current = -1;
    });
  }

  Future<void> _startSearch(String value) async {
    final query = value.trim();
    if (query.isEmpty) {
      setState(() => _session = null);
      return;
    }
    final session = SearchSession(
      gateway: widget.gateway,
      chatIds: _sources.chatIds,
      query: query,
      feedFilter: _sources.filter,
    );
    setState(() {
      _session = session;
      _current = -1;
    });
    await session.loadMore();
    if (mounted && identical(_session, session)) setState(() {});
  }

  Future<void> _loadMoreResults() async {
    final session = _session;
    if (session == null) return;
    final changed = await session.loadMore();
    if (changed && mounted && identical(_session, session)) setState(() {});
  }

  /// Opens the result at [index]: the list makes way and the timeline is rebuilt around
  /// that post, as the official app does when a result is tapped.
  Future<void> _openResult(int index) async {
    final session = _session;
    if (session == null || _jumping || index < 0) return;
    setState(() => _jumping = true);
    try {
      if (!await session.ensure(index)) return;
      if (!mounted || !identical(_session, session)) return;
      final post = session.results[index];
      _queryFocus.unfocus();
      setState(() {
        _current = index;
        _listOpen = false;
      });
      await _view.currentState?.jumpToPost(
        chatId: post.chatId,
        messageId: post.messageId,
        date: post.date,
      );
    } finally {
      if (mounted) setState(() => _jumping = false);
    }
  }

  void _openFeedEditor() => unawaited(
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FeedEditorScreen(
          db: widget.db,
          gateway: widget.gateway,
          feedId: widget.feed!.id,
        ),
      ),
    ),
  );

  PreferredSizeWidget _appBar(BuildContext context) {
    final theme = Theme.of(context);
    if (_searchOpen) {
      return AppBar(
        leading: BackButton(onPressed: _closeSearch),
        titleSpacing: 0,
        title: TextField(
          controller: _queryCtl,
          focusNode: _queryFocus,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Search posts',
            border: InputBorder.none,
          ),
          onChanged: _onQuery,
          onTap: () => setState(() => _listOpen = true),
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
          IconButton(
            tooltip: 'Jump to date',
            icon: const Icon(Icons.calendar_month),
            onPressed: () {
              // The calendar takes over from the search, as in the official app.
              final view = _view.currentState;
              _closeSearch();
              unawaited(view?.pickDate());
            },
          ),
        ],
      );
    }
    final channel = widget.channel;
    return AppBar(
      title: channel == null
          // The feed's editor is its info screen: its channels and their shared media.
          ? InkWell(
              onTap: _openFeedEditor,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(widget.feed!.name),
              ),
            )
          // A channel's title leads to its info, as in the official app.
          : InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ChannelInfoScreen(
                    gateway: widget.gateway,
                    channel: channel,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(channel.title, style: theme.textTheme.titleLarge),
                  if (channel.memberCount > 0)
                    Text(
                      '${formatCount(channel.memberCount)} subscribers',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
      actions: [
        IconButton(
          tooltip: 'Search',
          icon: const Icon(Icons.search),
          onPressed: _openSearch,
        ),
        if (widget.feed != null)
          IconButton(
            tooltip: 'Edit feed',
            icon: const Icon(Icons.tune),
            onPressed: _openFeedEditor,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return Scaffold(
      appBar: _appBar(context),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                TimelineView(
                  key: _view,
                  db: widget.db,
                  gateway: widget.gateway,
                  feed: widget.feed,
                  channel: widget.channel,
                  focusChatId: widget.focusChatId,
                  focusMessageId: widget.focusMessageId,
                  share: widget.share,
                  onSources: _onSources,
                ),
                if (_searchOpen && _listOpen)
                  Positioned.fill(
                    child: Material(
                      color: Theme.of(context).colorScheme.surface,
                      child: SearchResults(
                        results: session?.results ?? const [],
                        gateway: widget.gateway,
                        look: (chatId) => (
                          title: _sources.titles[chatId] ?? '',
                          photo: _sources.photos[chatId],
                        ),
                        onOpen: (i) => unawaited(_openResult(i)),
                        onLoadMore: () => unawaited(_loadMoreResults()),
                        query: _queryCtl.text,
                        loading: session?.loading ?? false,
                        exhausted: session?.exhausted ?? false,
                        error: session?.error,
                        current: _current,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_searchOpen && !_listOpen && session != null)
            SearchStepper(
              current: _current,
              total: session.total,
              loading: _jumping,
              onOlder:
                  _jumping ||
                      (session.exhausted &&
                          _current + 1 >= session.results.length)
                  ? null
                  : () => unawaited(_openResult(_current + 1)),
              onNewer: _jumping || _current <= 0
                  ? null
                  : () => unawaited(_openResult(_current - 1)),
            ),
        ],
      ),
    );
  }
}

/// The channels a timeline reads, with what the search rows need to draw them.
typedef TimelineSources = ({
  List<int> chatIds,
  FeedFilter filter,
  Map<int, String> titles,
  Map<int, FileRef?> photos,
});

/// The merged timeline of one feed, or the posts of one channel (ARCHITECTURE.md 5.3).
/// Has no app bar of its own; [TimelineScreen] supplies one.
class TimelineView extends StatefulWidget {
  const TimelineView({
    super.key,
    required this.db,
    required this.gateway,
    this.feed,
    this.channel,
    this.focusChatId,
    this.focusMessageId,
    this.share = shareWithSystemSheet,
    this.onSources,
  }) : assert((feed == null) != (channel == null));
  final AppDatabase db;
  final TelegramGateway gateway;

  /// Reports the channels, the filter and the photos as they are loaded, for the search.
  final ValueChanged<TimelineSources>? onSources;

  /// A feed of ours: sources and read marks come from the database.
  final Feed? feed;

  /// One channel: its read position is Telegram's own.
  final Channel? channel;

  /// Opens the system share sheet with [text] (tests inject a recorder).
  final Future<void> Function(String text, {required String subject}) share;

  static Future<void> shareWithSystemSheet(
    String text, {
    required String subject,
  }) async {
    await SharePlus.instance.share(ShareParams(text: text, subject: subject));
  }

  /// Post to open at (notification tap). Loads up to a few pages to find it.
  final int? focusChatId;
  final int? focusMessageId;

  @override
  State<TimelineView> createState() => TimelineViewState();
}

/// Where the user was in a feed; kept in memory so coming back within the session lands on
/// the same post, like reopening a chat in Telegram.
class _Anchor {
  const _Anchor(this.chatId, this.rowId, this.edge);
  final int chatId;
  final int rowId;

  /// `itemLeadingEdge` of the row: its bottom, as a fraction of the viewport from the bottom.
  final double edge;
}

class TimelineViewState extends State<TimelineView> {
  /// Remembered positions per feed id (positive) or channel chat id (negative). They hang
  /// off the database object, which goes away with the session.
  static final _memory = Expando<Map<int, _Anchor>>();

  /// Opening loads down to the read marks, but never more than this many rows.
  static const _openCap = 300;

  final _scrollCtl = ItemScrollController();
  final _positions = ItemPositionsListener.create();
  late final ReadMarker _marker = ReadMarker(
    db: widget.db,
    gateway: widget.gateway,
    feedId: widget.feed?.id,
  );

  int get _memoryKey => widget.feed?.id ?? widget.channel!.chatId;
  FeedTimeline? _timeline;
  StreamSubscription<PostEvent>? _events;
  StreamSubscription<List<WatchedChannel>>? _sources;
  StreamSubscription<List<FeedReadMark>>? _marksSub;
  StreamSubscription<Feed?>? _feedSub;
  FeedFilter _filter = FeedFilter.none;
  List<({int chatId, String title, String? username})> _sourceRows = const [];
  Map<int, String> _titles = const {};
  Map<int, String?> _usernames = const {};

  /// Channel photos for the avatars beside the posts.
  Map<int, FileRef?> _photos = const {};

  /// Every channel the account follows, by chat id: the forwarded-from line opens one.
  Map<int, Channel> _known = const {};

  /// The channel's pinned post, shown in a bar over the timeline. A feed mixes channels,
  /// so it has no such bar (founder decision, round 7).
  Post? _pinned;
  bool _pinnedHidden = false;

  /// Emoji a double tap sends; the reader's last one, a thumbs up until they react once.
  /// Read once when the timeline opens and kept up to date by reacting here: watching the
  /// setting would tie every channel timeline to a database stream it otherwise never needs.
  String _quick = defaultQuickReaction;
  Map<int, int> _marks = const {};
  bool _loading = false;
  String? _error;

  /// True until the first rows are loaded and the opening position is known; the list is
  /// only built afterwards because its initial index cannot be changed later.
  bool _opening = true;
  int _initialIndex = 0;
  double _initialAlignment = 0;

  /// False until the list has reported its first positions after opening.
  bool _settled = true;

  /// Unread posts between the reader and the newest one, plus the ones that arrived while
  /// reading: what the button at the corner counts, as the official app does.
  int _unreadBelow = 0;

  /// Row that gets the "Unread posts" divider above it; fixed when the feed opens.
  (int, int)? _firstUnread;

  /// Post the timeline opens at: a notification, or a search result / date it jumped to.
  int? _focusChat;
  int? _focusMessage;

  /// Where each source starts when the timeline was jumped; null for the live timeline.
  Map<int, int>? _anchors;

  /// The jumped-to row, tinted for a moment so the eye finds it.
  (int, int)? _highlight;
  Timer? _highlightTimer;
  bool _loadingNewer = false;

  /// Day the timeline jumped to from the calendar; it settles on its first post.
  DateTime? _focusDay;

  /// Day of the topmost post on screen, shown as a floating pill while the list moves and
  /// faded out shortly after it stops, as the official app does. Notifiers, so the pill
  /// comes and goes without rebuilding the list on every scroll.
  final _stickyDay = ValueNotifier<DateTime?>(null);
  final _stickyShown = ValueNotifier<bool>(false);
  Timer? _stickyHide;

  /// How long the floating day pill stays after the list came to rest.
  static const _stickyLinger = Duration(milliseconds: 900);

  /// Set by the button that leaves a jump: the rebuilt timeline opens at its newest post,
  /// not where it would open when the feed is entered.
  bool _openAtNewest = false;

  Map<int, _Anchor> get _remembered => _memory[widget.db] ??= {};

  @override
  void initState() {
    super.initState();
    _focusChat = widget.focusChatId;
    _focusMessage = widget.focusMessageId;
    _positions.itemPositions.addListener(_onPositions);
    unawaited(_loadQuickReaction());
    if (widget.channel != null) unawaited(_loadPinned());
    final feed = widget.feed;
    if (feed == null) {
      final c = widget.channel!;
      _photos = {c.chatId: c.photo};
      _marks = {c.chatId: c.lastReadMessageId};
      _setSources([(chatId: c.chatId, title: c.title, username: c.username)]);
      return;
    }
    _sources = widget.db
        .watchSourceChannels(feed.id)
        .listen(
          (rows) => _setSources([
            for (final r in rows)
              (chatId: r.chatId, title: r.title, username: r.username),
          ]),
        );
    _marksSub = widget.db.watchAllReadMarks().listen((_) async {
      _marks = await widget.db.readMarks(feed.id);
      if (mounted) setState(() {});
    });
    unawaited(_loadPhotos());
    _filter = FeedFilter.decode(feed.filterJson);
    // The filter can change in the feed editor while this timeline is underneath.
    _feedSub = widget.db.watchFeed(feed.id).listen((row) {
      final next = FeedFilter.decode(row?.filterJson);
      if (next == _filter) return;
      _filter = next;
      _timeline = null;
      _setSources(_sourceRows);
    });
  }

  /// The database keeps titles only; the photos come from Telegram's chat list. Rows show
  /// initials until they are here. The channels themselves stay for the forwarded-from line,
  /// which opens the origin when the account follows it.
  Future<void> _loadPhotos() async {
    try {
      final channels = await widget.gateway.myChannels();
      if (!mounted) return;
      _known = {for (final c in channels) c.chatId: c};
      setState(() => _photos = {for (final c in channels) c.chatId: c.photo});
      _reportSources();
    } on TelegramException {
      // Initials stay.
    }
  }

  Future<Map<int, int>> _loadMarks() async =>
      widget.feed == null ? _marks : await widget.db.readMarks(widget.feed!.id);

  /// (Re)builds the timeline when the sources change.
  void _setSources(
    List<({int chatId, String title, String? username})> sources,
  ) {
    _sourceRows = sources;
    _titles = {for (final s in sources) s.chatId: s.title};
    _usernames = {for (final s in sources) s.chatId: s.username};
    final ids = sources.map((s) => s.chatId).toList();
    if (_timeline != null &&
        _timeline!.chatIds.length == ids.length &&
        _timeline!.chatIds.containsAll(ids)) {
      setState(() {});
      return;
    }
    _events?.cancel();
    final t = FeedTimeline(
      widget.gateway,
      ids,
      filter: _filter,
      startAt: _anchors,
    );
    _firstUnread = null;
    _timeline = t;
    _events = widget.gateway.postEvents.listen((e) {
      final before = t.items.length;
      final changed = t.apply(e);
      if (changed || e is PostAdded) setState(() {});
      // A row added at the newest end shifts every index; stay glued to the newest post.
      if (t.atTop && t.items.length > before) _jumpToNewest();
      if (e is PostAdded) _coverHidden();
    });
    // A list that is already up keeps its scroll position: initialScrollIndex only counts
    // when it is built for the first time, and the spinner in between may never be drawn.
    final rebuild = _scrollCtl.isAttached;
    setState(() => _opening = true);
    _reportSources();
    unawaited(_open(t, reposition: rebuild));
  }

  /// Hands the screen what its search needs. After the frame: sources arrive while this
  /// widget builds, and the parent may not be rebuilt from inside that build.
  void _reportSources() {
    final report = widget.onSources;
    if (report == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      report((
        chatIds: [for (final s in _sourceRows) s.chatId],
        filter: _filter,
        titles: _titles,
        photos: _photos,
      ));
    });
  }

  /// Opens the timeline around one post, the way the official app opens a search result or
  /// a date: every source starts at its newest post up to that moment, the post itself is
  /// the anchor of its own channel, and the list can page both ways from there.
  Future<void> jumpToPost({
    required int chatId,
    required int messageId,
    required int date,
  }) async {
    final others = [
      for (final s in _sourceRows)
        if (s.chatId != chatId) s.chatId,
    ];
    var anchors = {chatId: messageId};
    if (others.isNotEmpty) {
      try {
        anchors = {
          ...await anchorsForDate(widget.gateway, others, date),
          chatId: messageId,
        };
      } on TelegramException catch (e) {
        _error = e.message; // the post of its own channel is still reachable
      }
    }
    if (!mounted) return;
    _focusChat = chatId;
    _focusMessage = messageId;
    _anchors = anchors;
    _highlightTimer?.cancel();
    _highlight = null;
    _timeline = null;
    _setSources(_sourceRows);
  }

  /// Opens the calendar and jumps to the day the reader picks, as in the official app.
  Future<void> pickDate({DateTime? around}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: around ?? now,
      // Telegram itself is younger than this.
      firstDate: DateTime(2013),
      lastDate: now,
      helpText: 'Jump to date',
    );
    if (picked == null || !mounted) return;
    await jumpToDate(picked);
  }

  /// Opens the timeline at a day: every source starts at its newest post of that day (or
  /// the newest older one), and the list settles on the first post of the day.
  Future<void> jumpToDate(DateTime day) async {
    final messenger = ScaffoldMessenger.of(context);
    final end = DateTime(day.year, day.month, day.day, 23, 59, 59);
    Map<int, int> anchors;
    try {
      anchors = await anchorsForDate(widget.gateway, [
        for (final s in _sourceRows) s.chatId,
      ], end.millisecondsSinceEpoch ~/ 1000);
    } on TelegramException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Telegram: ${e.message}')));
      return;
    }
    if (!mounted) return;
    if (anchors.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Nothing here from ${formatDay(day)} or earlier.'),
        ),
      );
      return;
    }
    _focusChat = null;
    _focusMessage = null;
    _focusDay = DateTime(day.year, day.month, day.day);
    _anchors = anchors;
    _highlightTimer?.cancel();
    _highlight = null;
    _timeline = null;
    _setSources(_sourceRows);
  }

  /// Back to the live timeline: rebuilt without anchors, at its newest post.
  void _toNewest() {
    final t = _timeline;
    if (t == null) return;
    if (!t.anchored) {
      _release();
      return;
    }
    _anchors = null;
    _focusChat = null;
    _focusMessage = null;
    _focusDay = null;
    _openAtNewest = true;
    _highlightTimer?.cancel();
    _highlight = null;
    _timeline = null;
    _setSources(_sourceRows);
  }

  /// Posts the filter hides count as read once everything before them is: otherwise a
  /// channel that only posts hidden things would keep its feed marked as new forever.
  void _coverHidden() {
    final t = _timeline;
    if (t == null || _filter.isEmpty) return;
    for (final chat in t.chatIds) {
      final mark = _marks[chat] ?? 0;
      if (mark == 0 || !t.sortedDownTo(chat, mark)) continue;
      final covered = t.coveredFrom(chat, mark);
      if (covered > mark) _marker.cover(chat, covered);
    }
  }

  int _indexOf(FeedTimeline t, int chatId, bool Function(TimelineItem) test) =>
      t.items.indexWhere((i) => i.chatId == chatId && test(i));

  /// Loads the first rows and decides where the list opens: the post a notification asked
  /// for, else where the user left this feed earlier in the session, else the first unread
  /// post, else the newest post.
  Future<void> _open(FeedTimeline t, {bool reposition = false}) async {
    setState(() => _loading = true);
    try {
      _marks = await _loadMarks();
      await t.loadMore();
      Future<int> search(int Function() find) async {
        var index = find();
        for (var pages = 0; index < 0 && pages < 8 && !t.exhausted; pages++) {
          await t.loadMore();
          index = find();
        }
        return index;
      }

      final focusChat = _focusChat;
      final focusMessage = _focusMessage;
      final left = _remembered[_memoryKey];
      var index = -1;
      if (_openAtNewest) {
        _openAtNewest = false;
        _initialIndex = 0;
        _initialAlignment = 0;
        _error = null;
        return;
      }
      final day = _focusDay;
      if (day != null) {
        // The anchors are the last posts of that day, so the day has to be loaded down to
        // its beginning before its first post can be found: a page holds thirty rows and a
        // busy feed has many more in a day.
        final dayStart = day.millisecondsSinceEpoch ~/ 1000;
        while (!t.exhausted &&
            t.items.length < _openCap &&
            (t.items.isEmpty || t.items.last.head.date >= dayStart)) {
          await t.loadMore();
        }
        // One page of newer posts goes above, then the list settles on the first row of the
        // day, with the last one of the day before it just off the top of the screen.
        if (t.anchored) await t.loadNewer();
        var first = -1;
        for (var i = 0; i < t.items.length; i++) {
          if (_dayOf(t.items[i]) == day) first = i;
        }
        if (first >= 0) {
          _initialIndex = (first + 1).clamp(0, t.items.length);
          _initialAlignment = 0.92;
          _error = null;
          return;
        }
        // Nothing was posted that day: the closest older post is the anchor itself.
        _initialIndex = 0;
        _initialAlignment = 0;
        _error = null;
        return;
      }
      if (focusChat != null && focusMessage != null) {
        bool isFocus(TimelineItem i) =>
            i.allPosts.any((p) => p.messageId == focusMessage);
        index = await search(() => _indexOf(t, focusChat, isFocus));
        if (t.anchored && index >= 0) {
          // One page of newer posts above the post, so it stands in its surroundings and
          // the list does not run on towards the newest end by itself.
          await t.loadNewer();
          index = _indexOf(t, focusChat, isFocus);
          _flash((focusChat, t.items[index].rowId));
        }
        _initialAlignment = t.anchored ? 0.55 : 0.3;
      } else if (left != null) {
        index = await search(
          () => _indexOf(t, left.chatId, (i) => i.rowId == left.rowId),
        );
        _initialAlignment = left.edge;
      }
      if (index < 0) {
        while (!t.reachedMarks(_marks) &&
            !t.exhausted &&
            t.items.length < _openCap) {
          await t.loadMore();
        }
        final unread = t.firstUnreadIndex(_marks);
        if (unread < 0) {
          index = 0;
          _initialAlignment = 0;
        } else {
          final row = t.items[unread];
          _firstUnread = (row.chatId, row.rowId);
          // The divider sits on top of the first unread row. The list can only be aligned
          // by a row's bottom edge, so the row above it (older, or the footer) is put
          // just below the top of the screen.
          index = unread + 1;
          _initialAlignment = 0.92;
        }
      }
      _initialIndex = index;
      _error = null;
    } on TelegramException catch (e) {
      _error = e.message;
    } finally {
      if (mounted && identical(t, _timeline)) {
        setState(() {
          _loading = false;
          _opening = false;
        });
        _settled = false;
        if (reposition) {
          final at = _initialIndex;
          final alignment = _initialAlignment;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && identical(t, _timeline) && _scrollCtl.isAttached) {
              _scrollCtl.jumpTo(
                index: at.clamp(0, t.items.length),
                alignment: alignment,
              );
            }
          });
        }
        _coverHidden();
      }
    }
  }

  /// A few unread posts do not fill the screen below the divider: the list would show empty
  /// space under the newest post, or cut off its last lines. When the newest post is (nearly)
  /// on screen anyway, it goes to the bottom instead.
  void _settleAtNewest(Iterable<ItemPosition> positions) {
    for (final p in positions) {
      if (p.index == 0 && p.itemLeadingEdge > -0.25 && p.itemLeadingEdge != 0) {
        // Right away (positions are reported after layout, not during a build): a jump that
        // waits for some later frame would rebuild the rows under the user's first tap.
        if (_scrollCtl.isAttached) _scrollCtl.jumpTo(index: 0, alignment: 0);
        return;
      }
    }
  }

  void _jumpToNewest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollCtl.isAttached) {
        _scrollCtl.jumpTo(index: 0, alignment: 0);
      }
    });
  }

  /// Visible rows drive read marking, the "at the newest post" flag, the remembered position
  /// and loading of older posts. The list is reversed: index 0 is the newest post at the
  /// bottom, and a row's leading edge is its bottom, measured from the viewport's bottom.
  void _onPositions() {
    final t = _timeline;
    final positions = _positions.itemPositions.value;
    if (t == null || positions.isEmpty || _opening) return;
    if (!_settled) {
      // First layout after opening.
      _settled = true;
      _settleAtNewest(positions);
    }
    final items = t.items;
    if (items.isEmpty) return;
    var newest = positions.first;
    var oldestIndex = positions.first.index;
    final seen = <TimelineItem>[];
    for (final p in positions) {
      if (p.index < newest.index) newest = p;
      if (p.index > oldestIndex) oldestIndex = p.index;
      // Read like in Telegram: the post has been on screen down to its end.
      if (p.index < items.length &&
          p.itemLeadingEdge >= 0 &&
          p.itemLeadingEdge < 1) {
        seen.add(items[p.index]);
      }
    }
    if (seen.isNotEmpty) {
      _marker.seen(
        seen,
        coveredUpTo: (item) => t.coveredFrom(item.chatId, item.head.messageId),
      );
      // A single channel has no marks table to listen to; its dots clear here.
      if (widget.feed == null) {
        final chat = widget.channel!.chatId;
        var newestSeen = _marks[chat] ?? 0;
        for (final item in seen) {
          if (item.head.messageId > newestSeen) {
            newestSeen = item.head.messageId;
          }
        }
        if (newestSeen != _marks[chat]) {
          setState(() => _marks = {chat: newestSeen});
        }
      }
    }
    // The list is reversed, so the row on top of the screen is the one with the highest
    // index: its day is what the floating pill names.
    _show(_stickyDay, _dayOf(items[oldestIndex.clamp(0, items.length - 1)]));
    if (newest.index < items.length && !t.anchored) {
      final row = items[newest.index];
      _remembered[_memoryKey] = _Anchor(
        row.chatId,
        row.rowId,
        newest.itemLeadingEdge,
      );
    }
    // Close to the newest loaded row of a jumped timeline: fetch the ones above it.
    if (t.anchored && !t.exhaustedNewer && newest.index <= 3) {
      unawaited(_loadNewer());
    }
    // A jumped timeline is only at the newest post once it has caught up with the live end.
    final below = t.unreadBefore(newest.index, _marks) + t.pendingNew;
    if (below != _unreadBelow) setState(() => _unreadBelow = below);
    final atNewest =
        newest.index == 0 &&
        newest.itemLeadingEdge >= -0.05 &&
        (!t.anchored || t.exhaustedNewer);
    if (atNewest != t.atTop) {
      t.atTop = atNewest;
      if (atNewest && t.pendingNew > 0) {
        _release();
      } else {
        setState(() {}); // the "to newest" button comes and goes
      }
    }
    if (oldestIndex >= items.length - 5) unawaited(_loadMore());
  }

  /// The floating day pill follows a scroll the reader started: it is there as soon as the
  /// list moves under the finger and fades out [_stickyLinger] after the list came to rest,
  /// like the date in the official app. A scroll of the app's own making (opening the feed,
  /// a jump to a date, new posts at the bottom) does not bring it out.
  bool _onScroll(ScrollNotification n) {
    if (n is UserScrollNotification) {
      if (n.direction != ScrollDirection.idle) _armSticky();
    } else if (n is ScrollUpdateNotification && _stickyShown.value) {
      _armSticky(); // the fling after the finger is gone keeps it up
    }
    return false;
  }

  void _armSticky() {
    _show(_stickyShown, true);
    _stickyHide?.cancel();
    _stickyHide = Timer(_stickyLinger, () {
      if (mounted) _show(_stickyShown, false);
    });
  }

  /// A scroll notification can arrive from inside the list's own layout (new content
  /// dimensions start a ballistic scroll), and the pill must not be rebuilt from there:
  /// such a change waits for the end of the frame.
  void _show<T>(ValueNotifier<T> notifier, T value) {
    if (notifier.value == value) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      notifier.value = value;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) notifier.value = value;
    });
  }

  /// Tints the row for a moment, so the post the timeline jumped to is easy to spot.
  void _flash((int, int) row) {
    _highlightTimer?.cancel();
    _highlight = row;
    _highlightTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _highlight = null);
    });
  }

  /// Pages towards the newest post after a jump. The rows appear before the ones on screen,
  /// so every index moves up by as many; the reader is put back where they were.
  Future<void> _loadNewer() async {
    final t = _timeline;
    if (t == null || _loadingNewer || !t.anchored || t.exhaustedNewer) return;
    _loadingNewer = true;
    // The row closest to the newest end is the one to hold on to.
    ItemPosition? newest;
    for (final p in _positions.itemPositions.value) {
      if (newest == null || p.index < newest.index) newest = p;
    }
    final index = newest?.index ?? 0;
    final edge = newest?.itemLeadingEdge ?? 0.0;
    try {
      final added = await t.loadNewer();
      if (!mounted || !identical(t, _timeline)) return;
      setState(() {});
      if (added > 0 && _scrollCtl.isAttached) {
        // Right away, like _settleAtNewest: a later frame would show the new rows first.
        _scrollCtl.jumpTo(index: index + added, alignment: edge);
      }
    } on TelegramException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      _loadingNewer = false;
    }
  }

  Future<void> _loadMore() async {
    final t = _timeline;
    if (t == null || _loading || t.exhausted) return;
    setState(() => _loading = true);
    try {
      await t.loadMore();
      _error = null;
      _coverHidden();
    } on TelegramException catch (e) {
      _error = e.message;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Shows the posts that arrived while the user was reading older ones, scrolled so the
  /// oldest of them is in view; without any, goes to the newest post.
  void _release() {
    final t = _timeline;
    if (t == null) return;
    final arrived = t.pendingNew;
    t.releasePending();
    setState(() {});
    if (!_scrollCtl.isAttached) return;
    _scrollCtl.scrollTo(
      index: arrived > 1 ? arrived - 1 : 0,
      alignment: arrived > 1 ? 0.5 : 0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  /// Opens the post in the Telegram app, falling back to t.me in the browser.
  Future<void> _openInTelegram(TimelineItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = telegramPostUri(
      chatId: item.chatId,
      messageId: item.head.messageId,
      username: _usernames[item.chatId],
    );
    final web = telegramPostWebUri(
      chatId: item.chatId,
      messageId: item.head.messageId,
    );
    if (await launchFirst([uri, web])) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('No app can open this post.')),
    );
  }

  /// Tap on the forwarded-from line: opens the original post in the channel it came from,
  /// when the account follows that channel. Channels the account does not follow cannot be
  /// read (SPEC 5), so the line only says so.
  void _openForward(TimelineItem item) {
    final origin = item.head.forwardedFrom;
    if (origin == null) return;
    final channel = _known[origin.chatId];
    if (channel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            origin.title.isEmpty
                ? 'That post came from an account that hides itself.'
                : '${origin.title} is not a channel you follow.',
          ),
        ),
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
            focusChatId: origin.chatId,
            focusMessageId: origin.messageId == 0 ? null : origin.messageId,
          ),
        ),
      ),
    );
  }

  /// Tap on the quote block: to the post this one answers. Inside the timeline's own
  /// channels that is a jump; a post of another channel opens that channel, when the account
  /// follows it.
  void _openReply(TimelineItem item) {
    final reply = item.textPost.replyTo;
    if (reply == null || reply.messageId == 0) return;
    final t = _timeline;
    if (t != null && t.chatIds.contains(reply.chatId)) {
      unawaited(
        jumpToPost(
          chatId: reply.chatId,
          messageId: reply.messageId,
          // The answered post is older than the one answering it.
          date: item.head.date,
        ),
      );
      return;
    }
    final channel = _known[reply.chatId];
    if (channel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That post is in a channel you do not follow.'),
        ),
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
            focusChatId: reply.chatId,
            focusMessageId: reply.messageId,
          ),
        ),
      ),
    );
  }

  /// A link in a post: whatever app handles it, the browser for web pages.
  Future<void> _openLink(String url) async {
    final messenger = ScaffoldMessenger.of(context);
    if (await launchFirst([Uri.tryParse(url)])) return;
    messenger.showSnackBar(SnackBar(content: Text('No app can open $url')));
  }

  Uri? _shareLink(TimelineItem item) => telegramShareUri(
    chatId: item.chatId,
    messageId: item.head.messageId,
    username: _usernames[item.chatId],
  );

  Future<void> _share(TimelineItem item) async {
    final link = _shareLink(item);
    if (link == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This post has no link to share.')),
      );
      return;
    }
    final title = _titles[item.chatId] ?? '';
    await widget.share(
      shareText(channelTitle: title, text: item.head.text, link: link),
      subject: title,
    );
  }

  /// The post's words, as the official app's "Copy" does.
  Future<void> _copyText(TimelineItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: item.text));
    messenger.showSnackBar(const SnackBar(content: Text('Text copied')));
  }

  Future<void> _copyLink(TimelineItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    final link = _shareLink(item);
    if (link == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('This post has no link to copy.')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: link.toString()));
    messenger.showSnackBar(SnackBar(content: Text('Link copied: $link')));
  }

  /// Forwards the post, and with it the whole album, into Saved Messages.
  Future<void> _save(TimelineItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.gateway.saveToSavedMessages(item.chatId, [
        for (final p in item.allPosts) p.messageId,
      ]);
      messenger.showSnackBar(
        const SnackBar(content: Text('Saved to Saved Messages')),
      );
    } on TelegramException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Telegram: ${e.message}')));
    }
  }

  Future<void> _react(TimelineItem item, String emoji, bool remove) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.gateway.react(
        item.chatId,
        item.head.messageId,
        emoji,
        remove: remove,
      );
      // The one reacted with last is the one a double tap sends, as in the official app.
      if (!remove) {
        if (mounted) setState(() => _quick = emoji);
        await widget.db.setSetting(SettingKeys.quickReaction, emoji);
      }
    } on TelegramException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Telegram: ${e.message}')));
    }
  }

  Future<void> _loadPinned() async {
    try {
      final pinned = await widget.gateway.pinnedPost(widget.channel!.chatId);
      if (mounted && pinned != null) setState(() => _pinned = pinned);
    } on TelegramException {
      // No bar, as if the channel had nothing pinned.
    }
  }

  Future<void> _loadQuickReaction() async {
    final emoji = await widget.db.setting(SettingKeys.quickReaction);
    if (mounted && emoji != null && emoji.isNotEmpty) {
      setState(() => _quick = emoji);
    }
  }

  /// Double tap on a post: the quick reaction, added or taken back again. A channel that
  /// does not allow that emoji says so through Telegram's own answer.
  Future<void> _quickReact(TimelineItem item) async {
    final emoji = _quick;
    final chosen = item.head.reactions.any((r) => r.emoji == emoji && r.chosen);
    await _react(item, emoji, chosen);
  }

  /// Emoji for the post menu; a failure is reported by the menu itself.
  Future<List<String>> _availableReactions(TimelineItem item) =>
      widget.gateway.availableReactions(item.chatId, item.head.messageId);

  @override
  void dispose() {
    _positions.itemPositions.removeListener(_onPositions);
    _stickyHide?.cancel();
    _stickyDay.dispose();
    _stickyShown.dispose();
    _highlightTimer?.cancel();
    _events?.cancel();
    _sources?.cancel();
    _marksSub?.cancel();
    _feedSub?.cancel();
    unawaited(_marker.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _timeline;
    final items = t?.items ?? const <TimelineItem>[];
    return Stack(
      children: [
        Positioned.fill(
          child: ColoredBox(
            color: ChatColors.of(context).background,
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: _body(context, t, items),
            ),
          ),
        ),
        if (_pinned != null && !_pinnedHidden)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: PinnedBar(
              post: _pinned!,
              onTap: () => unawaited(
                jumpToPost(
                  chatId: _pinned!.chatId,
                  messageId: _pinned!.messageId,
                  date: _pinned!.date,
                ),
              ),
              onHide: () => setState(() => _pinnedHidden = true),
            ),
          ),
        if (t != null && !_opening && items.isNotEmpty)
          Positioned(
            top: _pinned != null && !_pinnedHidden ? pinnedBarHeight : 0,
            left: 0,
            right: 0,
            child: FloatingDay(
              day: _stickyDay,
              shown: _stickyShown,
              onTap: (day) => unawaited(pickDate(around: day)),
            ),
          ),
        if (t != null && !_opening && (!t.atTop || t.anchored))
          Positioned(
            right: 16,
            bottom: 16,
            child: Badge.count(
              count: _unreadBelow,
              isLabelVisible: _unreadBelow > 0,
              child: FloatingActionButton.small(
                heroTag: null,
                tooltip: t.pendingNew > 0
                    ? '${t.pendingNew} new post${t.pendingNew == 1 ? '' : 's'}'
                    : _unreadBelow > 0
                    ? '$_unreadBelow unread post${_unreadBelow == 1 ? '' : 's'}'
                    : 'Newest posts',
                onPressed: _toNewest,
                child: const Icon(Icons.keyboard_arrow_down),
              ),
            ),
          ),
      ],
    );
  }

  static DateTime _dayOf(TimelineItem item) {
    final d = DateTime.fromMillisecondsSinceEpoch(item.head.date * 1000);
    return DateTime(d.year, d.month, d.day);
  }

  Widget _body(
    BuildContext context,
    FeedTimeline? t,
    List<TimelineItem> items,
  ) {
    return t == null || _opening
        ? const Center(child: CircularProgressIndicator())
        : items.isEmpty && t.chatIds.isEmpty
        ? const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'This feed has no channels yet. Tap the tune icon to add some.',
                textAlign: TextAlign.center,
              ),
            ),
          )
        : items.isEmpty
        ? Center(
            child: Text(
              _error != null
                  ? 'Telegram: $_error'
                  : _filter.isEmpty
                  ? 'No posts.'
                  : 'No posts pass this feed\'s filter (${_filter.describe()}).',
              textAlign: TextAlign.center,
            ),
          )
        // Oldest at the top, newest at the bottom, like a chat in Telegram.
        : ScrollablePositionedList.builder(
            reverse: true,
            // Room under the newest post: index 0 sits at the bottom edge of the screen,
            // where the bubble would otherwise touch the edge (and the gesture bar).
            padding: EdgeInsets.only(
              bottom: 8 + MediaQuery.paddingOf(context).bottom,
            ),
            initialScrollIndex: _initialIndex.clamp(0, items.length),
            initialAlignment: _initialAlignment,
            itemScrollController: _scrollCtl,
            itemPositionsListener: _positions,
            itemCount: items.length + 1,
            itemBuilder: (context, i) {
              if (i == items.length) {
                // The list builds this row a little before it scrolls into view: time to
                // fetch older posts. Without it the spinner would turn for ever off screen
                // when the rows end just short of it. After an error only scrolling retries.
                if (!t.exhausted && _error == null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) unawaited(_loadMore());
                  });
                }
                return Padding(
                  padding: const EdgeInsets.all(10),
                  child: Center(
                    child: t.exhausted
                        ? const ChatPill('Beginning of the feed')
                        : _error != null
                        ? ChatPill('Telegram: $_error')
                        : const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                  ),
                );
              }
              final item = items[i];
              final id = (item.chatId, item.rowId);
              final card = PostCard(
                item: item,
                channelTitle: _titles[item.chatId] ?? '',
                channelPhoto: _photos[item.chatId],
                gateway: widget.gateway,
                unread: FeedTimeline.isUnread(item, _marks),
                onOpenInTelegram: () => _openInTelegram(item),
                onShare: () => _share(item),
                onCopyLink: () => _copyLink(item),
                onCopyText: item.text.isEmpty ? null : () => _copyText(item),
                onSave: () => _save(item),
                onReact: (emoji, remove) => _react(item, emoji, remove),
                availableReactions: () => _availableReactions(item),
                onOpenLink: _openLink,
                onAutoplaySettings: () =>
                    showAutoplaySettings(context, widget.db),
                onOpenForward: item.head.forwardedFrom == null
                    ? null
                    : () => _openForward(item),
                onOpenReply: item.textPost.replyTo == null
                    ? null
                    : () => _openReply(item),
                onQuickReact: () => unawaited(_quickReact(item)),
                // Only posts of channels with a discussion group have a thread.
                onOpenThread: !item.head.canComment
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ThreadScreen(
                            gateway: widget.gateway,
                            post: item.head,
                            item: item,
                            channelTitle: _titles[item.chatId] ?? '',
                            channelPhoto: _photos[item.chatId],
                          ),
                        ),
                      ),
              );
              // The day goes above its first post: the row after this one is older.
              final day = _dayOf(item);
              final newDay =
                  i == items.length - 1 || _dayOf(items[i + 1]) != day;
              final row = id != _highlight
                  ? card
                  : ColoredBox(
                      color: Theme.of(context).colorScheme.primary
                          .withValues(alpha: 0.12),
                      child: card,
                    );
              return KeyedSubtree(
                key: ValueKey(id),
                child: !newDay && id != _firstUnread
                    ? row
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (newDay)
                            ChatPill(
                              formatDay(day),
                              onTap: () => unawaited(pickDate(around: day)),
                            ),
                          if (id == _firstUnread) const UnreadDivider(),
                          row,
                        ],
                      ),
              );
            },
          );
  }
}

/// The day of the topmost post, floating over the timeline: it is there while the list
/// moves and fades out once it comes to rest, as the date does in the official app. A tap
/// opens the calendar on that day, like the day pills between the posts.
class FloatingDay extends StatefulWidget {
  const FloatingDay({
    super.key,
    required this.day,
    required this.shown,
    this.onTap,
  });

  /// Day of the topmost post; null until the list has reported its first rows.
  final ValueListenable<DateTime?> day;

  /// Whether the list is moving (or has just come to rest).
  final ValueListenable<bool> shown;
  final void Function(DateTime day)? onTap;

  @override
  State<FloatingDay> createState() => _FloatingDayState();
}

class _FloatingDayState extends State<FloatingDay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    value: _visible ? 1 : 0,
  );

  bool get _visible => widget.shown.value && widget.day.value != null;

  @override
  void initState() {
    super.initState();
    widget.shown.addListener(_follow);
    widget.day.addListener(_follow);
  }

  @override
  void dispose() {
    widget.shown.removeListener(_follow);
    widget.day.removeListener(_follow);
    _fade.dispose();
    super.dispose();
  }

  void _follow() => _visible ? _fade.forward() : _fade.reverse();

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _fade,
    builder: (context, _) {
      final day = widget.day.value;
      // Nothing in the tree while it is away: a pill nobody can see is none.
      if (_fade.value == 0 || day == null) return const SizedBox.shrink();
      return Opacity(
        opacity: _fade.value,
        child: ChatPill(
          formatDay(day),
          onTap: widget.onTap == null ? null : () => widget.onTap!(day),
        ),
      );
    },
  );
}

/// Height of [PinnedBar]; the floating day pill stands below it.
const pinnedBarHeight = 44.0;

/// The channel's pinned post over the timeline, as in the official app: a line of what it
/// says, a tap to jump to it, and a cross to put the bar away for this visit.
class PinnedBar extends StatelessWidget {
  const PinnedBar({
    super.key,
    required this.post,
    required this.onTap,
    required this.onHide,
  });
  final Post post;
  final VoidCallback onTap;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.96),
      child: SizedBox(
        height: pinnedBarHeight,
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.push_pin_outlined,
                        size: 18,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Pinned post',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: scheme.primary,
                              ),
                            ),
                            Text(
                              // One line: a pinned post may be a long one.
                              postLabel(post)
                                  .replaceAll(String.fromCharCode(10), ' '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Hide',
              icon: const Icon(Icons.close, size: 18),
              onPressed: onHide,
            ),
          ],
        ),
      ),
    );
  }
}

/// Marks where the unread posts began when the feed was opened.
class UnreadDivider extends StatelessWidget {
  const UnreadDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(vertical: 4),
      color: scheme.secondaryContainer.withValues(alpha: 0.85),
      alignment: Alignment.center,
      child: Text(
        'Unread posts',
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: scheme.onSecondaryContainer),
      ),
    );
  }
}
