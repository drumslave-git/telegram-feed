import 'dart:async';
import 'dart:math' as math;

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
import '../home/connection_title.dart';
import '../media/media_viewer.dart';
import '../settings/data_storage_screen.dart' show DataStorageScreen;
import '../settings/settings_tiles.dart' show openSettingsScreen;
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';
import 'feed_editor_screen.dart';
import 'open_links.dart';
import 'post_card.dart';
import 'read_marker.dart';
import 'recent_searches.dart';
import 'saved_position.dart';
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

  /// What kind of post the search looks for (H-26).
  HistoryFilter _searchFilter = HistoryFilter.any;

  /// The words searched for last, offered when the bar opens (H-28).
  List<String> _recent = const [];

  /// True while the results cover the timeline; false once a result was opened.
  bool _listOpen = false;

  /// Result the timeline stands on, -1 before one was opened.
  int _current = -1;
  bool _jumping = false;

  /// How many rows the timeline has picked; over zero the bar of H-17 takes the app bar.
  int _selected = 0;

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

  void _openSearch() {
    setState(() {
      _searchOpen = true;
      _listOpen = true;
    });
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
      _listOpen = false;
      _session = null;
      _current = -1;
      _searchFilter = HistoryFilter.any;
    });
  }

  /// A chip was chosen: the same words, looked for among that kind of post. With no words
  /// yet, a kind alone lists what the channels have of it.
  void _setSearchFilter(HistoryFilter filter) {
    if (filter == _searchFilter) return;
    setState(() {
      _searchFilter = filter;
      _listOpen = true;
      _current = -1;
    });
    unawaited(_startSearch(_queryCtl.text));
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
    // A kind of post on its own is a search too: "every video of this feed".
    if (query.isEmpty && _searchFilter == HistoryFilter.any) {
      setState(() => _session = null);
      return;
    }
    final session = SearchSession(
      gateway: widget.gateway,
      chatIds: _sources.chatIds,
      query: query,
      filter: _searchFilter,
      feedFilter: _sources.filter,
    );
    setState(() {
      _session = session;
      _current = -1;
    });
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

  /// What the reader picked, and what can be done with it: the official app's own set,
  /// minus forwarding to a chat, which this app does not do.
  PreferredSizeWidget _selectionBar() => AppBar(
    leading: IconButton(
      tooltip: 'Cancel',
      icon: const Icon(Icons.close),
      onPressed: () => _view.currentState?.clearSelection(),
    ),
    title: Text('$_selected selected'),
    actions: [
      IconButton(
        tooltip: 'Copy text',
        icon: const Icon(Icons.content_copy),
        onPressed: () => unawaited(_copySelected()),
      ),
      IconButton(
        tooltip: 'Share',
        icon: const Icon(Icons.share),
        onPressed: () => unawaited(_shareSelected()),
      ),
      IconButton(
        tooltip: 'Save to Saved Messages',
        icon: const Icon(Icons.bookmark_add_outlined),
        onPressed: () => unawaited(_saveSelected()),
      ),
    ],
  );

  List<TimelineItem> get _picked =>
      _view.currentState?.selectedItems ?? const [];

  Future<void> _copySelected() async {
    final messenger = ScaffoldMessenger.of(context);
    final items = _picked;
    final text = [
      for (final i in items)
        if (i.text.isNotEmpty) i.text,
    ].join(String.fromCharCode(10) + String.fromCharCode(10));
    await Clipboard.setData(ClipboardData(text: text));
    _view.currentState?.clearSelection();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${items.length} post${items.length == 1 ? '' : 's'} copied',
        ),
      ),
    );
  }

  Future<void> _shareSelected() async {
    final items = _picked;
    final view = _view.currentState;
    final parts = [for (final i in items) view?.shareTextOf(i) ?? i.text];
    _view.currentState?.clearSelection();
    await widget.share(
      parts.join(String.fromCharCode(10) + String.fromCharCode(10)),
      subject: widget.feed?.name ?? widget.channel?.title ?? '',
    );
  }

  Future<void> _saveSelected() async {
    final messenger = ScaffoldMessenger.of(context);
    final items = _picked;
    final byChat = <int, List<int>>{};
    for (final i in items) {
      byChat.putIfAbsent(i.chatId, () => []).addAll([
        for (final p in i.allPosts) p.messageId,
      ]);
    }
    _view.currentState?.clearSelection();
    try {
      for (final entry in byChat.entries) {
        await widget.gateway.saveToSavedMessages(entry.key, entry.value);
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${items.length} post${items.length == 1 ? '' : 's'} saved to Saved Messages',
          ),
        ),
      );
    } on TelegramException catch (e) {
      showTelegramError(messenger, e, what: 'Could not save the posts.');
    }
  }

  PreferredSizeWidget _appBar(BuildContext context) {
    final theme = Theme.of(context);
    if (_selected > 0) return _selectionBar();
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
            // The calendar takes over from the search, as in the official app; cancelled,
            // it leaves the search as it was.
            onPressed: () =>
                unawaited(_view.currentState?.pickDate(onPicked: _closeSearch)),
          ),
        ],
        // The kinds of post to look for, under the field as in the official app.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: SearchFilterChips(
            filter: _searchFilter,
            onChanged: _setSearchFilter,
          ),
        ),
      );
    }
    final channel = widget.channel;
    return AppBar(
      title: ConnectionTitle(
        gateway: widget.gateway,
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
    return PopScope(
      canPop: _selected == 0 && !_searchOpen,
      // Back first leaves the selection, then the search, as in the official app.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_selected > 0) {
          _view.currentState?.clearSelection();
        } else {
          _closeSearch();
        }
      },
      child: Scaffold(
        appBar: _appBar(context),
        body: Column(
          children: [
            Expanded(
              // The stepper below takes the gesture inset for itself, so the timeline
              // must not keep room for it too while the stepper stands there. Through a
              // Builder: this screen's own context sits above the Scaffold, whose body
              // already has the status-bar inset removed, and copying the outer data
              // over it would put that inset back at the top of the list.
              child: Builder(
                builder: (context) => MediaQuery.removePadding(
                  context: context,
                  removeBottom: _searchOpen && !_listOpen && session != null,
                  child: Stack(
                    children: [
                      TimelineView(
                        key: _view,
                        db: widget.db,
                        gateway: widget.gateway,
                        onSelectionChanged: (n) =>
                            setState(() => _selected = n),
                        feed: widget.feed,
                        channel: widget.channel,
                        focusChatId: widget.focusChatId,
                        focusMessageId: widget.focusMessageId,
                        share: widget.share,
                        onSources: _onSources,
                        onEditFeed: widget.feed == null
                            ? null
                            : _openFeedEditor,
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
                              total: session?.total ?? -1,
                              error: session?.error,
                              current: _current,
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
                          ),
                        ),
                    ],
                  ),
                ),
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
    this.onSelectionChanged,
    this.onEditFeed,
  }) : assert((feed == null) != (channel == null));
  final AppDatabase db;
  final TelegramGateway gateway;

  /// Reports the channels, the filter and the photos as they are loaded, for the search.
  final ValueChanged<TimelineSources>? onSources;

  /// How many rows are picked, so the screen can put up the selection bar.
  final ValueChanged<int>? onSelectionChanged;

  /// Opens the feed's channels; the button an empty feed offers. Null for a channel.
  final VoidCallback? onEditFeed;

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

class TimelineViewState extends State<TimelineView>
    with WidgetsBindingObserver {
  /// Opening loads down to the read marks, or to the row the reader left the timeline at,
  /// but never more than this many rows.
  static const _openCap = 300;

  final _scrollCtl = ItemScrollController();
  final _positions = ItemPositionsListener.create();
  late final ReadMarker _marker = ReadMarker(gateway: widget.gateway);

  /// Where the position the reader leaves this timeline at is kept.
  String get _positionKey => widget.feed != null
      ? SettingKeys.positionOfFeed(widget.feed!.id)
      : SettingKeys.positionOfChat(widget.channel!.chatId);
  FeedTimeline? _timeline;
  StreamSubscription<PostEvent>? _events;
  StreamSubscription<List<WatchedChannel>>? _sources;
  StreamSubscription<ReadState>? _readStates;
  StreamSubscription<Feed?>? _feedSub;
  FeedFilter _filter = FeedFilter.none;
  List<({int chatId, String title, String? username})> _sourceRows = const [];
  Map<int, String> _titles = const {};
  Map<int, String?> _usernames = const {};

  /// Channel photos for the avatars beside the posts.
  Map<int, FileRef?> _photos = const {};

  /// Every channel the account follows, by chat id: the forwarded-from line opens one.
  Map<int, Channel> _known = const {};

  /// Rows the reader picked, by (chat id, row id). Empty means the timeline is reading,
  /// not selecting.
  final _selected = <(int, int)>{};

  /// The channel's pinned post, shown in a bar over the timeline. A feed mixes channels,
  /// so it has no such bar.
  Post? _pinned;
  bool _pinnedHidden = false;

  /// Emoji a double tap sends; the reader's last one, a thumbs up until they react once.
  /// Read once when the timeline opens and kept up to date by reacting here: watching the
  /// setting would tie every channel timeline to a database stream it otherwise never needs.
  String _quick = defaultQuickReaction;

  /// Telegram's read position of every channel (ARCHITECTURE.md 5.4): everything up to it
  /// is read. It moves as the reader reads here, and when the official app or another device
  /// reads.
  Map<int, int> _marks = const {};

  /// Ticks when the button at the corner has to be drawn again while the rows stay as they
  /// are: reading moves [_marks] and reaching the newest post hides the button, both many
  /// times in one scroll, and a rebuild of the whole screen would build every row anew.
  final _corner = ValueNotifier<int>(0);

  /// The row widgets built last, by (chat id, row id), with what they were built from; a
  /// row whose inputs stay the same is handed back as it is and not built again.
  final _rows = <(int, int), ({_RowInputs inputs, Widget row})>{};

  /// The timeline [_rows] belong to.
  FeedTimeline? _rowsOf;
  bool _loading = false;
  String? _error;

  /// True until the first rows are loaded and the opening position is known; the list is
  /// only built afterwards because its initial index cannot be changed later.
  bool _opening = true;
  int _initialIndex = 0;
  double _initialAlignment = 0;

  /// False until the list has reported its first positions after opening.
  bool _settled = true;

  /// True from a rebuild of a list that stayed up until the jump to its opening position
  /// has been laid out: what the list reports in between is where it was before.
  bool _repositioning = false;

  /// Row that gets the "Unread posts" divider above it: the first unread post when the
  /// timeline was entered. It stays for the visit, through jumps and rebuilds.
  (int, int)? _firstUnread;

  /// Whether the divider has been on the screen in this visit. Until it has, the button at
  /// the corner goes to it first, as in the official app.
  bool _dividerSeen = false;

  /// Where a tap on a reply quote jumped from: the button goes back there before it goes
  /// to the newest post, as in the official app.
  ({int chatId, int messageId, int date})? _returnTo;

  /// Where the reader is now, as it is kept on leaving: null at the newest post and on an
  /// unread row. [_hereKnown] is false until the list has reported its rows.
  SavedPosition? _here;
  bool _hereKnown = false;

  /// False until the first opening of this visit. Later rebuilds (a changed filter or
  /// source) keep the reader where they are, not where they left the timeline last time.
  bool _entered = false;

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

  /// Set by the button when the divider is not among the loaded rows: the rebuilt timeline
  /// opens at the first unread post.
  bool _openAtUnread = false;

  @override
  void initState() {
    super.initState();
    _focusChat = widget.focusChatId;
    _focusMessage = widget.focusMessageId;
    _positions.itemPositions.addListener(_onPositions);
    WidgetsBinding.instance.addObserver(this);
    _readStates = widget.gateway.readUpdates.listen(_onReadState);
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

  /// Telegram's read position of every source, as it is now. A position only moves
  /// forward, so one the reader has passed here already stays.
  Future<Map<int, int>> _loadMarks() async {
    final ids = [for (final s in _sourceRows) s.chatId];
    Future<int> of(int chatId) async {
      try {
        return (await widget.gateway.readState(chatId)).lastReadMessageId;
      } on TelegramException {
        return 0;
      }
    }

    final read = await Future.wait(ids.map(of));
    return {
      for (var i = 0; i < ids.length; i++)
        ids[i]: math.max(read[i], _marks[ids[i]] ?? 0),
    };
  }

  /// Telegram moved a read position: the official app, another device, or this reading.
  void _onReadState(ReadState r) {
    if (!mounted || !_titles.containsKey(r.chatId)) return;
    if (r.lastReadMessageId <= (_marks[r.chatId] ?? 0)) return;
    setState(() => _marks = {..._marks, r.chatId: r.lastReadMessageId});
  }

  // Leaving the app is leaving the timeline, as far as its position goes: the official app
  // keeps a chat's position when it pauses.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _keepPosition();
  }

  /// Keeps where the reader is for the next visit, or forgets it when they are at the
  /// newest post or on an unread row. Nothing changes before the list has shown any rows.
  void _keepPosition() {
    if (!_hereKnown) return;
    final here = _here;
    unawaited(
      here == null
          ? widget.db.deleteSetting(_positionKey)
          : widget.db.setSetting(_positionKey, here.encode()),
    );
  }

  Future<SavedPosition?> _loadPosition() async =>
      SavedPosition.decode(await widget.db.setting(_positionKey));

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
    _timeline = t;
    _events = widget.gateway.postEvents.listen((e) {
      final before = t.items.length;
      final changed = t.apply(e);
      if (changed) {
        setState(() {});
      } else if (e is PostAdded) {
        _corner.value++; // held back while the reader is further up: the button counts it
      }
      // A row added at the newest end shifts every index; stay glued to the newest post.
      if (t.atTop && t.items.length > before) _jumpToNewest();
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
  /// Asks for a day and goes there; true when one was picked. [onPicked] runs first,
  /// before the jump, so the search can close only when the reader did pick a day.
  Future<bool> pickDate({DateTime? around, VoidCallback? onPicked}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: around ?? now,
      // Telegram itself is younger than this.
      firstDate: DateTime(2013),
      lastDate: now,
      helpText: 'Jump to date',
    );
    if (picked == null || !mounted) return false;
    onPicked?.call();
    await jumpToDate(picked);
    return true;
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
      showTelegramError(messenger, e, what: 'Could not jump to that day.');
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

  /// The button at the corner, as the official app's: first to the "Unread posts" divider
  /// while the reader has not seen it in this visit, then back to where a reply quote was
  /// tapped, then to the very end of the timeline.
  void _onDownButton() {
    final t = _timeline;
    if (t == null) return;
    final divider = _firstUnread;
    if (divider != null && !_dividerSeen) {
      _dividerSeen = true;
      final i = t.items.indexWhere((x) => (x.chatId, x.rowId) == divider);
      if (i >= 0 && _scrollCtl.isAttached) {
        // As when the timeline opens there: the row above the divider just below the top.
        unawaited(
          _scrollCtl.scrollTo(
            index: i + 1,
            alignment: 0.92,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          ),
        );
        return;
      }
      if (t.anchored) {
        _rebuildLive(atUnread: true);
        return;
      }
    }
    final back = _returnTo;
    if (back != null) {
      _returnTo = null;
      unawaited(
        jumpToPost(
          chatId: back.chatId,
          messageId: back.messageId,
          date: back.date,
        ),
      );
      return;
    }
    if (t.anchored) {
      _rebuildLive(atUnread: false);
    } else {
      _release(toEnd: true);
    }
  }

  /// After a failed load: the timeline is built again from the same place, so a reader who
  /// hit a bad connection is not left with a dead screen.
  void _retryLoad() {
    setState(() => _error = null);
    _timeline = null;
    _setSources(_sourceRows);
  }

  /// Back to the live timeline, rebuilt without anchors: at its first unread post, or at
  /// its newest one.
  void _rebuildLive({required bool atUnread}) {
    _anchors = null;
    _focusChat = null;
    _focusMessage = null;
    _focusDay = null;
    _openAtUnread = atUnread;
    _openAtNewest = !atUnread;
    _highlightTimer?.cancel();
    _highlight = null;
    _timeline = null;
    _setSources(_sourceRows);
  }

  int _indexOf(FeedTimeline t, int chatId, bool Function(TimelineItem) test) =>
      t.items.indexWhere((i) => i.chatId == chatId && test(i));

  /// The first unread row gets the divider, once per visit; the button's first stop.
  void _markFirstUnread(FeedTimeline t, {bool again = false}) {
    if (_firstUnread != null && !again) return;
    final unread = t.firstUnreadIndex(_marks);
    if (unread < 0) return;
    final row = t.items[unread];
    _firstUnread = (row.chatId, row.rowId);
    _dividerSeen = false;
  }

  /// Loads the first rows and decides where the list opens, as the official app opens a
  /// chat: the post a notification asked for; else where the reader left the timeline
  /// scrolled up; else the first unread post under the divider; else the newest post.
  Future<void> _open(FeedTimeline t, {bool reposition = false}) async {
    setState(() => _loading = true);
    try {
      _marks = await _loadMarks();
      final entering = !_entered;
      _entered = true;
      final left = entering
          ? await _loadPosition()
          : (_hereKnown ? _here : null);
      await t.loadMore();
      Future<int> search(int Function() find, {int pages = 8}) async {
        var index = find();
        for (var p = 0; index < 0 && p < pages && !t.exhausted; p++) {
          await t.loadMore();
          index = find();
        }
        return index;
      }

      final focusChat = _focusChat;
      final focusMessage = _focusMessage;
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
      final atUnread = _openAtUnread;
      _openAtUnread = false;
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
      } else if (left != null && !atUnread) {
        // Everything newer than that row is loaded on the way to it, the unread posts
        // among them: the divider goes on the first of them, below the reader.
        index = await search(
          () => _indexOf(t, left.chatId, (i) => i.rowId == left.rowId),
          pages: _openCap ~/ t.pageSize,
        );
        _initialAlignment = left.edge;
        if (index >= 0 && entering) _markFirstUnread(t);
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
          _markFirstUnread(t, again: atUnread);
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
          _repositioning = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && identical(t, _timeline) && _scrollCtl.isAttached) {
              _scrollCtl.jumpTo(
                index: at.clamp(0, t.items.length),
                alignment: alignment,
              );
            }
            // The jump is laid out in the next frame; its positions come after this.
            WidgetsBinding.instance
              ..addPostFrameCallback((_) => _repositioning = false)
              ..scheduleFrame();
          });
        }
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

  /// The official app's rule for a channel: a post is read once 80 % of it has been above
  /// the bottom edge of the screen, an album once all of it has. The list is reversed, so a
  /// row's leading edge is its bottom and its trailing edge its top, both measured from the
  /// bottom of the screen.
  static bool _readable(TimelineItem item, ItemPosition p) {
    final bottom = p.itemLeadingEdge;
    final top = p.itemTrailingEdge;
    if (top <= 0 || bottom >= 1) return false;
    if (item.parts.isNotEmpty) return bottom >= 0;
    return bottom + 0.2 * (top - bottom) >= 0;
  }

  /// Visible rows drive reading, the "at the newest post" flag, the position kept for the
  /// next visit and loading of older posts. The list is reversed: index 0 is the newest post
  /// at the bottom, and a row's leading edge is its bottom, measured from the viewport's
  /// bottom.
  void _onPositions() {
    final t = _timeline;
    final positions = _positions.itemPositions.value;
    if (t == null || positions.isEmpty || _opening || _repositioning) return;
    if (!_settled) {
      // First layout after opening.
      _settled = true;
      _settleAtNewest(positions);
    }
    final items = t.items;
    if (items.isEmpty) return;
    final divider = _firstUnread;
    var newest = positions.first;
    var oldestIndex = positions.first.index;
    var readIndex = -1;
    final viewed = <int, List<int>>{};
    for (final p in positions) {
      if (p.index < newest.index) newest = p;
      if (p.index > oldestIndex) oldestIndex = p.index;
      if (p.index >= items.length) continue;
      final item = items[p.index];
      if (!_dividerSeen && divider == (item.chatId, item.rowId)) {
        _dividerSeen = true;
      }
      if (_readable(item, p)) {
        if (readIndex < 0 || p.index < readIndex) readIndex = p.index;
        (viewed[item.chatId] ??= []).addAll(
          item.allPosts.map((x) => x.messageId),
        );
      }
    }
    final live = !t.anchored || t.exhaustedNewer;
    if (readIndex >= 0) {
      // The feed reads like one chat: everything older than the newest post read is read,
      // in every channel of it.
      final passed = t.passedAt(
        readIndex,
        throughNewest: readIndex == 0 && live && t.pendingNew == 0,
      );
      _marker.read(passed, viewed: viewed);
      Map<int, int>? moved;
      passed.forEach((chat, id) {
        if (id > (_marks[chat] ?? 0)) (moved ??= {..._marks})[chat] = id;
      });
      if (moved != null) {
        _marks = moved!;
        _corner.value++; // the unread count on the button
      }
    }
    // The list is reversed, so the row on top of the screen is the one with the highest
    // index: its day is what the floating pill names.
    _show(_stickyDay, _dayOf(items[oldestIndex.clamp(0, items.length - 1)]));
    if (newest.index < items.length) {
      final row = items[newest.index];
      _hereKnown = true;
      _here = (newest.index == 0 && live) || FeedTimeline.isUnread(row, _marks)
          ? null
          : SavedPosition(
              chatId: row.chatId,
              rowId: row.rowId,
              edge: newest.itemLeadingEdge,
            );
    }
    // Close to the newest loaded row of a jumped timeline: fetch the ones above it.
    if (t.anchored && !t.exhaustedNewer && newest.index <= 3) {
      unawaited(_loadNewer());
    }
    // A jumped timeline is only at the newest post once it has caught up with the live end.
    final atNewest =
        newest.index == 0 && newest.itemLeadingEdge >= -0.05 && live;
    if (atNewest != t.atTop) {
      t.atTop = atNewest;
      if (atNewest) _returnTo = null;
      if (atNewest && t.pendingNew > 0) {
        _release();
      } else {
        _corner.value++; // the button at the corner comes and goes
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
    // Nothing on the screen shows it: no rebuild until the new rows are there.
    _loading = true;
    try {
      await t.loadMore();
      _error = null;
    } on TelegramException catch (e) {
      _error = e.message;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Shows the posts that arrived while the reader was reading older ones. Reached by
  /// scrolling, the oldest of them comes into view; from the button, the list goes to its
  /// very end, as the official app's does.
  void _release({bool toEnd = false}) {
    final t = _timeline;
    if (t == null) return;
    final arrived = t.pendingNew;
    t.releasePending();
    setState(() {});
    if (!_scrollCtl.isAttached) return;
    final middle = !toEnd && arrived > 1;
    _scrollCtl.scrollTo(
      index: middle ? arrived - 1 : 0,
      alignment: middle ? 0.5 : 0,
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
      // The button at the corner comes back here before it goes to the newest post.
      _returnTo = (
        chatId: item.chatId,
        messageId: item.head.messageId,
        date: item.head.date,
      );
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

  /// A link in a post. A Telegram link to a channel the account follows opens here, post
  /// and all; everything else goes to whatever app handles it (the browser for web pages).
  Future<void> _openLink(String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.tryParse(url);
    if (uri != null && _openTelegramLink(uri)) return;
    if (await launchFirst([uri])) return;
    messenger.showSnackBar(SnackBar(content: Text('No app can open $url')));
  }

  /// The link path, for the test of H-18: answers whether the app opened it itself.
  @visibleForTesting
  bool openLinkForTest(String url) => _openTelegramLink(Uri.parse(url));

  /// True when the link named a channel of this account and its timeline was opened.
  bool _openTelegramLink(Uri uri) {
    final target = telegramTargetOf(uri);
    if (target == null) return false;
    final username = target.username?.toLowerCase();
    Channel? channel;
    for (final c in _known.values) {
      if (target.chatId != null && c.chatId == target.chatId) channel = c;
      if (username != null && (c.username ?? '').toLowerCase() == username) {
        channel = c;
      }
      if (channel != null) break;
    }
    if (channel == null) return false;
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TimelineScreen(
            db: widget.db,
            gateway: widget.gateway,
            channel: channel!,
            focusChatId: target.messageId == null ? null : channel.chatId,
            focusMessageId: target.messageId,
          ),
        ),
      ),
    );
    return true;
  }

  Uri? _shareLink(TimelineItem item) => telegramShareUri(
    chatId: item.chatId,
    messageId: item.head.messageId,
    username: _usernames[item.chatId],
  );

  /// The post as it goes out to another app: the channel, the words and the link. Used for
  /// one post and for a selection of them.
  String shareTextOf(TimelineItem item) {
    final link = _shareLink(item);
    final title = _titles[item.chatId] ?? '';
    return link == null
        ? item.text
        : shareText(channelTitle: title, text: item.head.text, link: link);
  }

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
      showTelegramError(messenger, e, what: 'Could not save the post.');
    }
  }

  /// Reactions the reader changed, shown at once, by post, with the list they were made
  /// from: once Telegram's update gives the post a new list, the post's own is shown again.
  final _optimistic = <(int, int), (List<Reaction>, List<Reaction>)>{};

  /// The reactions to draw for a post: the reader's change while Telegram has not answered.
  List<Reaction>? _reactionsOf(TimelineItem item) {
    final o = _optimistic[(item.chatId, item.head.messageId)];
    if (o == null || !identical(o.$1, item.head.reactions)) return null;
    return o.$2;
  }

  /// The reactions after the reader's tap: one reaction of one's own, as Telegram allows
  /// without Premium; its update corrects anything else.
  static List<Reaction> _toggled(
    List<Reaction> from,
    String emoji, {
    required bool remove,
  }) {
    final out = <Reaction>[];
    var found = false;
    for (final r in from) {
      final mine = r.emoji == emoji;
      found = found || mine;
      // Removing takes the reader's one away; adding moves it from any other emoji.
      final drop = mine ? remove : (r.chosen && !remove);
      final add = mine && !remove && !r.chosen;
      if (drop) {
        if (r.count > 1) out.add(Reaction(emoji: r.emoji, count: r.count - 1));
      } else if (add) {
        out.add(Reaction(emoji: r.emoji, count: r.count + 1, chosen: true));
      } else {
        out.add(r);
      }
    }
    if (!remove && !found) {
      out.add(Reaction(emoji: emoji, count: 1, chosen: true));
    }
    return out;
  }

  Future<void> _react(TimelineItem item, String emoji, bool remove) async {
    final messenger = ScaffoldMessenger.of(context);
    final key = (item.chatId, item.head.messageId);
    // A second tap before Telegram answered would undo the first.
    if (_reacting.contains(key)) return;
    _reacting.add(key);
    final shown = _reactionsOf(item) ?? item.head.reactions;
    setState(
      () => _optimistic[key] = (
        item.head.reactions,
        _toggled(shown, emoji, remove: remove),
      ),
    );
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
      if (mounted) setState(() => _optimistic.remove(key));
      showTelegramError(messenger, e, what: 'Could not send the reaction.');
    } finally {
      _reacting.remove(key);
    }
  }

  final _reacting = <(int, int)>{};

  /// The post each picture in the viewer came from, in the same order as the media.
  List<TimelineItem> _viewerOwners = const [];

  /// Every picture and video the timeline holds, newest first down to each album's last
  /// picture before its first (an album's head is its newest post): what the viewer pages
  /// through, so a tap on one picture walks the whole feed and not only its post. The post
  /// behind each one is kept, for the channel, the day, the caption and the actions.
  List<Media> _viewerMedia() {
    final media = <Media>[];
    final owners = <TimelineItem>[];
    for (final item in _timeline?.items ?? const <TimelineItem>[]) {
      final shown = MediaViewerScreen.viewable([
        for (final p in item.allPosts)
          if (p.media != null) p.media!,
      ]);
      media.addAll(shown);
      owners.addAll(List.filled(shown.length, item));
    }
    _viewerOwners = owners;
    return media;
  }

  /// What the viewer says about each picture.
  List<ViewerDetail> _viewerDetails() => [
    for (final item in _viewerOwners)
      ViewerDetail(
        channel: _titles[item.chatId] ?? '',
        date: item.head.date,
        caption: item.text,
        // The pictures of one post count among themselves ("2 of 3"), not among the
        // hundreds the feed holds.
        postKey: '${item.chatId}:${item.head.messageId}',
      ),
  ];

  void _viewerSave(int index) {
    if (index < _viewerOwners.length) {
      unawaited(_save(_viewerOwners[index]));
    }
  }

  /// The viewer reached the older end: one more page of posts, and all the media again.
  Future<List<Media>> _moreViewerMedia() async {
    await _loadMore();
    return _viewerMedia();
  }

  /// The viewer's list and its paging, for the test of H-21.
  @visibleForTesting
  List<Media> viewerMediaForTest() => _viewerMedia();

  @visibleForTesting
  Future<List<Media>> moreViewerMediaForTest() => _moreViewerMedia();

  /// Picks a row, or lets it go; the screen above follows the count and shows its own bar.
  void toggleSelected(TimelineItem item) {
    final id = (item.chatId, item.rowId);
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
    widget.onSelectionChanged?.call(_selected.length);
  }

  /// In a feed, a post's channel name opens that channel's info, as a name does in the
  /// official app. A channel the account no longer follows has none to show.
  VoidCallback? _channelInfoOf(int chatId) {
    if (widget.feed == null) return null;
    final channel = _known[chatId];
    if (channel == null) return null;
    return () => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ChannelInfoScreen(gateway: widget.gateway, channel: channel),
      ),
    );
  }

  void clearSelection() {
    if (_selected.isEmpty) return;
    setState(_selected.clear);
    widget.onSelectionChanged?.call(0);
  }

  /// The rows the reader picked, oldest first, as the actions want them.
  List<TimelineItem> get selectedItems {
    final items = _timeline?.items ?? const <TimelineItem>[];
    return [
      for (final i in items.reversed)
        if (_selected.contains((i.chatId, i.rowId))) i,
    ];
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
    final chosen = (_reactionsOf(item) ?? item.head.reactions).any(
      (r) => r.emoji == emoji && r.chosen,
    );
    await _react(item, emoji, chosen);
  }

  /// Emoji for the post menu; a failure is reported by the menu itself.
  /// The reactions a channel allows, asked once per channel: the menu opened a spinner
  /// on every long press while it asked again for a list that does not change.
  final _reactionsOfChat = <int, Future<List<String>>>{};

  Future<List<String>> _availableReactions(TimelineItem item) =>
      _reactionsOfChat[item.chatId] ??= widget.gateway.availableReactions(
        item.chatId,
        item.head.messageId,
      );

  @override
  void dispose() {
    _keepPosition();
    WidgetsBinding.instance.removeObserver(this);
    _positions.itemPositions.removeListener(_onPositions);
    _stickyHide?.cancel();
    _stickyDay.dispose();
    _stickyShown.dispose();
    _corner.dispose();
    _highlightTimer?.cancel();
    _events?.cancel();
    _sources?.cancel();
    _readStates?.cancel();
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
        ValueListenableBuilder<int>(
          valueListenable: _corner,
          builder: (context, _, _) => _cornerButton(context),
        ),
      ],
    );
  }

  /// The button to the newest posts, with the unread count on it.
  Widget _cornerButton(BuildContext context) {
    final t = _timeline;
    // No `_opening` here: the button would blink away and back every time the feed
    // is rebuilt (a changed filter, another channel).
    // Positioned even when away: a child of the stack without a position would size it.
    if (t == null || (t.atTop && !t.anchored)) {
      return const Positioned(right: 0, bottom: 0, child: SizedBox.shrink());
    }
    // Unread posts as Telegram counts them, and the ones that arrived meanwhile.
    final unread = t.unreadPosts(_marks) + t.pendingNew;
    return Positioned(
      right: 16,
      // Above the gesture bar: the app draws edge to edge.
      bottom: 16 + MediaQuery.paddingOf(context).bottom,
      // The accent colour, as the official app counts on its page-down button.
      child: Badge.count(
        count: unread,
        isLabelVisible: unread > 0,
        backgroundColor: Theme.of(context).colorScheme.primary,
        textColor: Theme.of(context).colorScheme.onPrimary,
        child: FloatingActionButton.small(
          heroTag: null,
          tooltip: t.pendingNew > 0
              ? '${t.pendingNew} new post${t.pendingNew == 1 ? '' : 's'}'
              : unread > 0
              ? '$unread unread post${unread == 1 ? '' : 's'}'
              : 'Newest posts',
          onPressed: _onDownButton,
          child: const Icon(Icons.keyboard_arrow_down),
        ),
      ),
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
        ? EmptyState(
            icon: Icons.rss_feed,
            title: 'This feed has no channels yet',
            message:
                'Add the channels it should collect; their posts then read as one '
                'timeline, oldest first.',
            actionLabel: 'Add channels',
            onAction: widget.onEditFeed,
          )
        : items.isEmpty && _error != null
        ? ErrorState(
            what: 'Could not load the posts.',
            message: _error,
            onRetry: _retryLoad,
          )
        : items.isEmpty
        ? Center(
            child: Text(
              _filter.isEmpty
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
                // when the rows end just short of it. After an error the Retry button
                // asks again, so a failure is not the end of the list.
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
                        ? ErrorState(
                            what: 'Could not load older posts.',
                            message: _error,
                            compact: true,
                            onRetry: () {
                              setState(() => _error = null);
                              unawaited(_loadMore());
                            },
                          )
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
              // The day goes above its first post: the row after this one is older.
              final day = _dayOf(item);
              final newDay =
                  i == items.length - 1 || _dayOf(items[i + 1]) != day;
              final tint = id == _highlight
                  ? Theme.of(context).colorScheme.primary
                        .withValues(alpha: 0.12)
                  : Colors.transparent;
              final inputs = _RowInputs(
                item,
                title: _titles[item.chatId] ?? '',
                photo: _photos[item.chatId],
                channel: _known[item.chatId],
                reactions: _reactionsOf(item),
                selecting: _selected.isNotEmpty,
                selected: _selected.contains(id),
                tint: tint,
                newDay: newDay,
                firstUnread: id == _firstUnread,
              );
              if (!identical(_rowsOf, t)) {
                _rows.clear();
                _rowsOf = t;
              }
              final kept = _rows[id];
              if (kept != null && kept.inputs.same(inputs)) return kept.row;
              final card = PostCard(
                item: item,
                channelTitle: _titles[item.chatId] ?? '',
                channelPhoto: _photos[item.chatId],
                gateway: widget.gateway,
                onOpenInTelegram: () => _openInTelegram(item),
                onShare: () => _share(item),
                onCopyLink: () => _copyLink(item),
                onCopyText: item.text.isEmpty ? null : () => _copyText(item),
                onSave: () => _save(item),
                onReact: (emoji, remove) => _react(item, emoji, remove),
                availableReactions: () => _availableReactions(item),
                onOpenLink: _openLink,
                onAutoplaySettings: () => openSettingsScreen(
                  context,
                  DataStorageScreen(db: widget.db, gateway: widget.gateway),
                ),
                onOpenForward: item.head.forwardedFrom == null
                    ? null
                    : () => _openForward(item),
                onOpenReply: item.textPost.replyTo == null
                    ? null
                    : () => _openReply(item),
                onOpenChannel: _channelInfoOf(item.chatId),
                reactions: _reactionsOf(item),
                onQuickReact: () => unawaited(_quickReact(item)),
                onViewerMedia: _viewerMedia,
                onMoreViewerMedia: _moreViewerMedia,
                onViewerDetails: _viewerDetails,
                onViewerSave: _viewerSave,
                onSelect: () => toggleSelected(item),
                selecting: _selected.isNotEmpty,
                selected: _selected.contains(id),
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
              // The tint fades in and out instead of appearing and vanishing, so the
              // eye follows the post the jump landed on.
              final row = RepaintBoundary(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  color: tint,
                  child: card,
                ),
              );
              final built = KeyedSubtree(
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
              _rows[id] = (inputs: inputs, row: built);
              return built;
            },
          );
  }
}

/// What a timeline row is drawn from. With the same inputs the screen hands the row widget
/// it built before back to the list, so a rebuild (a view count that changed, a page that
/// arrived, a post read) builds only the rows that changed instead of every row on the
/// screen. The item is mutable: its head and parts are compared one by one.
final class _RowInputs {
  _RowInputs(
    this.item, {
    required this.title,
    required this.photo,
    required this.channel,
    required this.reactions,
    required this.selecting,
    required this.selected,
    required this.tint,
    required this.newDay,
    required this.firstUnread,
  }) : head = item.head,
       parts = List.of(item.parts);
  final TimelineItem item;
  final Post head;
  final List<Post> parts;
  final String title;
  final FileRef? photo;
  final Channel? channel;
  final List<Reaction>? reactions;
  final bool selecting;
  final bool selected;
  final Color tint;
  final bool newDay;
  final bool firstUnread;

  bool same(_RowInputs o) {
    if (!identical(item, o.item) ||
        !identical(head, o.head) ||
        parts.length != o.parts.length) {
      return false;
    }
    for (var i = 0; i < parts.length; i++) {
      if (!identical(parts[i], o.parts[i])) return false;
    }
    return title == o.title &&
        photo == o.photo &&
        identical(channel, o.channel) &&
        identical(reactions, o.reactions) &&
        selecting == o.selecting &&
        selected == o.selected &&
        tint == o.tint &&
        newDay == o.newDay &&
        firstUnread == o.firstUnread;
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
      // Opaque: posts used to shine through the bar and through its words.
      color: scheme.surfaceContainerHighest,
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
