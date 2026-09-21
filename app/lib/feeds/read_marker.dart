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

  /// Chat id → newest message id already sent.
  final _sent = <int, int>{};
  Timer? _timer;

  /// Records that everything of each chat up to the id in [read] is read, and that the
  /// posts in [viewed] were on the screen. Cheap; Telegram hears of it after [debounce].
  void read(Map<int, int> read, {Map<int, Iterable<int>> viewed = const {}}) {
    var changed = false;
    read.forEach((chat, id) {
      if (id > (_read[chat] ?? 0) && id > (_sent[chat] ?? 0)) {
        _read[chat] = id;
        changed = true;
      }
    });
    viewed.forEach((chat, ids) {
      final sent = _sent[chat] ?? 0;
      for (final id in ids) {
        if (id > sent && (_viewed[chat] ??= {}).add(id)) changed = true;
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
      final ids = {
        ...?viewed[chat],
        ?read[chat],
      }.where((id) => id > sent).toList()..sort();
      if (ids.isEmpty) continue;
      _sent[chat] = math.max(sent, ids.last);
      try {
        await gateway.markViewed(chat, ids);
      } on TelegramException {
        // The chat is gone or Telegram refused; the next reading tries again.
        _sent[chat] = sent;
      }
    }
  }

  Future<void> dispose() => flush();
}
