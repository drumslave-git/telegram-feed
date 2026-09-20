import 'package:app_db/app_db.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

/// "Mark all read", the action the official app has on a chat and a folder. Moves the read
/// marks of a feed (or of channels, for a folder or a single channel) to the newest post
/// each channel has, and moves Telegram's own read position with them when the reader asked
/// for that ([SettingKeys.syncReadToTelegram], on by default).
class MarkRead {
  const MarkRead({required this.db, required this.gateway});
  final AppDatabase db;
  final TelegramGateway gateway;

  /// Newest post per channel, which is what "everything" means here.
  Future<Map<int, int>> _newest(Iterable<int> chatIds) async {
    final wanted = chatIds.toSet();
    try {
      final channels = await gateway.myChannels();
      return {
        for (final c in channels)
          if (wanted.contains(c.chatId) && c.lastMessageId > 0)
            c.chatId: c.lastMessageId,
      };
    } on TelegramException {
      return const {};
    }
  }

  Future<bool> _syncsToTelegram() async =>
      (await db.setting(SettingKeys.syncReadToTelegram)) != 'false';

  /// Every channel of the feed, up to its newest post. Answers how many channels moved.
  Future<int> feed(int feedId) async {
    final sources = await db.watchSourceChannels(feedId).first;
    final newest = await _newest([for (final s in sources) s.chatId]);
    for (final entry in newest.entries) {
      await db.markRead(feedId, entry.key, entry.value);
    }
    await _viewInTelegram(newest);
    return newest.length;
  }

  /// Channels themselves (a folder's tab, or one channel's row): the app keeps no marks of
  /// its own for them, so this is Telegram's read position and the marks of every feed that
  /// holds them.
  Future<int> channels(Iterable<int> chatIds) async {
    final newest = await _newest(chatIds);
    for (final feed in await db.allFeeds()) {
      final sources = await db.watchSourceChannels(feed.id).first;
      for (final s in sources) {
        final id = newest[s.chatId];
        if (id != null) await db.markRead(feed.id, s.chatId, id);
      }
    }
    await _viewInTelegram(newest);
    return newest.length;
  }

  Future<void> _viewInTelegram(Map<int, int> newest) async {
    if (newest.isEmpty || !await _syncsToTelegram()) return;
    for (final entry in newest.entries) {
      try {
        await gateway.markViewed(entry.key, [entry.value]);
      } on TelegramException {
        // The app's own marks have moved; Telegram's can lag behind.
      }
    }
  }
}
