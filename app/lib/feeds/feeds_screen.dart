import 'dart:async';

import 'package:app_db/app_db.dart';
import 'package:flutter/material.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

/// Feeds with the number of sources that have posts newer than the feed's read mark.
/// Cheap upper bound per ARCHITECTURE.md 5.4: `Channel.lastMessageId` vs `feed_read_marks`.
final class FeedsController extends ChangeNotifier {
  FeedsController({required this.db, required this.gateway}) {
    _feedsSub = db.watchFeeds().listen((f) {
      _feeds = f;
      unawaited(_recount());
    });
    _marksSub = db.watchAllReadMarks().listen((_) => unawaited(_recount()));
    _postsSub = gateway.postEvents.listen((e) {
      if (e is PostAdded) {
        _lastIds[e.post.chatId] = e.post.messageId;
        unawaited(_recount());
      }
    });
    unawaited(refreshChannels());
  }

  final AppDatabase db;
  final TelegramGateway gateway;
  late final StreamSubscription<List<Feed>> _feedsSub;
  late final StreamSubscription<PostEvent> _postsSub;
  late final StreamSubscription<List<FeedReadMark>> _marksSub;
  List<Feed> _feeds = const [];
  final _lastIds = <int, int>{};
  Map<int, int> _newSources = const {};
  bool _channelsLoaded = false;
  String? error;

  List<Feed> get feeds => _feeds;
  bool get channelsLoaded => _channelsLoaded;

  /// Number of sources with unread posts, per feed id.
  int newSourcesOf(int feedId) => _newSources[feedId] ?? 0;

  Future<void> refreshChannels() async {
    try {
      for (final c in await gateway.myChannels()) {
        _lastIds[c.chatId] = c.lastMessageId;
      }
      _channelsLoaded = true;
      error = null;
    } on TelegramException catch (e) {
      error = e.message;
    }
    await _recount();
  }

  Future<void> _recount() async {
    final counts = <int, int>{};
    for (final f in _feeds) {
      final marks = await db.readMarks(f.id);
      counts[f.id] = marks.entries
          .where((m) => (_lastIds[m.key] ?? 0) > m.value)
          .length;
    }
    _newSources = counts;
    notifyListeners();
  }

  @override
  void dispose() {
    _feedsSub.cancel();
    _postsSub.cancel();
    _marksSub.cancel();
    super.dispose();
  }
}

class FeedsScreen extends StatefulWidget {
  const FeedsScreen({
    super.key,
    required this.db,
    required this.gateway,
    required this.onOpenFeed,
    this.actions = const [],
  });
  final AppDatabase db;
  final TelegramGateway gateway;
  final void Function(Feed feed) onOpenFeed;
  final List<Widget> actions;

  @override
  State<FeedsScreen> createState() => _FeedsScreenState();
}

class _FeedsScreenState extends State<FeedsScreen> {
  late final _ctl = FeedsController(db: widget.db, gateway: widget.gateway);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<String?> _askName(BuildContext context, {String? initial}) {
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

  Future<void> _create() async {
    final name = await _askName(context);
    if (name != null && name.isNotEmpty) await widget.db.createFeed(name);
  }

  Future<void> _rename(Feed f) async {
    final name = await _askName(context, initial: f.name);
    if (name != null && name.isNotEmpty && name != f.name) {
      await widget.db.renameFeed(f.id, name);
    }
  }

  Future<void> _delete(Feed f) async {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Feeds'), actions: widget.actions),
      floatingActionButton: FloatingActionButton(
        onPressed: _create,
        tooltip: 'New feed',
        child: const Icon(Icons.add),
      ),
      body: ListenableBuilder(
        listenable: _ctl,
        builder: (context, _) {
          final feeds = _ctl.feeds;
          if (feeds.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No feeds yet. Create one and add the channels you want to read together.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return Column(
            children: [
              if (_ctl.error != null)
                MaterialBanner(
                  content: Text('Telegram: ${_ctl.error}'),
                  actions: [
                    TextButton(
                      onPressed: _ctl.refreshChannels,
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
                    final fresh = _ctl.newSourcesOf(f.id);
                    return ListTile(
                      key: ValueKey(f.id),
                      title: Text(f.name),
                      leading: fresh > 0
                          ? Badge.count(
                              count: fresh,
                              child: const Icon(Icons.rss_feed),
                            )
                          : const Icon(Icons.rss_feed),
                      subtitle: fresh > 0
                          ? Text(
                              '$fresh channel${fresh == 1 ? '' : 's'} with new posts',
                            )
                          : null,
                      onTap: () => widget.onOpenFeed(f),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) => switch (v) {
                          'rename' => _rename(f),
                          'delete' => _delete(f),
                          _ => null,
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(value: 'rename', child: Text('Rename')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
