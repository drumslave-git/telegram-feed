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

import '../host/haptics.dart';
import '../host/viewing.dart';
import '../home/channel_info_screen.dart';
import '../home/connection_title.dart';
import '../l10n/l10n.dart';
import '../media/audio_session.dart';
import '../media/gallery.dart';
import '../media/media_viewer.dart';
import '../settings/data_storage_screen.dart' show DataStorageScreen;
import '../settings/settings_tiles.dart' show openSettingsScreen;
import '../widgets/destructive_button.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';
import 'calendar_screen.dart';
import 'feed_editor_screen.dart';
import 'open_links.dart';
import 'pinned_posts.dart';
import 'post_card.dart';
import '../host/secure_window.dart';
import 'read_marker.dart';
import 'recent_searches.dart';
import 'saved_position.dart';
import 'thread_screen.dart';
import 'timeline_search.dart';

export 'post_card.dart' show PostCard, UnreadDivider;

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
    this.savedMessages = false,
  }) : assert((feed == null) != (channel == null));
  final AppDatabase db;
  final TelegramGateway gateway;
  final Feed? feed;
  final Channel? channel;

  /// [channel] is the account's Saved Messages, whose posts can be deleted.
  final bool savedMessages;
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

  /// The running search; null until words were sent.
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

  /// Whether this timeline is the screen in front.
  bool _inFront = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Told again whenever another screen covers this one or uncovers it.
    _inFront = ModalRoute.of(context)?.isCurrent ?? true;
    _tellViewing();
  }

  /// Says which channels are on screen, so a post that matches a rule here only
  /// sounds instead of popping up over the timeline it has just appeared in.
  void _tellViewing() {
    if (_inFront) {
      Viewing.show(this, _sources.chatIds);
    } else {
      Viewing.hide(this);
    }
  }

  @override
  void dispose() {
    Viewing.hide(this);
    _queryCtl.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  void _onSources(TimelineSources sources) {
    if (!mounted) return;
    setState(() => _sources = sources);
    _tellViewing();
    // A search that started before the sources were known covers them now.
    final session = _session;
    if (session != null && session.chatIds.length != sources.chatIds.length) {
      unawaited(_startSearch(session.query, asList: _listOpen));
    }
  }

  /// The search opens over the timeline, which stays where it is until words are sent:
  /// only the words searched for last cover it, while nothing is typed.
  void _openSearch() {
    setState(() {
      _searchOpen = true;
      _listOpen = false;
    });
    unawaited(_loadRecent());
  }

  /// Opens the search with [words] in it and lists what has them, as a tap on a hashtag
  /// does in the official app.
  void _searchFor(String words) {
    _openSearch();
    _queryCtl.text = words;
    unawaited(_startSearch(words, asList: true));
  }

  Future<void> _loadRecent() async {
    final words = await RecentSearches(widget.db).load();
    if (mounted) setState(() => _recent = words);
  }

  void _closeSearch() {
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
    setState(() => _searchFilter = filter);
    // A kind of post is looked through as a list.
    unawaited(_startSearch(_queryCtl.text, asList: true));
  }

  /// The words in the field changed. Nothing is searched until they are sent, as in the
  /// official app; a field that was emptied drops what the last search found.
  void _onQuery(String value) {
    setState(() {
      if (value.trim().isEmpty && _searchFilter == HistoryFilter.any) {
        _session = null;
        _listOpen = false;
        _current = -1;
      }
    });
  }

  /// Runs the search for [value]. The timeline goes to the newest post that has the
  /// words at once, with the bar to step through the others; [asList] shows what was
  /// found as a list instead.
  Future<void> _startSearch(String value, {bool asList = false}) async {
    final query = value.trim();
    // A kind of post on its own is a search too: "every video of this feed".
    if (query.isEmpty && _searchFilter == HistoryFilter.any) {
      setState(() {
        _session = null;
        _listOpen = false;
        _current = -1;
      });
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
      _listOpen = asList;
      _current = -1;
    });
    await session.loadMore();
    if (!mounted || !identical(_session, session)) return;
    setState(() {});
    if (!asList && session.results.isNotEmpty) await _openResult(0);
  }

  /// "Show as list" and "Show as chat" of the bar under the search.
  void _toggleList() => setState(() => _listOpen = !_listOpen);

  /// Back, on the screen or of the phone: out of the list of results to the post that is
  /// open under it, and only then out of the search.
  void _backFromSearch() {
    if (_listOpen && _current >= 0) {
      setState(() => _listOpen = false);
    } else {
      _closeSearch();
    }
  }

  Future<void> _loadMoreResults() async {
    final session = _session;
    if (session == null) return;
    final changed = await session.loadMore();
    if (changed && mounted && identical(_session, session)) setState(() {});
  }

  Future<void> _rememberQuery(String query) async {
    if (query.trim().isEmpty) return;
    final words = await RecentSearches(widget.db).remember(query);
    if (mounted) setState(() => _recent = words);
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
      // Words are worth offering again once they led somewhere: what was typed on the way
      // to them is not kept.
      unawaited(_rememberQuery(session.query));
      _queryFocus.unfocus();
      setState(() {
        _current = index;
        _listOpen = false;
      });
      await keyboardGone(context);
      if (!mounted || !identical(_session, session)) return;
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
  PreferredSizeWidget _selectionBar(AppLocalizations l10n) => AppBar(
    leading: IconButton(
      tooltip: l10n.commonCancel,
      icon: const Icon(Icons.close),
      onPressed: () => _view.currentState?.clearSelection(),
    ),
    title: Text(l10n.timelineSelectedCount(_selected)),
    actions: [
      // A post of a channel that protects its content is not copied, shared or saved, so
      // a selection that holds one offers none of the three.
      if (!_picked.any((i) => i.isProtected)) ...[
        IconButton(
          tooltip: l10n.timelineCopyText,
          icon: const Icon(Icons.content_copy),
          onPressed: () => unawaited(_copySelected()),
        ),
        if (!widget.savedMessages) ...[
          IconButton(
            tooltip: l10n.commonShare,
            icon: const Icon(Icons.share),
            onPressed: () => unawaited(_shareSelected()),
          ),
          IconButton(
            tooltip: l10n.timelineSaveToSavedMessages,
            icon: const Icon(Icons.bookmark_add_outlined),
            onPressed: () => unawaited(_saveSelected()),
          ),
        ],
      ],
      if (widget.savedMessages)
        IconButton(
          tooltip: l10n.commonDelete,
          icon: const Icon(Icons.delete_outline),
          onPressed: () => unawaited(_view.currentState?.deletePosts(_picked)),
        ),
    ],
  );

  List<TimelineItem> get _picked =>
      _view.currentState?.selectedItems ?? const [];

  Future<void> _copySelected() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final items = _picked;
    final text = [
      for (final i in items)
        if (i.text.isNotEmpty) i.text,
    ].join(String.fromCharCode(10) + String.fromCharCode(10));
    await Clipboard.setData(ClipboardData(text: text));
    _view.currentState?.clearSelection();
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.timelinePostsCopied(items.length))),
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
    final l10n = context.l10n;
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
        SnackBar(content: Text(l10n.timelinePostsSaved(items.length))),
      );
    } on TelegramException catch (e) {
      showTelegramError(messenger, e, what: l10n.timelineSavePostsFailed);
    }
  }

  PreferredSizeWidget _appBar(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    if (_selected > 0) return _selectionBar(l10n);
    if (_searchOpen) {
      return AppBar(
        leading: BackButton(onPressed: _backFromSearch),
        titleSpacing: 0,
        title: TextField(
          controller: _queryCtl,
          focusNode: _queryFocus,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: l10n.searchPostsHint,
            border: InputBorder.none,
          ),
          onChanged: _onQuery,
          onSubmitted: (value) => unawaited(_startSearch(value)),
        ),
        actions: [
          if (_queryCtl.text.isNotEmpty)
            IconButton(
              tooltip: l10n.commonClear,
              icon: const Icon(Icons.close),
              onPressed: () {
                _queryCtl.clear();
                _onQuery('');
              },
            ),
          IconButton(
            tooltip: l10n.timelineJumpToDate,
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
                    builder: (info) => ChannelInfoScreen(
                      gateway: widget.gateway,
                      channel: channel,
                      onShowInChat: (post) {
                        Navigator.of(info).pop();
                        unawaited(
                          _view.currentState?.jumpToPost(
                            chatId: post.chatId,
                            messageId: post.messageId,
                            date: post.date,
                          ),
                        );
                      },
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
                        l10n.timelineSubscribers(
                          channel.memberCount,
                          formatCount(channel.memberCount),
                        ),
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
          tooltip: l10n.commonSearch,
          icon: const Icon(Icons.search),
          onPressed: _openSearch,
        ),
        if (widget.feed != null)
          IconButton(
            tooltip: l10n.timelineEditFeed,
            icon: const Icon(Icons.tune),
            onPressed: _openFeedEditor,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    // What covers the timeline while the search is open: the results as a list, or,
    // before anything was typed, the words searched for last.
    final covered =
        _searchOpen &&
        (_listOpen ||
            (session == null &&
                _queryCtl.text.trim().isEmpty &&
                _recent.isNotEmpty));
    return PopScope(
      canPop: _selected == 0 && !_searchOpen,
      // Back first leaves the selection, then the search, as in the official app.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_selected > 0) {
          _view.currentState?.clearSelection();
        } else {
          _backFromSearch();
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
                  removeBottom: _searchOpen && session != null,
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
                        savedMessages: widget.savedMessages,
                        focusChatId: widget.focusChatId,
                        focusMessageId: widget.focusMessageId,
                        share: widget.share,
                        onSources: _onSources,
                        onHashtag: _searchFor,
                        highlight: _searchOpen ? session?.query : null,
                        onEditFeed: widget.feed == null
                            ? null
                            : _openFeedEditor,
                      ),
                      if (covered)
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
                              kind: _searchFilter,
                              searched: session != null,
                              loading: session?.loading ?? false,
                              exhausted: session?.exhausted ?? false,
                              total: session?.total ?? -1,
                              error: session?.error,
                              current: _current,
                              recent: _recent,
                              onRecent: (words) {
                                _queryCtl.text = words;
                                _queryFocus.unfocus();
                                unawaited(_startSearch(words));
                              },
                              onRemoveRecent: (words) async {
                                final left = await RecentSearches(widget.db)
                                    .remove(words);
                                if (mounted) setState(() => _recent = left);
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
            if (_searchOpen && session != null)
              SearchStepper(
                current: _current,
                total: session.total,
                loading:
                    _jumping || (session.loading && session.results.isEmpty),
                listShown: _listOpen,
                onToggleList: session.results.isEmpty ? null : _toggleList,
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
    this.onHashtag,
    this.highlight,
    this.savedMessages = false,
  }) : assert((feed == null) != (channel == null));
  final AppDatabase db;
  final TelegramGateway gateway;

  /// [channel] is the account's Saved Messages: the post menu offers Delete.
  final bool savedMessages;

  /// Reports the channels, the filter and the photos as they are loaded, for the search.
  /// The words of the search that is open: they are marked in the posts.
  final String? highlight;
  final ValueChanged<TimelineSources>? onSources;

  /// How many rows are picked, so the screen can put up the selection bar.
  final ValueChanged<int>? onSelectionChanged;

  /// Opens the feed's channels; the button an empty feed offers. Null for a channel.
  final VoidCallback? onEditFeed;

  /// A hashtag in a post was tapped: the screen searches its posts for it.
  final void Function(String tag)? onHashtag;

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

  /// Minimized rows the reader opened in this visit, by (chat id, row id).
  final _opened = <(int, int)>{};

  /// A row the filter leaves out that is drawn as its one line: not opened by the reader.
  bool _folded(TimelineItem item) =>
      item.minimized && !_opened.contains((item.chatId, item.rowId));

  /// The channel's pinned posts, newest first, shown one at a time in a bar over the
  /// timeline. A feed mixes channels, so it has no such bar.
  List<Post> _pins = const [];

  /// The newest pinned post at the moment the reader hid the bar: the bar stays away until
  /// a newer post is pinned, as in the official app. Kept in the settings.
  int _pinsHiddenAt = 0;

  bool get _pinsShown =>
      _pins.isNotEmpty && _pins.first.messageId != _pinsHiddenAt;

  /// Done once the channel's pinned posts are known. An opening waits for it a moment:
  /// where the list opens depends on whether the bar covers its top.
  Future<void> _pinsLoaded = Future.value();

  /// Where the bottom edge of a row goes so that the next row (with its day label or the
  /// "Unread posts" divider) starts just under the top of the list, or under the pinned
  /// bar when there is one. A share of the list's height, measured from its bottom.
  double get _underTop {
    const open = 0.92;
    if (!_pinsShown) return open;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || box.size.height <= 0) return open;
    return open - pinnedBarHeight / box.size.height;
  }

  /// The pinned post the bar shows, as an index into [_pins].
  final _pinIndex = ValueNotifier<int>(0);

  /// The pinned post the list stands at: the newest one that is not newer than the newest
  /// post on the screen, or the oldest when the reader is above them all.
  int _pinByScroll = 0;

  /// After a tap on the bar it moves on to the next older pinned post (from the oldest back
  /// to the newest) wherever the list stands, until the reader scrolls on.
  int? _pinForced;

  void _showPinAt(int newestVisibleId) {
    if (_pins.isEmpty) return;
    var at = _pins.indexWhere((p) => p.messageId <= newestVisibleId);
    if (at < 0) at = _pins.length - 1;
    _pinByScroll = at;
    _show(_pinIndex, _pinForced ?? at);
  }

  /// The reader's own scroll lets go of the pin a tap moved the bar to: at once towards
  /// the newest posts and after the wrap to the newest pin, and towards older posts once
  /// the list is past that pin, as in the official app.
  void _followScrollForPin(double towardsNewest) {
    final forced = _pinForced;
    if (forced == null) return;
    if (towardsNewest > 0 || forced == 0 || _pinByScroll > forced) {
      _pinForced = null;
      _show(_pinIndex, _pinByScroll);
    }
  }

  /// A tap on the bar: to the post it shows, and the bar moves on to the next older one.
  void _onPinnedTap() {
    final at = _pinIndex.value.clamp(0, _pins.length - 1);
    final pin = _pins[at];
    _pinForced = at == _pins.length - 1 ? 0 : at + 1;
    _pinIndex.value = _pinForced!;
    unawaited(
      jumpToPost(chatId: pin.chatId, messageId: pin.messageId, date: pin.date),
    );
  }

  String get _pinsHiddenKey =>
      SettingKeys.pinsHiddenOfChat(widget.channel!.chatId);

  /// Puts the bar away until a newer post is pinned, and offers to take that back.
  void _hidePinned() {
    if (_pins.isEmpty) return;
    final before = _pinsHiddenAt;
    final l10n = context.l10n;
    setState(() => _pinsHiddenAt = _pins.first.messageId);
    unawaited(widget.db.setSetting(_pinsHiddenKey, '$_pinsHiddenAt'));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.pinnedPostsHidden),
          action: SnackBarAction(
            label: l10n.commonUndo,
            onPressed: () {
              if (!mounted) return;
              setState(() => _pinsHiddenAt = before);
              unawaited(
                before == 0
                    ? widget.db.deleteSetting(_pinsHiddenKey)
                    : widget.db.setSetting(_pinsHiddenKey, '$before'),
              );
            },
          ),
        ),
      );
  }

  /// The list of pinned posts: a post picked there is jumped to, and its button hides the
  /// bar.
  Future<void> _openPinnedList() async {
    final channel = widget.channel!;
    final picked = await Navigator.of(context).push<Object>(
      MaterialPageRoute(
        builder: (_) => PinnedPostsScreen(
          pins: _pins,
          channelTitle: _titles[channel.chatId] ?? channel.title,
          channelPhoto: _photos[channel.chatId],
          gateway: widget.gateway,
        ),
      ),
    );
    if (!mounted) return;
    if (picked == true) {
      _hidePinned();
    } else if (picked is Post) {
      // The bar names the post the list went to, like any place the reader scrolls to.
      _pinForced = null;
      unawaited(
        jumpToPost(
          chatId: picked.chatId,
          messageId: picked.messageId,
          date: picked.date,
        ),
      );
    }
  }

  /// Emoji a double tap sends; the reader's last one, a thumbs up until they react once.
  /// Read once when the timeline opens and kept up to date by reacting here: watching the
  /// setting would tie every channel timeline to a database stream it otherwise never needs.
  String _quick = defaultQuickReaction;
  StreamSubscription<String?>? _quickSub;

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
    _shown.add(this);
    _focusChat = widget.focusChatId;
    _focusMessage = widget.focusMessageId;
    _positions.itemPositions.addListener(_onPositions);
    WidgetsBinding.instance.addObserver(this);
    _readStates = widget.gateway.readUpdates.listen(_onReadState);
    // The quick reaction is chosen in Chat settings, and may be chosen anew while this
    // timeline is up underneath.
    _quickSub = widget.db.watchSetting(SettingKeys.quickReaction).listen((
      emoji,
    ) {
      if (!mounted) return;
      final next = emoji == null || emoji.isEmpty
          ? defaultQuickReaction
          : emoji;
      if (next != _quick) setState(() => _quick = next);
    });
    if (widget.channel != null) _pinsLoaded = _loadPinned();
    final feed = widget.feed;
    if (feed == null) {
      final c = widget.channel!;
      _photos = {c.chatId: c.photo};
      _marks = {c.chatId: c.lastReadMessageId};
      _setSources([(chatId: c.chatId, title: c.title, username: c.username)]);
      unawaited(_loadKnown());
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
  /// The channels the account follows, for a single channel's timeline: links, the
  /// forwarded-from line and reply quotes lead to them.
  Future<void> _loadKnown() async {
    try {
      final channels = await widget.gateway.myChannels();
      if (mounted) _known = {for (final c in channels) c.chatId: c};
    } on TelegramException {
      // Links then go to the app that handles them.
    }
  }

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
  /// Telegram's own count of the unread posts of each source, as its read state says.
  final _telegramUnread = <int, int>{};

  Future<Map<int, int>> _loadMarks() async {
    final ids = [for (final s in _sourceRows) s.chatId];
    Future<int> of(int chatId) async {
      try {
        final state = await widget.gateway.readState(chatId);
        _telegramUnread[chatId] = state.unreadCount;
        return state.lastReadMessageId;
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
    _telegramUnread[r.chatId] = r.unreadCount;
    if (r.lastReadMessageId <= (_marks[r.chatId] ?? 0)) return;
    setState(() => _marks = {..._marks, r.chatId: r.lastReadMessageId});
  }

  /// The app is in the background (or its window is covered whole): nothing on the screen
  /// is being read.
  bool _away = false;

  /// The first post that arrived during this absence. It gets the "Unread posts" divider,
  /// as in the official app, which drops the divider it had and puts a new one above the
  /// first message that comes in while it is paused.
  (int, int)? _awayDivider;

  /// The reader stood at the newest post when that post arrived: the list goes back to the
  /// divider when the app returns. A reader further up stays where they are.
  bool _awayAtNewest = false;

  void _dividerWhileAway(FeedTimeline t, Post post) {
    if (_awayDivider != null) return;
    final row = (
      post.chatId,
      post.albumId != 0 ? post.albumId : post.messageId,
    );
    _awayDivider = row;
    _awayAtNewest = t.atTop;
    setState(() {
      _firstUnread = row;
      _dividerSeen = false;
    });
  }

  // Leaving the app is leaving the timeline, as far as its position goes: the official app
  // keeps a chat's position when it pauses.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _keepPosition();
    final away =
        state == AppLifecycleState.paused || state == AppLifecycleState.hidden;
    if (away == _away || state == AppLifecycleState.inactive) return;
    _away = away;
    if (away) return;
    final divider = _awayDivider;
    _awayDivider = null;
    final t = _timeline;
    if (t == null || !_scrollCtl.isAttached || !t.atTop) return;
    final index = divider == null || !_awayAtNewest
        ? -1
        : t.items.indexWhere((i) => (i.chatId, i.rowId) == divider);
    // What the list reports until it stands where it belongs is not what the reader sees.
    _repositioning = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(t, _timeline) && _scrollCtl.isAttached) {
        if (index >= 0) {
          // As when the timeline opens at unread posts: the row above the divider just
          // below the top, and the newest post at the bottom when the new ones do not
          // fill the screen.
          _scrollCtl.jumpTo(index: index + 1, alignment: _underTop);
          _settled = false;
        } else {
          _scrollCtl.jumpTo(index: 0, alignment: 0);
        }
      }
      WidgetsBinding.instance
        ..addPostFrameCallback((_) => _repositioning = false)
        ..scheduleFrame();
    });
    WidgetsBinding.instance.scheduleFrame();
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
      final waiting = t.pendingNew;
      final changed = t.apply(e);
      if (e is PostAdded &&
          _away &&
          (t.items.length > before || t.pendingNew > waiting)) {
        _dividerWhileAway(t, e.post);
      }
      if (changed) {
        setState(() {});
      } else if (e is PostAdded) {
        _corner.value++; // held back while the reader is further up: the button counts it
      }
      // A row added at the newest end shifts every index; stay glued to the newest post.
      // While the app is away the list is put right when it comes back.
      if (!_away && t.atTop && t.items.length > before) _jumpToNewest();
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

  /// Whether the focus post was already looked for around its own date.
  bool _focusSought = false;

  /// When a post was posted, asked of Telegram; null when the post is not there.
  Future<int?> _dateOf(int chatId, int messageId) async {
    try {
      final posts = await widget.gateway.history(
        chatId,
        fromMessageId: messageId + 1,
        limit: 1,
      );
      return posts.firstOrNull?.messageId == messageId
          ? posts.first.date
          : null;
    } on TelegramException {
      return null;
    }
  }

  /// Opens the timeline around one post, the way the official app opens a search result or
  /// a date: every source starts at its newest post up to that moment, the post itself is
  /// the anchor of its own channel, and the list can page both ways from there.
  Future<void> jumpToPost({
    required int chatId,
    required int messageId,
    required int date,
  }) async {
    final t = _timeline;
    final loaded = t == null || _opening
        ? -1
        : _indexOf(
            t,
            chatId,
            (i) => i.allPosts.any((p) => p.messageId == messageId),
          );
    if (t != null && loaded >= 0) {
      await _scrollToLoaded(t, loaded);
      return;
    }
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

  static const _jumpScroll = Duration(milliseconds: 250);

  /// Scrolls to a row that is already loaded, as the official app does when the message
  /// it jumps to is in its list: animated, the row in the middle of the screen, tinted.
  Future<void> _scrollToLoaded(FeedTimeline t, int index) async {
    if (!_scrollCtl.isAttached) return;
    final row = (t.items[index].chatId, t.items[index].rowId);
    // A minimized post opens: the reader asked for that post.
    setState(() {
      _opened.add(row);
      _highlightTimer?.cancel();
      _highlight = row;
    });
    // The list is measured once this frame has laid it out: the row may have opened, and
    // a search bar that closed on the way here has changed the list's height.
    await WidgetsBinding.instance.endOfFrame;
    // Rows that load on the way move every index: the row is looked up again each time.
    int here() => !mounted || !identical(t, _timeline) || !_scrollCtl.isAttached
        ? -1
        : t.items.indexWhere((i) => (i.chatId, i.rowId) == row);
    var at = here();
    if (at < 0) return;
    var top = _centredTop(at);
    if (top == null) {
      // Not laid out, so its height is not known: its top goes a quarter down the screen,
      // and the row is centred once it is there.
      await _scrollCtl.scrollTo(
        index: at + 1,
        alignment: 0.75,
        duration: _jumpScroll,
        curve: Curves.easeOut,
      );
      // Where the row stands is told after the frame that put it there.
      if (mounted) await WidgetsBinding.instance.endOfFrame;
      at = here();
      if (at < 0) return;
      top = _centredTop(at);
    }
    if (top != null) {
      final end = _endsAtNewest(at, top);
      // A row near the newest post cannot be centred: the list goes to its end, and
      // stays as it is when it is there already.
      if (end) {
        if (!t.atTop) await _scrollToEnd();
      } else {
        await _scrollCtl.scrollTo(
          index: at + 1,
          alignment: top,
          duration: _jumpScroll,
          curve: Curves.easeOut,
        );
      }
    }
    if (mounted && _highlight == row) _flash(row);
  }

  /// Where the top edge of the row at [index] belongs so that the row stands in the middle
  /// of the list (of what the pinned bar leaves of it), or with its top at the top when it
  /// is taller than that: `getScrollOffsetForMessage` of the official app. A share of the
  /// list's height, measured from its bottom; null while the row is not laid out.
  double? _centredTop(int index) {
    // The render box, not the element: a rebuild that waits for its frame marks the list
    // dirty, and the element will not tell its size then.
    final box = _listKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    final height = box.size.height;
    if (height <= 0) return null;
    for (final p in _positions.itemPositions.value) {
      if (p.index != index) continue;
      final covered = _pinsShown ? pinnedBarHeight : 0.0;
      final free = 1 - covered / height;
      final row = p.itemTrailingEdge - p.itemLeadingEdge;
      return math.min(free, (free + row) / 2);
    }
    return null;
  }

  /// True when the row at [index] with its top at [top] would lift the newest post off the
  /// bottom edge and leave the list empty under it: the list belongs at its end then.
  bool _endsAtNewest(int index, double top) {
    ItemPosition? row;
    ItemPosition? newest;
    for (final p in _positions.itemPositions.value) {
      if (p.index == index) row = p;
      if (p.index == 0) newest = p;
    }
    if (row == null || newest == null) return false;
    return newest.itemLeadingEdge + top - row.itemTrailingEdge > 0;
  }

  /// A timeline that was opened around a post: the post is centred as soon as the list has
  /// laid it out and its height is known.
  int? _centreOnOpen;

  /// Opens the calendar and jumps to the day the reader picks, as in the official app.
  /// Asks for a day and goes there; true when one was picked. [onPicked] runs first,
  /// before the jump, so the search can close only when the reader did pick a day.
  Future<bool> pickDate({DateTime? around, VoidCallback? onPicked}) async {
    final picked = await Navigator.of(context).push<DateTime>(
      MaterialPageRoute(
        builder: (_) => CalendarScreen(
          gateway: widget.gateway,
          chatIds: [for (final s in _sourceRows) s.chatId],
          around: around,
        ),
      ),
    );
    if (picked == null || !mounted) return false;
    onPicked?.call();
    await jumpToDate(picked);
    return true;
  }

  /// A tap on the floating date: to the first post of that day, as in the official app.
  /// A day whose first post is loaded is scrolled to; any other opens the timeline there.
  Future<void> jumpToDayStart(DateTime day) async {
    final t = _timeline;
    if (t != null && !_opening && _scrollCtl.isAttached) {
      final items = t.items;
      // The list runs from the newest post: the last row of the day is its first post.
      var first = -1;
      for (var i = 0; i < items.length; i++) {
        if (_dayOf(items[i]) == day) first = i;
      }
      // Its first post for certain only when an older row is loaded too.
      if (first >= 0 && (first + 1 < items.length || t.exhausted)) {
        // As an opening at a day: the row above the day's pill just below the top.
        await _scrollCtl.scrollTo(
          index: first + 1,
          alignment: _underTop,
          duration: _jumpScroll,
          curve: Curves.easeOut,
        );
        return;
      }
    }
    await jumpToDate(day);
  }

  /// Opens the timeline at a day: every source starts at its newest post of that day (or
  /// the newest older one), and the list settles on the first post of the day.
  Future<void> jumpToDate(DateTime day) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final end = DateTime(day.year, day.month, day.day, 23, 59, 59);
    Map<int, int> anchors;
    try {
      anchors = await anchorsForDate(widget.gateway, [
        for (final s in _sourceRows) s.chatId,
      ], end.millisecondsSinceEpoch ~/ 1000);
    } on TelegramException catch (e) {
      showTelegramError(messenger, e, what: l10n.timelineJumpToDayFailed);
      return;
    }
    if (!mounted) return;
    if (anchors.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l10n.timelineNothingFromDay(formatDay(day, l10n: l10n)),
          ),
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
      int find() => t.items.indexWhere((x) => (x.chatId, x.rowId) == divider);
      var i = find();
      if (i < 0 && !t.anchored && t.hasPending) {
        // The divider stands on a post that arrived while the app was away and still
        // waits behind this button: the posts come in, and the list goes to the divider.
        t.releasePending();
        setState(() {});
        i = find();
      }
      if (i >= 0 && _scrollCtl.isAttached) {
        unawaited(_scrollToDivider(i));
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

  /// As when the timeline opens at unread posts: the row above the divider just below the
  /// top, or the list at its end when the unread posts do not fill the screen.
  Future<void> _scrollToDivider(int index) async {
    if (_endsAtNewest(index, _underTop)) return _scrollToEnd();
    await _scrollCtl.scrollTo(
      index: index + 1,
      alignment: _underTop,
      duration: _jumpScroll,
      curve: Curves.easeOut,
    );
    // Rows that were not laid out before the scroll tell only now how much they fill.
    if (!mounted || !_scrollCtl.isAttached) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_scrollCtl.isAttached) return;
    final gap = _positions.itemPositions.value.any(
      (p) => p.index == 0 && p.itemLeadingEdge > 0.03,
    );
    if (gap) await _scrollToEnd();
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

  /// The timeline was rebuilt around its oldest unread post ([_reopenAtOldestUnread]).
  bool _atOldestUnread = false;

  /// The oldest unread post of the sources: per source the post after its read mark, and
  /// of those the earliest. A source Telegram has no read mark for is left out.
  Future<Post?> _oldestUnread() async {
    Post? oldest;
    await Future.wait([
      for (final s in _sourceRows)
        if ((_marks[s.chatId] ?? 0) > 0 && (_telegramUnread[s.chatId] ?? 0) > 0)
          widget.gateway
              .historyAfter(
                s.chatId,
                afterMessageId: _marks[s.chatId]!,
                limit: 1,
              )
              .then((after) {
                if (after.isEmpty) return;
                final post = after.last;
                final o = oldest;
                if (o == null ||
                    post.date < o.date ||
                    (post.date == o.date && post.chatId < o.chatId)) {
                  oldest = post;
                }
              }),
    ]);
    return oldest;
  }

  /// Builds the timeline anew around its oldest unread post: that post anchors its own
  /// channel and the others start at their newest post up to that moment, as for a jump
  /// to a post. False when no such post is known, and the timeline [t] goes on opening.
  Future<bool> _reopenAtOldestUnread(FeedTimeline t) async {
    final first = await _oldestUnread();
    if (first == null || !mounted || !identical(t, _timeline)) return false;
    final others = [
      for (final s in _sourceRows)
        if (s.chatId != first.chatId) s.chatId,
    ];
    final anchors = {
      if (others.isNotEmpty)
        ...await anchorsForDate(widget.gateway, others, first.date),
      first.chatId: first.messageId,
    };
    if (!mounted || !identical(t, _timeline)) return false;
    _focusChat = null;
    _focusMessage = null;
    _focusDay = null;
    _anchors = anchors;
    _atOldestUnread = true;
    _timeline = null;
    _setSources(_sourceRows);
    return true;
  }

  /// Loads the first rows and decides where the list opens, as the official app opens a
  /// chat: the post a notification asked for; else where the reader left the timeline
  /// scrolled up; else the first unread post under the divider; else the newest post.
  Future<void> _open(FeedTimeline t, {bool reposition = false}) async {
    setState(() => _loading = true);
    try {
      _marks = await _loadMarks();
      await _pinsLoaded.timeout(
        const Duration(seconds: 2),
        onTimeout: () {}, // the bar comes when it comes
      );
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
          _initialAlignment = _underTop;
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
        if (index < 0 && !t.anchored && !_focusSought) {
          // Older than an opening loads (a file from the shared media, a post a link
          // names): the timeline opens around the post itself, as it does for a search
          // result. Asked for once: a post that is gone leaves the timeline where it
          // would have opened.
          _focusSought = true;
          final date = await _dateOf(focusChat, focusMessage);
          if (!mounted) return;
          if (date != null) {
            await jumpToPost(
              chatId: focusChat,
              messageId: focusMessage,
              date: date,
            );
            return;
          }
        }
        if (t.anchored && index >= 0) {
          // One page of newer posts above the post, so it stands in its surroundings and
          // the list does not run on towards the newest end by itself.
          await t.loadNewer();
          index = _indexOf(t, focusChat, isFocus);
          _flash((focusChat, t.items[index].rowId));
        }
        if (index >= 0) {
          // A minimized post opens: the reader asked for that post.
          _opened.add((focusChat, t.items[index].rowId));
          // The top of the post (the bottom of the row above it) a quarter down the
          // screen; the first layout tells its height, and it is centred.
          _centreOnOpen = index;
          index += 1;
          _initialAlignment = 0.75;
        }
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
        var again = atUnread;
        if (t.anchored && _atOldestUnread) {
          // Opened around the oldest unread post: the unread ones are the newer rows, and
          // a filter may leave the first pages of them out.
          _atOldestUnread = false;
          again = true;
          for (
            var page = 0;
            page < 10 &&
                !t.exhaustedNewer &&
                (page == 0 || t.firstUnreadIndex(_marks) < 0);
            page++
          ) {
            await t.loadNewer();
          }
        } else {
          // More unread posts than an opening loads: the rows down to the first of them
          // are not all fetched, the timeline opens around that post, as the official
          // app loads a chat around its first unread message. A filter shows fewer rows
          // than Telegram counts posts, so with one the rows are loaded and counted.
          final far =
              !t.anchored &&
              _filter.isEmpty &&
              t.chatIds.fold(0, (n, id) => n + (_telegramUnread[id] ?? 0)) >
                  _openCap;
          Future<void> loadToMarks() async {
            while (!t.reachedMarks(_marks) &&
                !t.exhausted &&
                t.items.length < _openCap) {
              await t.loadMore();
            }
          }

          if (!far) await loadToMarks();
          if (!t.anchored && (far || !t.reachedMarks(_marks) && !t.exhausted)) {
            if (await _reopenAtOldestUnread(t)) return;
          }
          if (far) await loadToMarks();
        }
        final unread = t.firstUnreadIndex(_marks);
        if (unread < 0) {
          index = 0;
          _initialAlignment = 0;
        } else {
          _markFirstUnread(t, again: again);
          // The divider sits on top of the first unread row. The list can only be aligned
          // by a row's bottom edge, so the row above it (older, or the footer) is put
          // just below the top of the screen.
          index = unread + 1;
          _initialAlignment = _underTop;
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
        _cornerByScroll = _initialIndex > 0 || _initialAlignment != 0;
        _scrolled = 0;
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
    if (t == null || positions.isEmpty || _opening || _repositioning || _away) {
      return;
    }
    if (!_settled) {
      // First layout after opening.
      _settled = true;
      final centre = _centreOnOpen;
      _centreOnOpen = null;
      final top = centre == null ? null : _centredTop(centre);
      if (top != null && !_endsAtNewest(centre!, top)) {
        if (_scrollCtl.isAttached) {
          _scrollCtl.jumpTo(index: centre + 1, alignment: top);
        }
      } else {
        _settleAtNewest(positions);
      }
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
      // Every post on the screen counts a view, as in the official app: an older one
      // scrolled back to, and one not yet far enough in to be read. A minimized line is
      // read with the rest, but its post has not been seen.
      if (!_folded(item)) {
        (viewed[item.chatId] ??= []).addAll(
          item.allPosts.map((x) => x.messageId),
        );
      }
      if (_readable(item, p)) {
        if (readIndex < 0 || p.index < readIndex) readIndex = p.index;
      }
    }
    final live = !t.anchored || t.exhaustedNewer;
    if (readIndex >= 0) {
      // The feed reads like one chat: everything older than the newest post read is read,
      // in every channel of it.
      final passed = t.passedAt(
        readIndex,
        throughNewest: readIndex == 0 && live && !t.hasPending,
      );
      _marker.read(passed, viewed: viewed);
      viewed.clear();
      Map<int, int>? moved;
      passed.forEach((chat, id) {
        if (id > (_marks[chat] ?? 0)) (moved ??= {..._marks})[chat] = id;
      });
      if (moved != null) {
        _marks = moved!;
        _corner.value++; // the unread count on the button
      }
    }
    // Nothing new was read, but what is on the screen was seen.
    if (viewed.isNotEmpty) _marker.read(const {}, viewed: viewed);
    // The list is reversed, so the row on top of the screen is the one with the highest
    // index: its day is what the floating pill names.
    _show(_stickyDay, _dayOf(items[oldestIndex.clamp(0, items.length - 1)]));
    if (newest.index < items.length) {
      final row = items[newest.index];
      if (_pins.isNotEmpty) {
        _showPinAt(row.allPosts.map((p) => p.messageId).reduce(math.max));
      }
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
      if (atNewest) {
        _returnTo = null;
        _cornerByScroll = false;
        _scrolled = 0;
      }
      if (atNewest && t.hasPending) {
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
  /// The button to the newest posts came with the scroll: the reader went this far
  /// towards the newest posts, as in the official app. Going as far back takes it away.
  /// A timeline that opens somewhere else than at its newest post (where it was left)
  /// starts with it, and it is lost at the newest post.
  bool _cornerByScroll = false;

  /// How far the finger has scrolled one way since it last turned: positive towards the
  /// newest posts, negative towards older ones.
  double _scrolled = 0;

  /// The distance, either way, after which the button comes or goes.
  static const _cornerScroll = 100.0;

  /// Follows the scroll for the button: it comes after [_cornerScroll] towards the
  /// newest posts and goes after as much the other way.
  void _followScrollForCorner(double delta) {
    // The list is reversed: its offset grows towards older posts.
    final towardsNewest = -delta;
    if (towardsNewest == 0) return;
    if ((towardsNewest > 0) != (_scrolled > 0)) _scrolled = 0;
    _scrolled += towardsNewest;
    final show = _scrolled >= _cornerScroll
        ? true
        : _scrolled <= -_cornerScroll
        ? false
        : _cornerByScroll;
    if (show != _cornerByScroll) {
      _cornerByScroll = show;
      _corner.value++;
    }
  }

  /// The reader's own scroll is under way: the drag, and the fling after it.
  bool _userScrolling = false;

  bool _onScroll(ScrollNotification n) {
    if (n is ScrollStartNotification &&
        n.dragDetails != null &&
        _highlight != null) {
      _highlightTimer?.cancel();
      setState(() => _highlight = null);
    }
    if (n is UserScrollNotification) {
      _userScrolling = n.direction != ScrollDirection.idle;
    } else if (n is ScrollUpdateNotification && _userScrolling) {
      _followScrollForCorner(n.scrollDelta ?? 0);
      // The list is reversed: its offset grows towards older posts.
      _followScrollForPin(-(n.scrollDelta ?? 0));
    }
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

  /// Tints the row for a second, so the post the timeline jumped to is easy to spot. A
  /// drag of the list ends it, as in the official app.
  void _flash((int, int) row) {
    _highlightTimer?.cancel();
    _highlight = row;
    _highlightTimer = Timer(const Duration(seconds: 1), () {
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
    final arrived = t.releasePending();
    setState(() {});
    if (!_scrollCtl.isAttached) return;
    if (toEnd || arrived <= 1) {
      unawaited(_scrollToEnd());
      return;
    }
    unawaited(
      _scrollCtl.scrollTo(
        index: arrived - 1,
        alignment: 0.5,
        duration: _jumpScroll,
        curve: Curves.easeOut,
      ),
    );
  }

  /// True when the list has built the row at [index], on the screen or in the stretch it
  /// keeps ready beyond it. The list reports only the rows on the screen; it keys every
  /// row it builds with the row's index, and that is looked for here.
  bool _rowBuilt(int index) {
    var found = false;
    void visit(Element e) {
      if (found) return;
      final key = e.widget.key;
      if (key is ValueKey<int>) {
        // A row: what stands inside it is of no interest.
        found = key.value == index;
        return;
      }
      e.visitChildren(visit);
    }

    _listKey.currentContext?.visitChildElements(visit);
    return found;
  }

  /// Animates to the newest post, where the list rests with its bottom padding under the
  /// post. The list package leaves that padding out when it scrolls to a row it has built
  /// (the post would end under the gesture bar) and counts it when the row is far, so
  /// the padding is handed over as the alignment in the first case.
  Future<void> _scrollToEnd() {
    var alignment = 0.0;
    final box = _listKey.currentContext?.findRenderObject();
    if (box is RenderBox &&
        box.hasSize &&
        box.size.height > 0 &&
        _rowBuilt(0)) {
      alignment = (8 + MediaQuery.paddingOf(context).bottom) / box.size.height;
    }
    return _scrollCtl.scrollTo(
      index: 0,
      alignment: alignment,
      duration: _jumpScroll,
      curve: Curves.easeOut,
    );
  }

  /// Opens the post in the Telegram app, falling back to t.me in the browser.
  Future<void> _openInTelegram(TimelineItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
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
    messenger.showSnackBar(SnackBar(content: Text(l10n.timelineNoAppForPost)));
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
                ? context.l10n.timelineForwardHidden
                : context.l10n.timelineForwardNotFollowed(origin.title),
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
        SnackBar(content: Text(context.l10n.timelineReplyNotFollowed)),
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
  Future<void> _openLink(String url, {TimelineItem? from}) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final uri = Uri.tryParse(url);
    if (uri != null && _openTelegramLink(uri, from: from)) return;
    if (await launchFirst([uri])) return;
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.timelineNoAppForLink(url))),
    );
  }

  /// The link path, for the test of H-18: answers whether the app opened it itself.
  @visibleForTesting
  bool openLinkForTest(String url) => _openTelegramLink(Uri.parse(url));

  /// True when the link named a channel of this account and the app went there itself. A
  /// post of a channel of this timeline is jumped to in place, and the button at the corner
  /// comes back to the post the link stood in ([from]), as in the official app; any other
  /// channel opens in a timeline of its own.
  bool _openTelegramLink(Uri uri, {TimelineItem? from, bool inPlace = true}) {
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
    final t = _timeline;
    final messageId = target.messageId;
    if (inPlace &&
        t != null &&
        messageId != null &&
        t.chatIds.contains(channel.chatId)) {
      final loaded = _indexOf(
        t,
        channel.chatId,
        (i) => i.allPosts.any((p) => p.messageId == messageId),
      );
      // A post that is not loaded is opened around its date, which the link does not
      // tell: the timeline of one channel needs none. A filter may keep the post out of
      // this timeline, and then its channel shows it.
      if (loaded >= 0 || (t.chatIds.length == 1 && _filter.isEmpty)) {
        if (from != null) {
          _returnTo = (
            chatId: from.chatId,
            messageId: from.head.messageId,
            date: from.head.date,
          );
        }
        unawaited(
          jumpToPost(
            chatId: channel.chatId,
            messageId: messageId,
            date: loaded >= 0 ? t.items[loaded].head.date : 0,
          ),
        );
        return true;
      }
    }
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
        : shareText(channelTitle: title, text: item.text, link: link);
  }

  Future<void> _share(TimelineItem item) async {
    final link = _shareLink(item);
    if (link == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.timelineNoLinkToShare)),
      );
      return;
    }
    final title = _titles[item.chatId] ?? '';
    await widget.share(
      shareText(channelTitle: title, text: item.text, link: link),
      subject: title,
    );
  }

  /// The post's words, as the official app's "Copy" does.
  Future<void> _copyText(TimelineItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    await Clipboard.setData(ClipboardData(text: item.text));
    messenger.showSnackBar(SnackBar(content: Text(l10n.timelineTextCopied)));
  }

  Future<void> _copyLink(TimelineItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final link = _shareLink(item);
    if (link == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.timelineNoLinkToCopy)),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: link.toString()));
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.timelineLinkCopied(link.toString()))),
    );
  }

  /// Copies what the post carries of one kind to the phone: pictures and videos to the
  /// gallery, documents to Downloads, music to Music. A file that is not here yet is
  /// downloaded first.
  Future<void> _saveToDevice(TimelineItem item, SaveTo to) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    // Oldest first, as the post shows them.
    final files = <({FileRef file, String name, String mime})>[];
    for (final p in item.allPosts.reversed) {
      switch ((to, p.media)) {
        case (SaveTo.gallery, PhotoMedia(:final sizes)) when sizes.isNotEmpty:
          files.add((
            file: sizes.last,
            name: Gallery.nameFor(fileId: sizes.last.id, video: false),
            mime: 'image/jpeg',
          ));
        case (SaveTo.gallery, VideoMedia(:final file)):
          files.add((
            file: file,
            name: Gallery.nameFor(fileId: file.id, video: true),
            mime: 'video/mp4',
          ));
        case (
          SaveTo.downloads,
          DocumentMedia(:final file, :final fileName, :final mimeType),
        ):
          files.add((
            file: file,
            name: fileName.isEmpty ? 'telegram-feed-${file.id}' : fileName,
            mime: mimeType.isEmpty ? 'application/octet-stream' : mimeType,
          ));
        case (
          SaveTo.music,
          AudioMedia(
            :final file,
            :final fileName,
            :final mimeType,
            :final title,
            :final performer,
            isVoice: false,
          ),
        ):
          final named = [
            performer,
            title,
          ].where((s) => s.isNotEmpty).join(' - ');
          files.add((
            file: file,
            name: fileName.isNotEmpty
                ? fileName
                : named.isNotEmpty
                ? '$named.mp3'
                : 'telegram-feed-${file.id}.mp3',
            mime: mimeType.isEmpty ? 'audio/mpeg' : mimeType,
          ));
        default:
      }
    }
    if (files.isEmpty) return;
    try {
      for (final f in files) {
        final ready = f.file.localPath != null
            ? f.file
            : await widget.gateway.download(f.file);
        final path = ready.localPath;
        if (path == null) throw StateError('the file did not arrive');
        await const Gallery().save(
          path: path,
          name: f.name,
          mimeType: f.mime,
          to: to,
        );
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(switch (to) {
            SaveTo.gallery => l10n.postSavedToGallery(files.length),
            SaveTo.downloads => l10n.postSavedToDownloads(files.length),
            SaveTo.music => l10n.postSavedToMusic(files.length),
          }),
        ),
      );
    } on Object catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.viewerSaveFailed('$e'))),
      );
    }
  }

  /// Reports a post to Telegram, which asks its questions one by one: a reason out of a
  /// list, perhaps another list, perhaps some words. Leaving any of them sends nothing.
  Future<void> _report(TimelineItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final ids = [for (final p in item.allPosts) p.messageId];
    var option = '';
    var text = '';
    try {
      // Telegram's own questions end by themselves; the bound is for a server that
      // would not.
      for (var asked = 0; asked < 8; asked++) {
        final step = await widget.gateway.report(
          item.chatId,
          ids,
          optionId: option,
          text: text,
        );
        if (!mounted) return;
        switch (step) {
          case ReportDone():
            messenger.showSnackBar(
              SnackBar(content: Text(l10n.postReportSent)),
            );
            return;
          case ReportChoice(:final title, :final options):
            final picked = await showModalBottomSheet<String>(
              context: context,
              showDragHandle: true,
              builder: (context) => SafeArea(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ListTile(
                      title: Text(
                        title.isEmpty ? l10n.postReport : title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    for (final o in options)
                      ListTile(
                        title: Text(o.text),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.pop(context, o.id),
                      ),
                  ],
                ),
              ),
            );
            if (picked == null || !mounted) return;
            option = picked;
            text = '';
          case ReportText(:final optionId, :final optional):
            final words = await showDialog<String>(
              context: context,
              builder: (context) => _ReportWords(optional: optional),
            );
            if (words == null || !mounted) return;
            option = optionId;
            text = words;
        }
      }
    } on TelegramException catch (e) {
      showTelegramError(messenger, e, what: l10n.postReportFailed);
    }
  }

  /// Deletes posts of Saved Messages, albums whole, once the reader says yes, as the
  /// official app asks. They leave the timeline when Telegram reports them deleted.
  Future<void> deletePosts(List<TimelineItem> items) async {
    if (items.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          items.length == 1
              ? l10n.timelineDeletePostTitle
              : l10n.timelineDeletePostsTitle(items.length),
        ),
        content: Text(
          items.length == 1
              ? l10n.timelineDeletePostMessage
              : l10n.timelineDeletePostsMessage,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.commonCancel),
          ),
          DestructiveButton(
            onPressed: () => Navigator.pop(context, true),
            label: l10n.commonDelete,
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    clearSelection();
    try {
      await widget.gateway.deleteFromSavedMessages([
        for (final i in items)
          for (final p in i.allPosts) p.messageId,
      ]);
    } on TelegramException catch (e) {
      showTelegramError(messenger, e, what: l10n.timelineDeletePostsFailed);
    }
  }

  /// Forwards the post, and with it the whole album, into Saved Messages.
  Future<void> _save(TimelineItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      await widget.gateway.saveToSavedMessages(item.chatId, [
        for (final p in item.allPosts) p.messageId,
      ]);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.timelineSavedToSavedMessages)),
      );
    } on TelegramException catch (e) {
      showTelegramError(messenger, e, what: l10n.timelineSavePostFailed);
    }
  }

  /// Reactions the reader changed, shown at once, by post, with the list they were made
  /// from: once Telegram's update gives the post a new list, the post's own is shown again.
  final _optimistic = <(int, int), (List<Reaction>, List<Reaction>)>{};

  /// The reactions to draw for a post: the reader's change while Telegram has not answered.
  List<Reaction>? _reactionsOf(TimelineItem item) {
    final post = item.reactionPost;
    final o = _optimistic[(item.chatId, post.messageId)];
    if (o == null || !identical(o.$1, post.reactions)) return null;
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
      // The paid reaction is beside the one reaction of one's own, not instead of it.
      if (r.emoji == paidReaction) {
        out.add(r);
        continue;
      }
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
    final l10n = context.l10n;
    // An album's reactions are those of its first message.
    final post = item.reactionPost;
    final key = (item.chatId, post.messageId);
    // A second tap before Telegram answered would undo the first.
    if (_reacting.contains(key)) return;
    Haptics.reaction();
    _reacting.add(key);
    final shown = _reactionsOf(item) ?? post.reactions;
    setState(() {
      _optimistic[key] = (
        post.reactions,
        _toggled(shown, emoji, remove: remove),
      );
      // The pill of a reaction that was just set pops, as the official app animates it.
      if (!remove) _justReacted = (item.chatId, item.rowId, emoji);
    });
    if (!remove) {
      _popEnd?.cancel();
      _popEnd = Timer(const Duration(milliseconds: 600), () {
        if (mounted) setState(() => _justReacted = null);
      });
    }
    try {
      await widget.gateway.react(
        item.chatId,
        post.messageId,
        emoji,
        remove: remove,
      );
    } on TelegramException catch (e) {
      if (mounted) setState(() => _optimistic.remove(key));
      showTelegramError(messenger, e, what: l10n.timelineReactionFailed);
    } finally {
      _reacting.remove(key);
    }
  }

  final _reacting = <(int, int)>{};

  /// The reaction the reader has just set, for the moment its pill pops: chat, row, emoji.
  (int, int, String)? _justReacted;
  Timer? _popEnd;

  /// What each channel lets the account react with, asked once per visit.
  final _allowedReactions = <int, Future<List<String>>>{};

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
      if (_folded(item)) continue; // its pictures are not on the screen
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
        entities: item.textPost.entities,
        // The pictures of one post count among themselves ("2 of 3"), not among the
        // hundreds the feed holds.
        postKey: '${item.chatId}:${item.head.messageId}',
        protected: item.isProtected,
        onOpenLink: (url) => unawaited(_openLink(url, from: item)),
        onShowInChat: () => unawaited(
          jumpToPost(
            chatId: item.chatId,
            messageId: item.head.messageId,
            date: item.head.date,
          ),
        ),
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

  /// As many posts as one selection holds, as in the official app.
  static const maxSelected = 100;

  /// Picks a row, or lets it go; the screen above follows the count and shows its own bar.
  /// A row beyond [maxSelected] is refused with a buzz.
  void toggleSelected(TimelineItem item) {
    final id = (item.chatId, item.rowId);
    if (!_selected.contains(id) && _selected.length >= maxSelected) {
      Haptics.refused();
      return;
    }
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
    widget.onSelectionChanged?.call(_selected.length);
  }

  /// The row a long press began on, while its finger is still down, and what was picked
  /// before it: the drag picks every row between that one and the finger.
  (int, int)? _dragAnchor;
  Set<(int, int)> _dragBase = const {};

  /// A long press on a row: the selection starts with it, or takes it in.
  void startSelection(TimelineItem item) {
    final id = (item.chatId, item.rowId);
    if (!_selected.contains(id) && _selected.length >= maxSelected) {
      Haptics.refused();
      return;
    }
    Haptics.longPress();
    _dragBase = {..._selected};
    _dragAnchor = id;
    setState(() => _selected.add(id));
    widget.onSelectionChanged?.call(_selected.length);
  }

  /// The finger of that long press is at [at] on the screen: every row from the one it
  /// began on to the one under it is picked, and going back lets the rows go again.
  void dragSelection(Offset at) {
    final anchor = _dragAnchor;
    final items = _timeline?.items;
    final box = _listKey.currentContext?.findRenderObject();
    if (anchor == null || items == null || box is! RenderBox) return;
    // A row's edges are fractions of the viewport, measured from its bottom.
    final fromBottom = 1 - box.globalToLocal(at).dy / box.size.height;
    int? under;
    for (final p in _positions.itemPositions.value) {
      if (p.index < items.length &&
          p.itemLeadingEdge <= fromBottom &&
          fromBottom <= p.itemTrailingEdge) {
        under = p.index;
      }
    }
    final from = items.indexWhere((i) => (i.chatId, i.rowId) == anchor);
    if (under == null || from < 0) return;
    final picked = {..._dragBase};
    var refused = false;
    final step = under >= from ? 1 : -1;
    for (var i = from; i != under + step; i += step) {
      final item = items[i];
      // Lines that are no posts cannot be picked.
      if (item.head.media is ServiceNote) continue;
      if (picked.length >= maxSelected) {
        refused = true;
        break;
      }
      picked.add((item.chatId, item.rowId));
    }
    if (picked.length == _selected.length && picked.containsAll(_selected)) {
      return;
    }
    if (refused) Haptics.refused();
    setState(() {
      _selected
        ..clear()
        ..addAll(picked);
    });
    widget.onSelectionChanged?.call(_selected.length);
  }

  final _listKey = GlobalKey();

  /// In a feed, a post's channel name opens that channel's info, as a name does in the
  /// official app. A channel the account no longer follows has none to show.
  VoidCallback? _channelInfoOf(int chatId) {
    if (widget.feed == null) return null;
    final channel = _known[chatId];
    if (channel == null) return null;
    return () => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (info) => ChannelInfoScreen(
          gateway: widget.gateway,
          channel: channel,
          onShowInChat: (post) {
            Navigator.of(info).pop();
            unawaited(
              jumpToPost(
                chatId: post.chatId,
                messageId: post.messageId,
                date: post.date,
              ),
            );
          },
        ),
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
      final pins = await widget.gateway.pinnedPosts(widget.channel!.chatId);
      if (pins.isEmpty) return;
      final hidden = int.tryParse(
        await widget.db.setting(_pinsHiddenKey) ?? '',
      );
      if (!mounted) return;
      setState(() {
        _pins = pins;
        _pinsHiddenAt = hidden ?? 0;
      });
    } on TelegramException {
      // No bar, as if the channel had nothing pinned.
    }
  }

  /// Double tap on a post: the quick reaction, added or taken back again. In a channel
  /// that does not allow that emoji it does nothing.
  Future<void> _quickReact(TimelineItem item) async {
    final emoji = _quick;
    final chosen = (_reactionsOf(item) ?? item.reactionPost.reactions).any(
      (r) => r.emoji == emoji && r.chosen,
    );
    if (!chosen) {
      // A channel that does not allow this reaction (or any): the double tap does
      // nothing, as in the official app.
      final List<String> allowed;
      try {
        allowed = await (_allowedReactions[item.chatId] ??= widget.gateway
            .availableReactions(item.chatId, item.reactionPost.messageId));
      } on TelegramException {
        unawaited(_allowedReactions.remove(item.chatId));
        return;
      }
      if (!mounted || !allowed.contains(emoji)) return;
    }
    await _react(item, emoji, chosen);
  }

  /// Emoji for the post menu; a failure is reported by the menu itself.
  /// The reactions a channel allows, asked once per channel: the menu opened a spinner
  /// on every long press while it asked again for a list that does not change.
  final _reactionsOfChat = <int, Future<List<String>>>{};

  Future<List<String>> _availableReactions(TimelineItem item) =>
      _reactionsOfChat[item.chatId] ??= widget.gateway.availableReactions(
        item.chatId,
        item.reactionPost.messageId,
      );

  @override
  void dispose() {
    _shown.remove(this);
    _keepPosition();
    WidgetsBinding.instance.removeObserver(this);
    _positions.itemPositions.removeListener(_onPositions);
    _stickyHide?.cancel();
    _popEnd?.cancel();
    unawaited(_quickSub?.cancel());
    unawaited(SecureWindow.release(this));
    _stickyDay.dispose();
    _stickyShown.dispose();
    _corner.dispose();
    _pinIndex.dispose();
    _highlightTimer?.cancel();
    _events?.cancel();
    _sources?.cancel();
    _readStates?.cancel();
    _feedSub?.cancel();
    unawaited(_marker.dispose());
    super.dispose();
  }

  /// The timelines that are open, the topmost last: where the audio bar looks for the
  /// posts of a voice message whose own timeline was closed.
  static final _shown = <TimelineViewState>[];

  /// The audio bar's way back to the post of the voice message that plays: every screen
  /// opened over this timeline goes, and the timeline goes to the post. A timeline that
  /// was closed meanwhile ([from], on [navigator]) opens again at the post, as the
  /// official app opens the chat, unless one of the same posts is open already.
  void _showAudioPost(Post post, TimelineView from, NavigatorState navigator) {
    if (!mounted) {
      for (final other in _shown.reversed) {
        final view = other.widget;
        if (view.feed?.id == from.feed?.id &&
            view.channel?.chatId == from.channel?.chatId) {
          return other._showAudioPost(post, from, navigator);
        }
      }
      if (!navigator.mounted) return;
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => TimelineScreen(
              db: from.db,
              gateway: from.gateway,
              feed: from.feed,
              channel: from.channel,
              focusChatId: post.chatId,
              focusMessageId: post.messageId,
              share: from.share,
              savedMessages: from.savedMessages,
            ),
          ),
        ),
      );
      return;
    }
    final route = ModalRoute.of(context);
    if (route != null) {
      Navigator.of(context).popUntil((r) => r == route || r.isFirst);
    }
    unawaited(
      jumpToPost(
        chatId: post.chatId,
        messageId: post.messageId,
        date: post.date,
      ),
    );
  }

  /// The voice messages, or the music, of the posts the timeline holds, oldest first:
  /// what plays on when one of them ends, as the official app plays on down the chat.
  List<AudioItem> _audioItems({required bool voice}) {
    final l10n = context.l10n;
    // What the bar needs once this timeline is gone.
    final view = widget;
    final navigator = Navigator.of(context);
    final found = <AudioItem>[];
    for (final item in (_timeline?.items ?? const <TimelineItem>[]).reversed) {
      if (_folded(item)) continue; // its row has no player
      for (final post in item.allPosts.reversed) {
        final media = post.media;
        if (media is! AudioMedia || media.isVoice != voice) continue;
        final named = [
          media.title,
          media.performer,
        ].where((s) => s.isNotEmpty).join(' – ');
        found.add(
          AudioItem(
            id: media.file.id,
            label: voice
                ? l10n.mediaVoiceMessage
                : named.isEmpty
                ? l10n.mediaAudio
                : named,
            durationSeconds: media.durationSeconds,
            isVoice: voice,
            // As Android's player names it: the piece and who plays it, or the channel.
            title: voice
                ? l10n.mediaVoiceMessage
                : media.title.isEmpty
                ? null
                : media.title,
            artist: voice || media.performer.isEmpty
                ? _titles[post.chatId] ?? ''
                : media.performer,
            onShow: () => _showAudioPost(post, view, navigator),
            load: () async {
              final file = media.file.isDownloaded
                  ? media.file
                  : await widget.gateway.download(media.file);
              return file.localPath!;
            },
          ),
        );
      }
    }
    return found;
  }

  @override
  Widget build(BuildContext context) {
    final t = _timeline;
    final items = t?.items ?? const <TimelineItem>[];
    return AudioQueue(items: _audioItems, child: _stack(context, t, items));
  }

  Widget _stack(
    BuildContext context,
    FeedTimeline? t,
    List<TimelineItem> items,
  ) {
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
        if (_pinsShown)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ValueListenableBuilder(
              valueListenable: _pinIndex,
              builder: (context, index, _) => PinnedBar(
                pins: _pins,
                index: index,
                onTap: _onPinnedTap,
                onHide: _hidePinned,
                onList: () => unawaited(_openPinnedList()),
              ),
            ),
          ),
        if (t != null && !_opening && items.isNotEmpty)
          Positioned(
            top: _pinsShown ? pinnedBarHeight : 0,
            left: 0,
            right: 0,
            child: FloatingDay(
              day: _stickyDay,
              shown: _stickyShown,
              onTap: (day) => unawaited(jumpToDayStart(day)),
            ),
          ),
        ValueListenableBuilder<int>(
          valueListenable: _corner,
          builder: (context, _, _) => _cornerButton(context),
        ),
      ],
    );
  }

  /// The button to the newest posts, with the unread count on it. As in the official app
  /// it is there while there is something to go to: unread posts, posts that arrived
  /// meanwhile, the way back from a jump. Otherwise it comes when the reader scrolls
  /// towards the newest posts and goes when they scroll away from them, and it is never
  /// there at the newest post itself.
  Widget _cornerButton(BuildContext context) {
    final t = _timeline;
    // Unread posts as Telegram counts them, and the ones that arrived meanwhile.
    var unread = t == null ? 0 : t.unreadPosts(_marks) + t.pendingNew;
    if (t != null && t.anchored && !t.exhaustedNewer && _filter.isEmpty) {
      // The rows up to the newest post are not all loaded: Telegram knows how many
      // there are.
      unread = math.max(
        unread,
        t.chatIds.fold(0, (n, id) => n + (_telegramUnread[id] ?? 0)),
      );
    }
    // No `_opening` here: the button would blink away and back every time the feed
    // is rebuilt (a changed filter, another channel).
    final away = t == null || (t.atTop && !t.anchored);
    final wanted = unread > 0 || (t?.anchored ?? false) || _returnTo != null;
    final shown = !away && (wanted || _cornerByScroll);
    return Positioned(
      right: 16,
      // Above the gesture bar: the app draws edge to edge.
      bottom: 16 + MediaQuery.paddingOf(context).bottom,
      // It grows in and shrinks away, as the official app's button does.
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: Tween<double>(begin: 0.6, end: 1).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: !shown
            ? const SizedBox.shrink()
            // The accent colour, as the official app counts on its page-down button.
            : Badge.count(
                key: const ValueKey('to newest'),
                count: unread,
                isLabelVisible: unread > 0,
                backgroundColor: Theme.of(context).colorScheme.primary,
                textColor: Theme.of(context).colorScheme.onPrimary,
                child: FloatingActionButton.small(
                  heroTag: null,
                  tooltip: t.pendingNew > 0
                      ? context.l10n.timelineNewPosts(t.pendingNew)
                      : unread > 0
                      ? context.l10n.timelineUnreadPostsCount(unread)
                      : context.l10n.timelineNewestPosts,
                  onPressed: _onDownButton,
                  child: const Icon(Icons.keyboard_arrow_down),
                ),
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
    final l10n = context.l10n;
    // A channel that protects its content is not to be captured: while a post of one is
    // loaded here, no screenshot is taken of the timeline, as in the official app.
    unawaited(
      SecureWindow.set(this, secure: items.any((item) => item.isProtected)),
    );
    return t == null || _opening
        ? const Center(child: CircularProgressIndicator())
        : items.isEmpty && t.chatIds.isEmpty
        ? EmptyState(
            icon: Icons.rss_feed,
            title: l10n.timelineNoChannelsTitle,
            message: l10n.timelineNoChannelsMessage,
            actionLabel: l10n.timelineAddChannels,
            onAction: widget.onEditFeed,
          )
        : items.isEmpty && _error != null
        ? ErrorState(
            what: l10n.timelineLoadFailed,
            message: _error,
            onRetry: _retryLoad,
          )
        : items.isEmpty
        ? Center(
            child: Text(
              _filter.isEmpty
                  ? l10n.timelineNoPosts
                  : l10n.timelineNoPostsPassFilter(_filter.describeIn(l10n)),
              textAlign: TextAlign.center,
            ),
          )
        // Oldest at the top, newest at the bottom, like a chat in Telegram.
        : ScrollablePositionedList.builder(
            key: _listKey,
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
                        ? ChatPill(l10n.timelineBeginningOfFeed)
                        : _error != null
                        ? ErrorState(
                            what: l10n.timelineOlderFailed,
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
                folded: _folded(item),
                title: _titles[item.chatId] ?? '',
                photo: _photos[item.chatId],
                channel: _known[item.chatId],
                reactions: _reactionsOf(item),
                selecting: _selected.isNotEmpty,
                selected: _selected.contains(id),
                tint: tint,
                newDay: newDay,
                firstUnread: id == _firstUnread,
                highlight: widget.highlight,
                pop:
                    _justReacted != null &&
                    _justReacted!.$1 == item.chatId &&
                    _justReacted!.$2 == item.rowId,
              );
              if (!identical(_rowsOf, t)) {
                _rows.clear();
                _rowsOf = t;
              }
              final kept = _rows[id];
              if (kept != null && kept.inputs.same(inputs)) return kept.row;
              final note = item.head.media;
              final card = note is ServiceNote
                  // A service message is a line, not a post; one about a pinned post
                  // leads to it.
                  ? ChatPill(
                      context.l10n.serviceLabel(
                        note,
                        channel: _titles[item.chatId] ?? '',
                        amongOthers: widget.feed != null,
                      ),
                      tapLabel: context.l10n.servicePinnedOpen(
                        _titles[item.chatId] ?? '',
                      ),
                      onTap:
                          note.kind != ServiceKind.pinned ||
                              note.messageId == 0 ||
                              _selected.isNotEmpty
                          ? null
                          : () => unawaited(
                              jumpToPost(
                                chatId: item.chatId,
                                messageId: note.messageId,
                                date: item.head.date,
                              ),
                            ),
                    )
                  : inputs.folded
                  ? MinimizedPost(
                      item: item,
                      channelTitle: _titles[item.chatId] ?? '',
                      onOpen: _selected.isNotEmpty
                          ? null
                          : () => setState(() => _opened.add(id)),
                    )
                  : PostCard(
                      item: item,
                      channelTitle: _titles[item.chatId] ?? '',
                      channelPhoto: _photos[item.chatId],
                      gateway: widget.gateway,
                      onOpenInTelegram: () => _openInTelegram(item),
                      // A post in Saved Messages has no link of its own and is
                      // saved already, so neither is offered there.
                      onShare: widget.savedMessages ? null : () => _share(item),
                      onCopyLink: widget.savedMessages
                          ? null
                          : () => _copyLink(item),
                      onCopyText: item.text.isEmpty
                          ? null
                          : () => _copyText(item),
                      onSave: widget.savedMessages ? null : () => _save(item),
                      onDelete: widget.savedMessages
                          ? () => unawaited(deletePosts([item]))
                          : null,
                      onReact: (emoji, remove) => _react(item, emoji, remove),
                      // What is kept in Saved Messages is the reader's own: there is
                      // nothing to report there.
                      onReport: widget.savedMessages
                          ? null
                          : () => unawaited(_report(item)),
                      onSaveToDevice: (to) =>
                          unawaited(_saveToDevice(item, to)),
                      availableReactions: () => _availableReactions(item),
                      onOpenLink: (url) =>
                          unawaited(_openLink(url, from: item)),
                      onOpenHashtag: widget.onHashtag,
                      onAutoplaySettings: () => openSettingsScreen(
                        context,
                        DataStorageScreen(
                          db: widget.db,
                          gateway: widget.gateway,
                        ),
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
                      highlight: widget.highlight,
                      justReacted:
                          _justReacted != null &&
                              _justReacted!.$1 == item.chatId &&
                              _justReacted!.$2 == item.rowId
                          ? _justReacted!.$3
                          : null,
                      onViewerMedia: _viewerMedia,
                      onMoreViewerMedia: _moreViewerMedia,
                      onViewerDetails: _viewerDetails,
                      onViewerSave: widget.savedMessages ? null : _viewerSave,
                      onSelect: () => toggleSelected(item),
                      onSelectStart: () => startSelection(item),
                      onSelectDrag: dragSelection,
                      onMinimize: !item.minimized
                          ? null
                          : () => setState(() => _opened.remove(id)),
                      selecting: _selected.isNotEmpty,
                      selected: _selected.contains(id),
                      // Only posts of channels with a discussion group have a thread.
                      onOpenThread: !item.threadPost.canComment
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => ThreadScreen(
                                  // The comments lie over this timeline: a link from
                                  // them opens a screen of its own, never a jump here.
                                  onOpenTelegramLink: (uri) =>
                                      _openTelegramLink(uri, inPlace: false),
                                  gateway: widget.gateway,
                                  post: item.threadPost,
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
                              formatChatDay(day, l10n: context.l10n),
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
    required this.folded,
    required this.title,
    required this.photo,
    required this.channel,
    required this.reactions,
    required this.selecting,
    required this.selected,
    required this.tint,
    required this.newDay,
    required this.firstUnread,
    this.highlight,
    this.pop = false,
  }) : head = item.head,
       parts = List.of(item.parts),
       minimized = item.minimized;
  final TimelineItem item;

  /// A reaction of this row was just set and its pill is popping.
  final bool pop;

  /// The words of the open search, marked in the row's text.
  final String? highlight;
  final Post head;
  final List<Post> parts;

  /// The filter leaves the post out; the row may still be open.
  final bool minimized;

  /// Drawn as the one line of a minimized post.
  final bool folded;
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
    return minimized == o.minimized &&
        folded == o.folded &&
        title == o.title &&
        photo == o.photo &&
        identical(channel, o.channel) &&
        identical(reactions, o.reactions) &&
        pop == o.pop &&
        selecting == o.selecting &&
        selected == o.selected &&
        tint == o.tint &&
        newDay == o.newDay &&
        highlight == o.highlight &&
        firstUnread == o.firstUnread;
  }
}

/// The words Telegram asks for with a report: a field and a Send button, which waits for
/// words unless they are optional.
class _ReportWords extends StatefulWidget {
  const _ReportWords({required this.optional});
  final bool optional;

  @override
  State<_ReportWords> createState() => _ReportWordsState();
}

class _ReportWordsState extends State<_ReportWords> {
  final _words = TextEditingController();

  @override
  void dispose() {
    _words.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.postReport),
      content: TextField(
        controller: _words,
        autofocus: true,
        minLines: 1,
        maxLines: 4,
        decoration: InputDecoration(hintText: l10n.postReportHint),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: widget.optional || _words.text.trim().isNotEmpty
              ? () => Navigator.pop(context, _words.text.trim())
              : null,
          child: Text(l10n.postReportSend),
        ),
      ],
    );
  }
}

/// The day of the topmost post, floating over the timeline: it is there while the list
/// moves and fades out once it comes to rest, as the date does in the official app. A tap
/// goes to the first post of that day; the day pills between the posts open the calendar.
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
          formatChatDay(day, l10n: context.l10n),
          tapLabel: context.l10n.postDayJumpToStart(
            formatChatDay(day, l10n: context.l10n),
          ),
          onTap: widget.onTap == null ? null : () => widget.onTap!(day),
        ),
      );
    },
  );
}
