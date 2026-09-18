import 'dart:async';

import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:share_plus/share_plus.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'feed_editor_screen.dart';
import 'media_view.dart';
import 'open_links.dart';
import 'photo_viewer.dart';
import 'read_marker.dart';
import 'thread_screen.dart';

/// The merged timeline of one feed (ARCHITECTURE.md section 5.3).
class TimelineScreen extends StatefulWidget {
  const TimelineScreen({
    super.key,
    required this.db,
    required this.gateway,
    required this.feed,
    this.focusChatId,
    this.focusMessageId,
    this.share = shareWithSystemSheet,
  });
  final AppDatabase db;
  final TelegramGateway gateway;
  final Feed feed;

  /// Opens the system share sheet with [text] (tests inject a recorder).
  final Future<void> Function(String text, {required String subject}) share;

  static Future<void> shareWithSystemSheet(
    String text, {
    required String subject,
  }) async {
    await SharePlus.instance.share(ShareParams(text: text, subject: subject));
  }

  /// Post to scroll to after loading (notification tap). Loads up to a few pages to find it.
  final int? focusChatId;
  final int? focusMessageId;

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
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

class _TimelineScreenState extends State<TimelineScreen> {
  /// Remembered positions per feed id. They hang off the database object, which goes away
  /// with the session.
  static final _memory = Expando<Map<int, _Anchor>>();

  /// Opening loads down to the read marks, but never more than this many rows.
  static const _openCap = 300;

  final _scrollCtl = ItemScrollController();
  final _positions = ItemPositionsListener.create();
  late final ReadMarker _marker = ReadMarker(
    db: widget.db,
    gateway: widget.gateway,
    feedId: widget.feed.id,
  );
  FeedTimeline? _timeline;
  StreamSubscription<PostEvent>? _events;
  StreamSubscription<List<WatchedChannel>>? _sources;
  StreamSubscription<List<FeedReadMark>>? _marksSub;
  Map<int, String> _titles = const {};
  Map<int, String?> _usernames = const {};
  Map<int, int> _marks = const {};
  bool _loading = false;
  String? _error;

  /// True until the first rows are loaded and the opening position is known; the list is
  /// only built afterwards because its initial index cannot be changed later.
  bool _opening = true;
  int _initialIndex = 0;
  double _initialAlignment = 0;

  /// Row that gets the "Unread posts" divider above it; fixed when the feed opens.
  (int, int)? _firstUnread;

  Map<int, _Anchor> get _remembered => _memory[widget.db] ??= {};

  @override
  void initState() {
    super.initState();
    _positions.itemPositions.addListener(_onPositions);
    _sources = widget.db.watchSourceChannels(widget.feed.id).listen(_onSources);
    _marksSub = widget.db.watchAllReadMarks().listen((_) async {
      _marks = await widget.db.readMarks(widget.feed.id);
      if (mounted) setState(() {});
    });
  }

  /// (Re)builds the timeline when the feed's sources change.
  void _onSources(List<WatchedChannel> sources) {
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
    final t = FeedTimeline(widget.gateway, ids);
    _timeline = t;
    _events = widget.gateway.postEvents.listen((e) {
      final before = t.items.length;
      final changed = t.apply(e);
      if (changed || e is PostAdded) setState(() {});
      // A row added at the newest end shifts every index; stay glued to the newest post.
      if (t.atTop && t.items.length > before) _jumpToNewest();
    });
    setState(() => _opening = true);
    unawaited(_open(t));
  }

  int _indexOf(FeedTimeline t, int chatId, bool Function(TimelineItem) test) =>
      t.items.indexWhere((i) => i.chatId == chatId && test(i));

  /// Loads the first rows and decides where the list opens: the post a notification asked
  /// for, else where the user left this feed earlier in the session, else the first unread
  /// post, else the newest post.
  Future<void> _open(FeedTimeline t) async {
    setState(() => _loading = true);
    try {
      _marks = await widget.db.readMarks(widget.feed.id);
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
      final left = _remembered[widget.feed.id];
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
        WidgetsBinding.instance.addPostFrameCallback((_) => _settleAtNewest());
      }
    }
  }

  /// A few short unread posts do not fill the screen below the divider; the list would show
  /// empty space under the newest post. Then the newest post goes to the bottom instead.
  void _settleAtNewest() {
    if (!mounted) return;
    for (final p in _positions.itemPositions.value) {
      if (p.index == 0 && p.itemLeadingEdge > 0.001) {
        _jumpToNewest();
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
    if (seen.isNotEmpty) _marker.seen(seen);
    if (newest.index < items.length) {
      final row = items[newest.index];
      _remembered[widget.feed.id] = _Anchor(
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

  Future<void> _pickReaction(TimelineItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    List<String> emoji;
    try {
      emoji = await widget.gateway.availableReactions(
        item.chatId,
        item.head.messageId,
      );
    } on TelegramException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Telegram: ${e.message}')));
      return;
    }
    if (!mounted) return;
    if (emoji.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('This channel does not allow reactions.')),
      );
      return;
    }
    final chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in emoji)
              ActionChip(
                label: Text(e, style: const TextStyle(fontSize: 22)),
                onPressed: () => Navigator.pop(context, e),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) await _react(item, chosen, false);
  }

  @override
  void dispose() {
    _positions.itemPositions.removeListener(_onPositions);
    _events?.cancel();
    _sources?.cancel();
    _marksSub?.cancel();
    unawaited(_marker.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _timeline;
    final items = t?.items ?? const <TimelineItem>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.feed.name),
        actions: [
          IconButton(
            tooltip: 'Edit feed',
            icon: const Icon(Icons.tune),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => FeedEditorScreen(
                  db: widget.db,
                  gateway: widget.gateway,
                  feedId: widget.feed.id,
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: t == null || _opening || t.atTop
          ? null
          : Badge.count(
              count: t.pendingNew,
              isLabelVisible: t.pendingNew > 0,
              child: FloatingActionButton.small(
                tooltip: t.pendingNew > 0
                    ? '${t.pendingNew} new post${t.pendingNew == 1 ? '' : 's'}'
                    : 'Newest posts',
                onPressed: _release,
                child: const Icon(Icons.keyboard_arrow_down),
              ),
            ),
      body: t == null || _opening
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
              child: Text(_error == null ? 'No posts.' : 'Telegram: $_error'),
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
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: t.exhausted
                          ? const Text('Beginning of the feed')
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
                  gateway: widget.gateway,
                  unread: FeedTimeline.isUnread(item, _marks),
                  onOpenInTelegram: () => _openInTelegram(item),
                  onShare: () => _share(item),
                  onCopyLink: () => _copyLink(item),
                  onReact: (emoji, remove) => _react(item, emoji, remove),
                  onPickReaction: () => _pickReaction(item),
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
                return KeyedSubtree(
                  key: ValueKey(id),
                  child: id == _firstUnread
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [const UnreadDivider(), card],
                        )
                      : card,
                );
              },
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
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(vertical: 4),
      color: scheme.secondaryContainer,
      alignment: Alignment.center,
      child: Text(
        'Unread posts',
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: scheme.onSecondaryContainer),
      ),
    );
  }
}

