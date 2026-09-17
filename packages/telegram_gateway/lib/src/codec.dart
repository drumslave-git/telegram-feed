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
};

Channel decodeChannel(Map<Object?, Object?> m) => Channel(
  chatId: m['chatId'] as int,
  title: m['title'] as String,
  username: m['username'] as String?,
  memberCount: m['memberCount'] as int,
  photo: _decodeFileOrNull(m['photo']),
  isMember: m['isMember'] as bool,
  lastMessageId: (m['lastMessageId'] as int?) ?? 0,
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
  ) =>
    {
      'kind': 'video',
      'file': encodeFileRef(file),
      'duration': durationSeconds,
      'thumbnail': _fileOrNull(thumbnail),
      'isAnimation': isAnimation,
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
};

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
  'isOutgoing': c.isOutgoing,
};

Comment decodeComment(Map<Object?, Object?> m) => Comment(
  chatId: m['chatId'] as int,
  messageId: m['messageId'] as int,
  threadId: m['threadId'] as int,
  date: m['date'] as int,
  text: m['text'] as String,
  author: m['author'] as String,
  isOutgoing: m['isOutgoing'] as bool,
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
};

UserInfo decodeUser(Map<Object?, Object?> m) => UserInfo(
  id: m['id'] as int,
  firstName: m['firstName'] as String,
  lastName: m['lastName'] as String,
  username: m['username'] as String?,
  phoneNumber: m['phoneNumber'] as String,
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
};

FileProgress decodeFileProgress(Map<Object?, Object?> m) => FileProgress(
  fileId: m['fileId'] as int,
  downloaded: m['downloaded'] as int,
  total: m['total'] as int,
  localPath: m['localPath'] as String?,
);
