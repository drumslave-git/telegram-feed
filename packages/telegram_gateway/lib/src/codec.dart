/// Map encoding of the gateway models, for sending them between isolates and engines.
/// Only JSON-compatible values are used so the maps survive `SendPort` transfers across
/// isolate groups (UI engine ↔ service engine).
library;

import 'models.dart';

Map<String, Object?> encodeAuthState(AuthState s) => switch (s) {
  AuthStarting() => {'state': 'starting'},
  AuthWaitPhoneNumber() => {'state': 'waitPhoneNumber'},
  AuthWaitOtherDeviceConfirmation(:final link) => {
    'state': 'waitOtherDevice',
    'link': link,
  },
  AuthWaitCode(:final phoneNumber, :final codeLength, :final viaSms) => {
    'state': 'waitCode',
    'phoneNumber': phoneNumber,
    'codeLength': codeLength,
    'viaSms': viaSms,
  },
  AuthWaitRegistration() => {'state': 'waitRegistration'},
  AuthWaitPassword(:final hint) => {'state': 'waitPassword', 'hint': hint},
  AuthReady() => {'state': 'ready'},
  AuthLoggingOut() => {'state': 'loggingOut'},
  AuthClosed() => {'state': 'closed'},
};

AuthState decodeAuthState(Map<Object?, Object?> m) => switch (m['state']) {
  'starting' => const AuthStarting(),
  'waitPhoneNumber' => const AuthWaitPhoneNumber(),
  'waitOtherDevice' => AuthWaitOtherDeviceConfirmation(m['link'] as String),
  'waitCode' => AuthWaitCode(
    phoneNumber: m['phoneNumber'] as String,
    codeLength: m['codeLength'] as int,
    viaSms: m['viaSms'] as bool,
  ),
  'waitRegistration' => const AuthWaitRegistration(),
  'waitPassword' => AuthWaitPassword(hint: m['hint'] as String),
  'ready' => const AuthReady(),
  'loggingOut' => const AuthLoggingOut(),
  'closed' => const AuthClosed(),
  final other => throw ArgumentError('unknown auth state $other'),
};

Map<String, Object?> encodeFileRef(FileRef f) => {
  'id': f.id,
  'remoteId': f.remoteId,
  'size': f.size,
  'localPath': f.localPath,
  'width': f.width,
  'height': f.height,
};

FileRef decodeFileRef(Map<Object?, Object?> m) => FileRef(
  id: m['id'] as int,
  remoteId: m['remoteId'] as String,
  size: m['size'] as int,
  localPath: m['localPath'] as String?,
  width: m['width'] as int,
  height: m['height'] as int,
);

Map<String, Object?>? _fileOrNull(FileRef? f) =>
    f == null ? null : encodeFileRef(f);
FileRef? _decodeFileOrNull(Object? m) =>
    m == null ? null : decodeFileRef(m as Map<Object?, Object?>);

Map<String, Object?> encodeChannel(Channel c) => {
  'chatId': c.chatId,
  'title': c.title,
  'username': c.username,
  'memberCount': c.memberCount,
  'photo': _fileOrNull(c.photo),
  'isMember': c.isMember,
  'lastMessageId': c.lastMessageId,
  'lastReadMessageId': c.lastReadMessageId,
  'unreadCount': c.unreadCount,
  'lastMessageText': c.lastMessageText,
  'lastMessageDate': c.lastMessageDate,
};

Map<String, Object?> encodeChatFolder(ChatFolder f) => {
  'id': f.id,
  'title': f.title,
  'channelIds': f.channelIds,
};

ChatFolder decodeChatFolder(Map<Object?, Object?> m) => ChatFolder(
  id: m['id'] as int,
  title: m['title'] as String,
  channelIds: (m['channelIds'] as List).cast<int>(),
);

