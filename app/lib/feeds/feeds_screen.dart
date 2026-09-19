import 'dart:async';

import 'package:app_db/app_db.dart';
import 'package:flutter/foundation.dart';
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
