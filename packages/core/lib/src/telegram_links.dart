/// Deep links into the official Telegram apps (SPEC: "Open in Telegram").
library;

/// Supergroup/channel id encoded in a TDLib chat id (`-100<id>`), or null for other chats.
int? supergroupIdOf(int chatId) {
  const base = -1000000000000;
  if (chatId > base) return null;
  return base - chatId;
}

/// Link to a post: `https://t.me/<username>/<id>` for public channels, otherwise the
/// `tg://privatepost` scheme that only the Telegram app understands.
Uri? telegramPostUri({
  required int chatId,
  required int messageId,
  String? username,
}) {
  final tdMessageId = messageId;
  // TDLib message ids are server ids shifted left by 20 bits.
  final serverId = tdMessageId >> 20;
  if (username != null && username.isNotEmpty) {
    return Uri.https('t.me', '/$username/$serverId');
  }
  final sg = supergroupIdOf(chatId);
  if (sg == null) return null;
  return Uri.parse('tg://privatepost?channel=$sg&post=$serverId');
}

/// Web fallback for private channels when no Telegram app handles `tg://`.
Uri? telegramPostWebUri({required int chatId, required int messageId}) {
  final sg = supergroupIdOf(chatId);
  if (sg == null) return null;
  return Uri.https('t.me', '/c/$sg/${messageId >> 20}');
}