Channel decodeChannel(Map<Object?, Object?> m) => Channel(
  chatId: m['chatId'] as int,
  title: m['title'] as String,
  username: m['username'] as String?,
  memberCount: m['memberCount'] as int,
  photo: _decodeFileOrNull(m['photo']),
  isMember: m['isMember'] as bool,
  lastMessageId: (m['lastMessageId'] as int?) ?? 0,
  lastReadMessageId: (m['lastReadMessageId'] as int?) ?? 0,
  unreadCount: (m['unreadCount'] as int?) ?? 0,
  lastMessageText: (m['lastMessageText'] as String?) ?? '',
  lastMessageDate: (m['lastMessageDate'] as int?) ?? 0,
);

Map<String, Object?> encodeChannelInfo(ChannelInfo i) => {
  'chatId': i.chatId,
  'description': i.description,
  'memberCount': i.memberCount,
  'inviteLink': i.inviteLink,
  'bigPhoto': _fileOrNull(i.bigPhoto),
};

ChannelInfo decodeChannelInfo(Map<Object?, Object?> m) => ChannelInfo(
  chatId: m['chatId'] as int,
  description: m['description'] as String,
  memberCount: m['memberCount'] as int,
  inviteLink: m['inviteLink'] as String,
  bigPhoto: _decodeFileOrNull(m['bigPhoto']),
);

Map<String, Object?> encodeSearchPage(SearchPage p) => {
  'posts': p.posts.map(encodePost).toList(),
  'totalCount': p.totalCount,
  'nextFromMessageId': p.nextFromMessageId,
};

SearchPage decodeSearchPage(Map<Object?, Object?> m) => SearchPage(
  posts: [
    for (final p in m['posts'] as List) decodePost(p as Map<Object?, Object?>),
  ],
  totalCount: m['totalCount'] as int,
  nextFromMessageId: m['nextFromMessageId'] as int,
);

Map<String, Object?> encodeMedia(Media m) => switch (m) {
  PhotoMedia(:final sizes) => {
    'kind': 'photo',
    'sizes': sizes.map(encodeFileRef).toList(),
  },
  VideoMedia(
    :final file,
    :final durationSeconds,
    :final thumbnail,
    :final isAnimation,
    :final isVideoNote,
  ) =>
    {
      'kind': 'video',
      'file': encodeFileRef(file),
      'duration': durationSeconds,
      'thumbnail': _fileOrNull(thumbnail),
      'isAnimation': isAnimation,
      'isVideoNote': isVideoNote,
    },
  AudioMedia(
    :final file,
    :final durationSeconds,
    :final title,
    :final performer,
    :final isVoice,
  ) =>
    {
      'kind': 'audio',
      'file': encodeFileRef(file),
      'duration': durationSeconds,
      'title': title,
      'performer': performer,
      'isVoice': isVoice,
    },
  StickerMedia(
    :final file,
    :final format,
    :final width,
    :final height,
    :final emoji,
    :final thumbnail,
  ) =>
    {
      'kind': 'sticker',
      'file': encodeFileRef(file),
      'format': format.name,
      'width': width,
      'height': height,
      'emoji': emoji,
      'thumbnail': _fileOrNull(thumbnail),
    },
  DocumentMedia(
    :final file,
    :final fileName,
    :final mimeType,
    :final thumbnail,
  ) =>
    {
      'kind': 'document',
      'file': encodeFileRef(file),
      'fileName': fileName,
      'mimeType': mimeType,
      'thumbnail': _fileOrNull(thumbnail),
    },
  UnsupportedMedia(:final tdType) => {'kind': 'unsupported', 'tdType': tdType},
};

