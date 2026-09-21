import 'package:app_db/app_db.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

/// "Mark all read", the action the official app has on a chat and a folder: Telegram's read
/// position of each channel moves to its newest post. A channel has one read position, so
/// it is read in every feed that holds it and in the official app alike.
class MarkRead {
  const MarkRead({required this.db, required this.gateway});
  final AppDatabase db;
  final TelegramGateway gateway;

  /// Every channel of the feed. Answers how many had anything unread.
  Future<int> feed(int feedId) async =>
      channels([for (final s in await db.sourcesOf(feedId)) s.chatId]);

  /// Channels themselves: a folder's tab, or one channel's row. Answers how many had
  /// anything unread.
  Future<int> channels(Iterable<int> chatIds) async {
    var moved = 0;
    for (final chat in chatIds.toSet()) {
      try {
        final state = await gateway.readState(chat);
        if (state.lastMessageId <= state.lastReadMessageId) continue;
        await gateway.markViewed(chat, [state.lastMessageId]);
        moved++;
      } on TelegramException {
        // A channel Telegram cannot tell about stays as it is.
      }
    }
    return moved;
  }
}
