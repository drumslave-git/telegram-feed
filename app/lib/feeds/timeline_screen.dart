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

class _TimelineScreenState extends State<TimelineScreen> {
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
  bool _jumping = false;
  String? _error;

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
      final changed = t.apply(e);
      if (changed || e is PostAdded) setState(() {});
    });
    setState(() {});
    unawaited(_loadMore().then((_) => _focusIfRequested()));
  }

  bool _focused = false;

  /// Scrolls to the requested post once it is loaded (bounded search).
  Future<void> _focusIfRequested() async {
    final chat = widget.focusChatId;
    final msg = widget.focusMessageId;
    final t = _timeline;
    if (chat == null || msg == null || t == null || _focused) return;
    _focused = true;
    int indexOf() => t.items.indexWhere(
      (i) => i.chatId == chat && i.allPosts.any((p) => p.messageId == msg),
    );
    var index = indexOf();
    for (var pages = 0; index < 0 && pages < 8 && !t.exhausted; pages++) {
      await t.loadMore();
      index = indexOf();
    }
    if (!mounted) return;
    setState(() {});
    if (index >= 0 && _scrollCtl.isAttached) {
      await _scrollCtl.scrollTo(
        index: index,
        alignment: 0.1,
        duration: const Duration(milliseconds: 300),
      );
    }
  }

  /// Visible item indices drive read marking, the "at top" flag and infinite scroll.
  void _onPositions() {
    final t = _timeline;
    final positions = _positions.itemPositions.value;
    if (t == null || positions.isEmpty) return;
    var minIndex = positions.first.index;
    var maxIndex = positions.first.index;
    double topEdge = 0;
    for (final p in positions) {
      if (p.index < minIndex) {
        minIndex = p.index;
        topEdge = p.itemLeadingEdge;
      }
      if (p.index > maxIndex) maxIndex = p.index;
    }
    final items = t.items;
    if (minIndex > 0) _marker.scrolledPast(items.take(minIndex));
    final atTop = minIndex == 0 && topEdge >= -0.05;
    if (atTop != t.atTop) {
      t.atTop = atTop;
      if (atTop && t.pendingNew > 0) _release();
    }
    if (maxIndex >= items.length - 5) unawaited(_loadMore());
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

  void _release() {
    _timeline?.releasePending();
    setState(() {});
    if (_scrollCtl.isAttached) {
      _scrollCtl.scrollTo(
        index: 0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  /// Loads until the read marks are reached, then scrolls to the oldest unread post.
  Future<void> _jumpToFirstUnread() async {
    final t = _timeline;
    if (t == null || _jumping) return;
    setState(() => _jumping = true);
    try {
      while (!t.reachedMarks(_marks) && !t.exhausted) {
        await t.loadMore();
      }
      final index = t.firstUnreadIndex(_marks);
      if (!mounted) return;
      setState(() {});
      if (index < 0) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Everything is read.')));
      } else if (_scrollCtl.isAttached) {
        await _scrollCtl.scrollTo(
          index: index,
          alignment: 0.1,
          duration: const Duration(milliseconds: 400),
        );
      }
    } on TelegramException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _jumping = false);
    }
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
            tooltip: 'Jump to first unread',
            icon: _jumping
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.mark_chat_unread_outlined),
            onPressed: _jumpToFirstUnread,
          ),
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
      body: Stack(
        children: [
          if (t == null || (items.isEmpty && _loading))
            const Center(child: CircularProgressIndicator())
          else if (items.isEmpty && t.chatIds.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'This feed has no channels yet. Tap the tune icon to add some.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else if (items.isEmpty)
            Center(
              child: Text(_error == null ? 'No posts.' : 'Telegram: $_error'),
            )
          else
            ScrollablePositionedList.builder(
              itemScrollController: _scrollCtl,
              itemPositionsListener: _positions,
              itemCount: items.length + 1,
              itemBuilder: (context, i) {
                if (i == items.length) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: t.exhausted
                          ? const Text('End of feed')
                          : const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                    ),
                  );
                }
                return PostCard(
                  key: ValueKey((items[i].chatId, items[i].rowId)),
                  item: items[i],
                  channelTitle: _titles[items[i].chatId] ?? '',
                  gateway: widget.gateway,
                  unread: FeedTimeline.isUnread(items[i], _marks),
                  onOpenInTelegram: () => _openInTelegram(items[i]),
                  onShare: () => _share(items[i]),
                  onCopyLink: () => _copyLink(items[i]),
                  onReact: (emoji, remove) => _react(items[i], emoji, remove),
                  onPickReaction: () => _pickReaction(items[i]),
                  // Only posts of channels with a discussion group have a thread.
                  onOpenThread: !items[i].head.canComment
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ThreadScreen(
                              gateway: widget.gateway,
                              post: items[i].head,
                              channelTitle: _titles[items[i].chatId] ?? '',
                            ),
                          ),
                        ),
                );
              },
            ),
          if (t != null && t.pendingNew > 0)
            Positioned(
              top: 8,
              left: 0,
              right: 0,
              child: Center(
                child: FilledButton.tonalIcon(
                  onPressed: _release,
                  icon: const Icon(Icons.arrow_upward),
                  label: Text(
                    '${t.pendingNew} new post${t.pendingNew == 1 ? '' : 's'}',
                  ),
                ),
              ),
            ),
        ],
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