Media decodeMedia(Map<Object?, Object?> m) => switch (m['kind']) {
  'photo' => PhotoMedia(
    sizes: (m['sizes'] as List)
        .map((e) => decodeFileRef(e as Map<Object?, Object?>))
        .toList(),
  ),
  'video' => VideoMedia(
    file: decodeFileRef(m['file'] as Map<Object?, Object?>),
    durationSeconds: m['duration'] as int,
    thumbnail: _decodeFileOrNull(m['thumbnail']),
    isAnimation: m['isAnimation'] as bool,
    isVideoNote: (m['isVideoNote'] as bool?) ?? false,
  ),
  'sticker' => StickerMedia(
    file: decodeFileRef(m['file'] as Map<Object?, Object?>),
    format: StickerFormat.values.byName(m['format'] as String),
    width: (m['width'] as int?) ?? 0,
    height: (m['height'] as int?) ?? 0,
    emoji: (m['emoji'] as String?) ?? '',
    thumbnail: _decodeFileOrNull(m['thumbnail']),
  ),
  'audio' => AudioMedia(
    file: decodeFileRef(m['file'] as Map<Object?, Object?>),
    durationSeconds: m['duration'] as int,
    title: m['title'] as String,
    performer: m['performer'] as String,
    isVoice: m['isVoice'] as bool,
  ),
  'document' => DocumentMedia(
    file: decodeFileRef(m['file'] as Map<Object?, Object?>),
    fileName: m['fileName'] as String,
    mimeType: m['mimeType'] as String,
    thumbnail: _decodeFileOrNull(m['thumbnail']),
  ),
  'unsupported' => UnsupportedMedia(m['tdType'] as String),
  final other => throw ArgumentError('unknown media kind $other'),
};

Map<String, Object?> encodePost(Post p) => {
  'chatId': p.chatId,
  'messageId': p.messageId,
  'date': p.date,
  'editDate': p.editDate,
  'text': p.text,
  'albumId': p.albumId,
  'media': p.media == null ? null : encodeMedia(p.media!),
  'views': p.views,
  'isOutgoing': p.isOutgoing,
  'reactions': [
    for (final r in p.reactions)
      {'emoji': r.emoji, 'count': r.count, 'chosen': r.chosen},
  ],
  'replyCount': p.replyCount,
  'canComment': p.canComment,
  'entities': _encodeEntities(p.entities),
  'linkPreview': p.linkPreview == null
      ? null
      : encodeLinkPreview(p.linkPreview!),
  'forwardedFrom': p.forwardedFrom == null
      ? null
      : {
          'title': p.forwardedFrom!.title,
          'chatId': p.forwardedFrom!.chatId,
          'messageId': p.forwardedFrom!.messageId,
          'userId': p.forwardedFrom!.userId,
          'signature': p.forwardedFrom!.signature,
          'hidden': p.forwardedFrom!.hidden,
        },
  'replyTo': p.replyTo == null
      ? null
      : {
          'chatId': p.replyTo!.chatId,
          'messageId': p.replyTo!.messageId,
          'title': p.replyTo!.title,
          'text': p.replyTo!.text,
          'manualQuote': p.replyTo!.manualQuote,
          'photo': p.replyTo!.photo == null
              ? null
              : encodeMedia(p.replyTo!.photo!),
        },
};

Map<String, Object?> encodeLinkPreview(LinkPreview p) => {
  'url': p.url,
  'displayUrl': p.displayUrl,
  'siteName': p.siteName,
  'title': p.title,
  'author': p.author,
  'description': p.description,
  'photo': p.photo == null ? null : encodeMedia(p.photo!),
  'isVideo': p.isVideo,
  'duration': p.durationSeconds,
  'largeMedia': p.largeMedia,
  'photoAbove': p.photoAbove,
  'aboveText': p.aboveText,
};

LinkPreview decodeLinkPreview(Map<Object?, Object?> m) => LinkPreview(
  url: m['url'] as String,
  displayUrl: (m['displayUrl'] as String?) ?? '',
  siteName: (m['siteName'] as String?) ?? '',
  title: (m['title'] as String?) ?? '',
  author: (m['author'] as String?) ?? '',
  description: (m['description'] as String?) ?? '',
  photo: m['photo'] == null
      ? null
      : decodeMedia(m['photo'] as Map<Object?, Object?>) as PhotoMedia,
  isVideo: (m['isVideo'] as bool?) ?? false,
  durationSeconds: (m['duration'] as int?) ?? 0,
  largeMedia: (m['largeMedia'] as bool?) ?? false,
  photoAbove: (m['photoAbove'] as bool?) ?? false,
  aboveText: (m['aboveText'] as bool?) ?? false,
);

