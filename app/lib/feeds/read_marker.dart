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

  /// Null for a single channel outside any feed: then only Telegram keeps the position.
  final int? feedId;
  final Duration debounce;

  final _maxSeen = <int, int>{}; // chat id → newest seen message id
  final _pendingIds =
      <int, Set<int>>{}; // chat id → message ids to report to Telegram
  final _reported = <int, int>{}; // chat id → newest id already written
  Timer? _timer;

  /// Records items the user has seen. Cheap; the write happens after [debounce].
  /// [coveredUpTo] names, per item, the newest message id reading it also covers: posts the
  /// feed's filter hides right after it.
  void seen(
    Iterable<TimelineItem> items, {
    int Function(TimelineItem item)? coveredUpTo,
  }) {
    var changed = false;
    for (final item in items) {
      final covered = coveredUpTo?.call(item) ?? 0;
      if (covered > item.head.messageId) {
        changed = cover(item.chatId, covered) || changed;
      }
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

  /// Marks everything of [chatId] up to [messageId] read without it having been on screen
  /// (posts a filter hides). Returns whether that moved anything.
  bool cover(int chatId, int messageId) {
    if (messageId <= (_maxSeen[chatId] ?? 0) &&
        messageId <= (_reported[chatId] ?? 0)) {
      return false;
    }
    if (messageId > (_maxSeen[chatId] ?? 0)) _maxSeen[chatId] = messageId;
    (_pendingIds[chatId] ??= {}).add(messageId);
    _timer?.cancel();
    _timer = Timer(debounce, () => unawaited(flush()));
    return true;
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
      final feed = feedId;
      if (feed != null) await db.markRead(feed, chatId, newest);
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
