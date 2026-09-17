import 'dart:async';

import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'feed_editor_screen.dart';
import 'media_view.dart';
import 'read_marker.dart';

/// The merged timeline of one feed (ARCHITECTURE.md section 5.3).
class TimelineScreen extends StatefulWidget {
  const TimelineScreen({
    super.key,
    required this.db,
    required this.gateway,
    required this.feed,
  });
  final AppDatabase db;
  final TelegramGateway gateway;
  final Feed feed;

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
    unawaited(_loadMore());
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
                  item: items[i],
                  channelTitle: _titles[items[i].chatId] ?? '',
                  gateway: widget.gateway,
                  unread: FeedTimeline.isUnread(items[i], _marks),
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
  });
  final TimelineItem item;
  final String channelTitle;
  final TelegramGateway gateway;
  final bool unread;

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
              ],
            ),
            for (final m in media.take(10))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: MediaView(media: m, gateway: gateway),
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
