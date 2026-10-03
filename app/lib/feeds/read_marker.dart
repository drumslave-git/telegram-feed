import 'dart:async';
import 'dart:math' as math;

import 'package:telegram_gateway/telegram_gateway.dart';

/// Tells Telegram what the reader has read (ARCHITECTURE.md section 5.4). The read position
/// is Telegram's own, one per channel: `viewMessages` moves it up to the newest post it
/// names, for every feed, the channel's own timeline and the official app alike.
final class ReadMarker {
  ReadMarker({
    required this.gateway,
    this.debounce = const Duration(milliseconds: 300),
  });

  final TelegramGateway gateway;
  final Duration debounce;

  /// Chat id → newest message id read here and not sent yet.
  final _read = <int, int>{};

  /// Chat id → posts that were on the screen and are not sent yet; Telegram counts their
  /// views.
  final _viewed = <int, Set<int>>{};

  /// Chat id → posts whose view Telegram has heard of from this screen; each counts once.
  final _counted = <int, Set<int>>{};

  /// Chat id → newest message id already sent.
  final _sent = <int, int>{};
  Timer? _timer;

  /// Records that everything of each chat up to the id in [read] is read, and that the
  /// posts in [viewed] were on the screen, whether read or not: each counts a view once.
  /// Cheap; Telegram hears of it after [debounce].
  void read(Map<int, int> read, {Map<int, Iterable<int>> viewed = const {}}) {
    var changed = false;
    read.forEach((chat, id) {
      if (id > (_read[chat] ?? 0) && id > (_sent[chat] ?? 0)) {
        _read[chat] = id;
        changed = true;
      }
    });
    viewed.forEach((chat, ids) {
      final counted = _counted[chat];
      for (final id in ids) {
        if (counted != null && counted.contains(id)) continue;
        if ((_viewed[chat] ??= {}).add(id)) changed = true;
      }
    });
    if (changed) {
      _timer?.cancel();
      _timer = Timer(debounce, () => unawaited(flush()));
    }
  }

  /// Sends what is pending now. Called after [debounce] and when the screen closes.
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    final read = Map.of(_read);
    final viewed = Map.of(_viewed);
    _read.clear();
    _viewed.clear();
    for (final chat in {...read.keys, ...viewed.keys}) {
      final sent = _sent[chat] ?? 0;
      final upTo = math.max(sent, read[chat] ?? 0);
      final seen = viewed[chat] ?? const <int>{};
      // The posts between the position Telegram has and the newest post read are read
      // now; with them goes the newest one itself.
      final nowRead = {
        ...seen.where((id) => id > sent && id <= upTo),
        if (upTo > sent) upTo,
      }.toList()..sort();
      // Posts read long ago, and posts on the screen that are not read yet, only count
      // a view: the read position stays where it is.
      final onlySeen = seen.where((id) => id <= sent || id > upTo).toList()
        ..sort();
      (_counted[chat] ??= {}).addAll(seen);
      if (nowRead.isNotEmpty) {
        _sent[chat] = upTo;
        try {
          await gateway.markViewed(chat, nowRead);
        } on TelegramException {
          // The chat is gone or Telegram refused; the next reading tries again.
          _sent[chat] = sent;
          _counted[chat]?.removeAll(nowRead);
        }
      }
      if (onlySeen.isNotEmpty) {
        try {
          await gateway.countViews(chat, onlySeen);
        } on TelegramException {
          _counted[chat]?.removeAll(onlySeen);
        }
      }
    }
  }

  Future<void> dispose() => flush();
}