List<Map<String, Object?>> _encodeEntities(List<TextEntity> entities) => [
  for (final e in entities)
    {
      'o': e.offset,
      'l': e.length,
      'k': e.kind.name,
      'u': e.url,
      'e': e.customEmojiId,
    },
];

List<TextEntity> _decodeEntities(Object? list) => [
  for (final e in (list as List?) ?? const [])
    TextEntity(
      offset: (e as Map)['o'] as int,
      length: e['l'] as int,
      kind: TextEntityKind.values.byName(e['k'] as String),
      url: e['u'] as String?,
      customEmojiId: e['e'] as String?,
    ),
];

Map<String, Object?> encodeThread(Thread t) => {
  'chatId': t.chatId,
  'threadId': t.threadId,
  'postChatId': t.postChatId,
  'postMessageId': t.postMessageId,
  'replyCount': t.replyCount,
};

Thread decodeThread(Map<Object?, Object?> m) => Thread(
  chatId: m['chatId'] as int,
  threadId: m['threadId'] as int,
  postChatId: m['postChatId'] as int,
  postMessageId: m['postMessageId'] as int,
  replyCount: m['replyCount'] as int,
);

Map<String, Object?> encodeComment(Comment c) => {
  'chatId': c.chatId,
  'messageId': c.messageId,
  'threadId': c.threadId,
  'date': c.date,
  'text': c.text,
  'author': c.author,
  'authorId': c.authorId,
  'authorPhoto': _fileOrNull(c.authorPhoto),
  'isOutgoing': c.isOutgoing,
  'entities': _encodeEntities(c.entities),
};

Comment decodeComment(Map<Object?, Object?> m) => Comment(
  chatId: m['chatId'] as int,
  messageId: m['messageId'] as int,
  threadId: m['threadId'] as int,
  date: m['date'] as int,
  text: m['text'] as String,
  author: m['author'] as String,
  authorId: (m['authorId'] as int?) ?? 0,
  authorPhoto: _decodeFileOrNull(m['authorPhoto']),
  isOutgoing: m['isOutgoing'] as bool,
  entities: _decodeEntities(m['entities']),
);

Post decodePost(Map<Object?, Object?> m) => Post(
  chatId: m['chatId'] as int,
  messageId: m['messageId'] as int,
  date: m['date'] as int,
  editDate: m['editDate'] as int,
  text: m['text'] as String,
  albumId: m['albumId'] as int,
  media: m['media'] == null
      ? null
      : decodeMedia(m['media'] as Map<Object?, Object?>),
  views: m['views'] as int,
  isOutgoing: m['isOutgoing'] as bool,
  reactions: [
    for (final r in (m['reactions'] as List?) ?? const [])
      Reaction(
        emoji: (r as Map)['emoji'] as String,
        count: r['count'] as int,
        chosen: r['chosen'] as bool,
      ),
  ],
  replyCount: (m['replyCount'] as int?) ?? 0,
  canComment: (m['canComment'] as bool?) ?? false,
  entities: _decodeEntities(m['entities']),
  linkPreview: m['linkPreview'] == null
      ? null
      : decodeLinkPreview(m['linkPreview'] as Map<Object?, Object?>),
  forwardedFrom: switch (m['forwardedFrom']) {
    final Map<Object?, Object?> o => ForwardOrigin(
      title: (o['title'] as String?) ?? '',
      chatId: (o['chatId'] as int?) ?? 0,
      messageId: (o['messageId'] as int?) ?? 0,
      userId: (o['userId'] as int?) ?? 0,
      signature: (o['signature'] as String?) ?? '',
      hidden: (o['hidden'] as bool?) ?? false,
    ),
    _ => null,
  },
  replyTo: switch (m['replyTo']) {
    final Map<Object?, Object?> r => ReplyTarget(
      chatId: (r['chatId'] as int?) ?? 0,
      messageId: (r['messageId'] as int?) ?? 0,
      title: (r['title'] as String?) ?? '',
      text: (r['text'] as String?) ?? '',
      manualQuote: (r['manualQuote'] as bool?) ?? false,
      photo: r['photo'] == null
          ? null
          : decodeMedia(r['photo'] as Map<Object?, Object?>) as PhotoMedia,
    ),
    _ => null,
  },
);

