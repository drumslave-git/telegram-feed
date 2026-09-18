import 'dart:async';

import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

/// Turns "these items were on screen down to their end" into read marks (ARCHITECTURE.md section 5.4):
/// per chat the newest message id seen goes to `feed_read_marks`, and, when the
/// `syncReadToTelegram` setting is on, to Telegram through `viewMessages`.
final class ReadMarker {
  ReadMarker({
    required this.db,
    required this.gateway,
    required this.feedId,
    this.debounce = const Duration(milliseconds: 800),
  });

  final AppDatabase db;
  final TelegramGateway gateway;
  final int feedId;
  final Duration debounce;

  final _maxSeen = <int, int>{}; // chat id → newest seen message id
  final _pendingIds =
      <int, Set<int>>{}; // chat id → message ids to report to Telegram
  final _reported = <int, int>{}; // chat id → newest id already written
  Timer? _timer;

  /// Records items the user has seen. Cheap; the write happens after [debounce].
  void seen(Iterable<TimelineItem> items) {
    var changed = false;
    for (final item in items) {
      for (final post in item.allPosts) {
        final max = _maxSeen[post.chatId] ?? 0;
        if (post.messageId > max) {
          _maxSeen[post.chatId] = post.messageId;
          changed = true;
        }
        if (post.messageId > (_reported[post.chatId] ?? 0)) {
          (_pendingIds[post.chatId] ??= {}).add(post.messageId);
          changed = true;
        }
      }
    }
    if (changed) {
      _timer?.cancel();
      _timer = Timer(debounce, () => unawaited(flush()));
    }
  }

  /// Writes what is pending now. Called on debounce and when the screen closes.
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    final sync = await db.syncReadToTelegram();
    final batch = Map.of(_pendingIds);
    _pendingIds.clear();
    for (final entry in _maxSeen.entries) {
      final chatId = entry.key;
      final newest = entry.value;
      if (newest <= (_reported[chatId] ?? 0)) continue;
      _reported[chatId] = newest;
      await db.markRead(feedId, chatId, newest);
      final ids = batch[chatId];
      if (sync && ids != null && ids.isNotEmpty) {
        try {
          await gateway.markViewed(chatId, ids.toList()..sort());
        } on TelegramException {
          // Local state is authoritative; Telegram sync is best effort.
        }
      }
    }
  }

  Future<void> dispose() => flush();
}