/// One timeline row: channel, date, inline media, text.
class PostCard extends StatelessWidget {
  const PostCard({
    super.key,
    required this.item,
    required this.channelTitle,
    required this.gateway,
    this.unread = false,
    this.onOpenInTelegram,
    this.onShare,
    this.onCopyLink,
    this.onReact,
    this.onPickReaction,
    this.onOpenThread,
  });
  final TimelineItem item;
  final String channelTitle;
  final TelegramGateway gateway;
  final bool unread;
  final VoidCallback? onOpenInTelegram;
  final VoidCallback? onShare;
  final VoidCallback? onCopyLink;

  /// Tap on an existing reaction chip: adds it, or removes it when already chosen.
  final void Function(String emoji, bool remove)? onReact;
  final VoidCallback? onPickReaction;
  final VoidCallback? onOpenThread;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = DateTime.fromMillisecondsSinceEpoch(item.head.date * 1000);
    // Albums: parts in message order (oldest first) so the layout matches Telegram.
    final media = [
      for (final p in item.allPosts.reversed)
        if (p.media != null) p.media!,
    ];
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (unread)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(
                      Icons.circle,
                      size: 8,
                      color: theme.colorScheme.primary,
                      semanticLabel: 'unread',
                    ),
                  ),
                Expanded(
                  child: Text(
                    channelTitle,
                    style: theme.textTheme.labelLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(_formatDate(date), style: theme.textTheme.labelSmall),
                if (onOpenInTelegram != null)
                  IconButton(
                    tooltip: 'Open in Telegram',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.open_in_new, size: 18),
                    onPressed: onOpenInTelegram,
                  ),
                if (onShare != null || onCopyLink != null)
                  PopupMenuButton<VoidCallback>(
                    tooltip: 'More',
                    icon: const Icon(Icons.more_vert, size: 18),
                    padding: EdgeInsets.zero,
                    onSelected: (action) => action(),
                    itemBuilder: (context) => [
                      if (onShare != null)
                        PopupMenuItem(
                          value: onShare,
                          child: const ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.share_outlined),
                            title: Text('Share'),
                          ),
                        ),
                      if (onCopyLink != null)
                        PopupMenuItem(
                          value: onCopyLink,
                          child: const ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.link),
                            title: Text('Copy link'),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
            for (final m in media.take(10))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: MediaView(
                  media: m,
                  gateway: gateway,
                  onOpenPhoto: m is! PhotoMedia
                      ? null
                      : () {
                          final photos = media.whereType<PhotoMedia>().toList();
                          PhotoViewerScreen.open(
                            context,
                            photos: photos,
                            gateway: gateway,
                            initialIndex: photos.indexOf(m),
                          );
                        },
                ),
              ),
            if (media.length > 10)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '+${media.length - 10} more',
                  style: theme.textTheme.labelSmall,
                ),
              ),
            if (item.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  item.text,
                  maxLines: 12,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (item.head.editDate > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('edited', style: theme.textTheme.labelSmall),
              ),
            if (onReact != null || item.head.reactions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final r in item.head.reactions)
                      FilterChip(
                        label: Text('${r.emoji} ${r.count}'),
                        selected: r.chosen,
                        visualDensity: VisualDensity.compact,
                        onSelected: onReact == null
                            ? null
                            : (_) => onReact!(r.emoji, r.chosen),
                      ),
                    if (onPickReaction != null)
                      ActionChip(
                        label: const Icon(
                          Icons.add_reaction_outlined,
                          size: 18,
                        ),
                        visualDensity: VisualDensity.compact,
                        onPressed: onPickReaction,
                      ),
                    if (onOpenThread != null)
                      ActionChip(
                        avatar: const Icon(Icons.forum_outlined, size: 18),
                        label: Text(
                          item.head.replyCount > 0
                              ? '${item.head.replyCount} comment${item.head.replyCount == 1 ? '' : 's'}'
                              : 'Comments',
                        ),
                        visualDensity: VisualDensity.compact,
                        onPressed: onOpenThread,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _formatDate(DateTime d) {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final time = '${two(d.hour)}:${two(d.minute)}';
  if (d.year == now.year && d.month == now.month && d.day == now.day) {
    return time;
  }
  return '${d.year}-${two(d.month)}-${two(d.day)} $time';
}