Map<String, Object?> encodePostEvent(PostEvent e) => switch (e) {
  PostAdded(:final post) => {'kind': 'added', 'post': encodePost(post)},
  PostEdited(:final post) => {'kind': 'edited', 'post': encodePost(post)},
  PostsDeleted(:final chatId, :final messageIds) => {
    'kind': 'deleted',
    'chatId': chatId,
    'messageIds': messageIds,
  },
};

PostEvent decodePostEvent(Map<Object?, Object?> m) => switch (m['kind']) {
  'added' => PostAdded(decodePost(m['post'] as Map<Object?, Object?>)),
  'edited' => PostEdited(decodePost(m['post'] as Map<Object?, Object?>)),
  'deleted' => PostsDeleted(
    chatId: m['chatId'] as int,
    messageIds: (m['messageIds'] as List).cast<int>(),
  ),
  final other => throw ArgumentError('unknown post event $other'),
};

Map<String, Object?> encodeReadState(ReadState r) => {
  'chatId': r.chatId,
  'read': r.lastReadMessageId,
  'unread': r.unreadCount,
  'last': r.lastMessageId,
};

ReadState decodeReadState(Map<Object?, Object?> m) => ReadState(
  chatId: m['chatId'] as int,
  lastReadMessageId: m['read'] as int,
  unreadCount: m['unread'] as int,
  lastMessageId: m['last'] as int,
);

Map<String, Object?> encodeMembership(ChannelMembershipEvent e) => {
  'chatId': e.chatId,
  'isMember': e.isMember,
};

ChannelMembershipEvent decodeMembership(Map<Object?, Object?> m) =>
    ChannelMembershipEvent(
      chatId: m['chatId'] as int,
      isMember: m['isMember'] as bool,
    );

Map<String, Object?> encodeUser(UserInfo u) => {
  'id': u.id,
  'firstName': u.firstName,
  'lastName': u.lastName,
  'username': u.username,
  'phoneNumber': u.phoneNumber,
  'photo': _fileOrNull(u.photo),
  'bio': u.bio,
  'isPremium': u.isPremium,
};

UserInfo decodeUser(Map<Object?, Object?> m) => UserInfo(
  id: m['id'] as int,
  firstName: m['firstName'] as String,
  lastName: m['lastName'] as String,
  username: m['username'] as String?,
  phoneNumber: m['phoneNumber'] as String,
  photo: _decodeFileOrNull(m['photo']),
  bio: (m['bio'] as String?) ?? '',
  isPremium: (m['isPremium'] as bool?) ?? false,
);

Map<String, Object?> encodeStorage(StorageStats s) => {
  'filesBytes': s.filesBytes,
  'fileCount': s.fileCount,
  'databaseBytes': s.databaseBytes,
};

StorageStats decodeStorage(Map<Object?, Object?> m) => StorageStats(
  filesBytes: m['filesBytes'] as int,
  fileCount: m['fileCount'] as int,
  databaseBytes: m['databaseBytes'] as int,
);

Map<String, Object?> encodeFileProgress(FileProgress p) => {
  'fileId': p.fileId,
  'downloaded': p.downloaded,
  'total': p.total,
  'localPath': p.localPath,
  'partialPath': p.partialPath,
};

FileProgress decodeFileProgress(Map<Object?, Object?> m) => FileProgress(
  fileId: m['fileId'] as int,
  downloaded: m['downloaded'] as int,
  total: m['total'] as int,
  localPath: m['localPath'] as String?,
  partialPath: (m['partialPath'] as String?) ?? '',
);
