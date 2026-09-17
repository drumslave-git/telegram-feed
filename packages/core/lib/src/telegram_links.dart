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

/// Link to put on the share sheet or the clipboard: the public `t.me` link when
/// the channel has a username, otherwise the `t.me/c` link (opens only for
/// members). Null for chats that are not channels.
Uri? telegramShareUri({
  required int chatId,
  required int messageId,
  String? username,
}) {
  if (username != null && username.isNotEmpty) {
    return Uri.https('t.me', '/$username/${messageId >> 20}');
  }
  return telegramPostWebUri(chatId: chatId, messageId: messageId);
}

/// Text for the share sheet: channel title, the start of the post, the link.
String shareText({
  required String channelTitle,
  required String text,
  required Uri link,
  int maxChars = 280,
}) {
  var body = text.trim().replaceAll(RegExp(r'\s*\n\s*'), '\n');
  if (body.length > maxChars) {
    body = '${body.substring(0, maxChars).trimRight()}…';
  }
  return [
    if (channelTitle.isNotEmpty) channelTitle,
    if (body.isNotEmpty) body,
    link.toString(),
  ].join('\n\n');
}

/// Web fallback for private channels when no Telegram app handles `tg://`.
Uri? telegramPostWebUri({required int chatId, required int messageId}) {
  final sg = supergroupIdOf(chatId);
  if (sg == null) return null;
  return Uri.https('t.me', '/c/$sg/${messageId >> 20}');
}
