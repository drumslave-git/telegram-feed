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

/// A Telegram link the app may be able to open itself: a channel by username, or a private
/// channel by its id, with the post it points at when it names one.
typedef TelegramTarget = ({String? username, int? chatId, int? messageId});

/// Reads a `t.me` or `tg://` link. Answers null for anything else — an invite link, a
/// sticker set, a phone number, a web page — which belongs to the browser or to the
/// official app. The message id is a TDLib one (the server id shifted left by 20 bits),
/// so the timeline can look for it straight away.
TelegramTarget? telegramTargetOf(Uri uri) {
  int? tdMessageId(String? raw) {
    final id = int.tryParse(raw ?? '');
    return id == null || id <= 0 ? null : id << 20;
  }

  int? privateChatId(String? raw) {
    final id = int.tryParse(raw ?? '');
    return id == null || id <= 0 ? null : -1000000000000 - id;
  }

  if (uri.scheme == 'tg') {
    final q = uri.queryParameters;
    return switch (uri.host.isEmpty ? uri.path : uri.host) {
      'resolve' when (q['domain'] ?? '').isNotEmpty => (
        username: q['domain'],
        chatId: null,
        messageId: tdMessageId(q['post']),
      ),
      'privatepost' when privateChatId(q['channel']) != null => (
        username: null,
        chatId: privateChatId(q['channel']),
        messageId: tdMessageId(q['post']),
      ),
      _ => null,
    };
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (uri.host != 't.me' && uri.host != 'telegram.me') return null;
  final parts = [
    for (final p in uri.pathSegments)
      if (p.isNotEmpty) p,
  ];
  if (parts.isEmpty) return null;
  // A private channel: t.me/c/<internal id>/<post>.
  if (parts.first == 'c') {
    final chatId = parts.length < 2 ? null : privateChatId(parts[1]);
    if (chatId == null) return null;
    return (
      username: null,
      chatId: chatId,
      messageId: parts.length < 3 ? null : tdMessageId(parts[2]),
    );
  }
  // Invite links and the app's own pages are not channels the app can open.
  const notChannels = {
    'joinchat',
    'addstickers',
    'addemoji',
    'addlist',
    'proxy',
    'socks',
    'share',
    'iv',
    'setlanguage',
    'confirmphone',
    'login',
    'boost',
    'giftcode',
    'm',
  };
  final first = parts.first;
  if (first.startsWith('+') || notChannels.contains(first.toLowerCase())) {
    return null;
  }
  return (
    username: first,
    chatId: null,
    messageId: parts.length < 2 ? null : tdMessageId(parts[1]),
  );
}
