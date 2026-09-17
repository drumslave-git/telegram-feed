import 'dart:async';

import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'feed_editor_screen.dart';
import 'media_view.dart';

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
  final _scroll = ScrollController();
  FeedTimeline? _timeline;
  StreamSubscription<PostEvent>? _events;
  StreamSubscription<List<WatchedChannel>>? _sources;
  Map<int, String> _titles = const {};
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _sources = widget.db.watchSourceChannels(widget.feed.id).listen(_onSources);
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

  void _onScroll() {
    final t = _timeline;
    if (t == null) return;
    final atTop = _scroll.offset < 48;
    if (atTop != t.atTop) {
      t.atTop = atTop;
      if (atTop && t.pendingNew > 0) _release();
    }
    if (_scroll.position.extentAfter < 600) unawaited(_loadMore());
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
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _events?.cancel();
    _sources?.cancel();
    _scroll.dispose();
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
            ListView.builder(
              controller: _scroll,
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
  });
  final TimelineItem item;
  final String channelTitle;
  final TelegramGateway gateway;

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
