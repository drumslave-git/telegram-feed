import 'dart:async';

import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:share_plus/share_plus.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'feed_editor_screen.dart';
import 'open_links.dart';
import 'post_card.dart';
import 'read_marker.dart';
import 'thread_screen.dart';

export 'post_card.dart' show PostCard;

/// A timeline with its own app bar: a feed opened from a notification, or one channel
/// opened from a folder tab or the channel list.
class TimelineScreen extends StatelessWidget {
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(feed?.name ?? channel!.title),
      actions: [
        if (feed != null)
          IconButton(
            tooltip: 'Edit feed',
            icon: const Icon(Icons.tune),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => FeedEditorScreen(
                  db: db,
                  gateway: gateway,
                  feedId: feed!.id,
                ),
              ),
            ),
          ),
      ],
    ),
    body: TimelineView(
      db: db,
      gateway: gateway,
      feed: feed,
      channel: channel,
      focusChatId: focusChatId,
      focusMessageId: focusMessageId,
      share: share,
    ),
  );
}

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
  }) : assert((feed == null) != (channel == null));
  final AppDatabase db;
  final TelegramGateway gateway;

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
  State<TimelineView> createState() => _TimelineViewState();
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

class _TimelineViewState extends State<TimelineView> {
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

  /// Row that gets the "Unread posts" divider above it; fixed when the feed opens.
  (int, int)? _firstUnread;

  Map<int, _Anchor> get _remembered => _memory[widget.db] ??= {};

  @override
  void initState() {
    super.initState();
    _positions.itemPositions.addListener(_onPositions);
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
  /// initials until they are here.
  Future<void> _loadPhotos() async {
    try {
      final channels = await widget.gateway.myChannels();
      if (!mounted) return;
      setState(() => _photos = {for (final c in channels) c.chatId: c.photo});
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
    final t = FeedTimeline(widget.gateway, ids, filter: _filter);
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
    setState(() => _opening = true);
    unawaited(_open(t));
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
  Future<void> _open(FeedTimeline t) async {
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

      final focusChat = widget.focusChatId;
      final focusMessage = widget.focusMessageId;
      final left = _remembered[_memoryKey];
      var index = -1;
      if (focusChat != null && focusMessage != null) {
        index = await search(
          () => _indexOf(
            t,
            focusChat,
            (i) => i.allPosts.any((p) => p.messageId == focusMessage),
          ),
        );
        _initialAlignment = 0.3;
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
    if (newest.index < items.length) {
      final row = items[newest.index];
      _remembered[_memoryKey] = _Anchor(
        row.chatId,
        row.rowId,
        newest.itemLeadingEdge,
      );
    }
    final atNewest = newest.index == 0 && newest.itemLeadingEdge >= -0.05;
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

  Future<void> _react(TimelineItem item, String emoji, bool remove) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.gateway.react(
        item.chatId,
        item.head.messageId,
        emoji,
        remove: remove,
      );
    } on TelegramException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Telegram: ${e.message}')));
    }
  }

  /// Emoji for the post menu; a failure is reported by the menu itself.
  Future<List<String>> _availableReactions(TimelineItem item) =>
      widget.gateway.availableReactions(item.chatId, item.head.messageId);

  @override
  void dispose() {
    _positions.itemPositions.removeListener(_onPositions);
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
            child: _body(context, t, items),
          ),
        ),
        if (t != null && !_opening && !t.atTop)
          Positioned(
            right: 16,
            bottom: 16,
            child: Badge.count(
              count: t.pendingNew,
              isLabelVisible: t.pendingNew > 0,
              child: FloatingActionButton.small(
                heroTag: null,
                tooltip: t.pendingNew > 0
                    ? '${t.pendingNew} new post${t.pendingNew == 1 ? '' : 's'}'
                    : 'Newest posts',
                onPressed: _release,
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
                onReact: (emoji, remove) => _react(item, emoji, remove),
                availableReactions: () => _availableReactions(item),
                // Only posts of channels with a discussion group have a thread.
                onOpenThread: !item.head.canComment
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ThreadScreen(
                            gateway: widget.gateway,
                            post: item.head,
                            channelTitle: _titles[item.chatId] ?? '',
                          ),
                        ),
                      ),
              );
              // The day goes above its first post: the row after this one is older.
              final day = _dayOf(item);
              final newDay =
                  i == items.length - 1 || _dayOf(items[i + 1]) != day;
              return KeyedSubtree(
                key: ValueKey(id),
                child: !newDay && id != _firstUnread
                    ? card
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (newDay) ChatPill(formatDay(day)),
                          if (id == _firstUnread) const UnreadDivider(),
                          card,
                        ],
                      ),
              );
            },
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
