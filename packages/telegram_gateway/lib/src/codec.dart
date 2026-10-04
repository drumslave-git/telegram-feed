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
  AuthWaitEmailAddress() => {'state': 'waitEmailAddress'},
  AuthWaitEmailCode(:final emailPattern, :final codeLength) => {
    'state': 'waitEmailCode',
    'emailPattern': emailPattern,
    'codeLength': codeLength,
  },
  AuthUnsupported() => {'state': 'unsupported'},
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
  'waitEmailAddress' => const AuthWaitEmailAddress(),
  'waitEmailCode' => AuthWaitEmailCode(
    emailPattern: m['emailPattern'] as String,
    codeLength: m['codeLength'] as int,
  ),
  'unsupported' => const AuthUnsupported(),
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
  'lastMessageMedia': c.lastMessageMedia == null
      ? null
      : encodeMedia(c.lastMessageMedia!),
  'lastMessageDate': c.lastMessageDate,
  if (c.lastMessageAlbum.isNotEmpty)
    'lastMessageAlbum': c.lastMessageAlbum.map(encodeMedia).toList(),
  if (c.isMuted) 'isMuted': true,
  if (c.isVerified) 'isVerified': true,
  if (c.isMarkedUnread) 'isMarkedUnread': true,
  if (c.pinnedLists.isNotEmpty) 'pinnedLists': [...c.pinnedLists],
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
  lastMessageMedia: m['lastMessageMedia'] == null
      ? null
      : decodeMedia(m['lastMessageMedia'] as Map<Object?, Object?>),
  lastMessageDate: (m['lastMessageDate'] as int?) ?? 0,
  lastMessageAlbum: [
    for (final a in (m['lastMessageAlbum'] as List?) ?? const [])
      decodeMedia(a as Map<Object?, Object?>),
  ],
  isMuted: m['isMuted'] == true,
  isVerified: m['isVerified'] == true,
  isMarkedUnread: m['isMarkedUnread'] == true,
  pinnedLists: ((m['pinnedLists'] as List?) ?? const []).cast<int>().toList(),
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

MediaCover _decodeCover(Object? name) =>
    name == null ? MediaCover.none : MediaCover.values.byName(name as String);

Map<String, Object?> encodeMedia(Media m) => switch (m) {
  PhotoMedia(:final sizes, :final cover, :final miniature) => {
    'kind': 'photo',
    'sizes': sizes.map(encodeFileRef).toList(),
    if (cover != MediaCover.none) 'cover': cover.name,
    'mini': ?miniature,
  },
  VideoMedia(
    :final file,
    :final durationSeconds,
    :final thumbnail,
    :final isAnimation,
    :final isVideoNote,
    :final cover,
    :final miniature,
  ) =>
    {
      'kind': 'video',
      'file': encodeFileRef(file),
      'duration': durationSeconds,
      'thumbnail': _fileOrNull(thumbnail),
      'isAnimation': isAnimation,
      'isVideoNote': isVideoNote,
      if (cover != MediaCover.none) 'cover': cover.name,
      'mini': ?miniature,
    },
  AudioMedia(
    :final file,
    :final durationSeconds,
    :final title,
    :final performer,
    :final isVoice,
    :final fileName,
    :final mimeType,
  ) =>
    {
      'kind': 'audio',
      'file': encodeFileRef(file),
      'duration': durationSeconds,
      'title': title,
      'performer': performer,
      'isVoice': isVoice,
      if (fileName.isNotEmpty) 'fileName': fileName,
      if (mimeType.isNotEmpty) 'mimeType': mimeType,
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
  LocationMedia(
    :final latitude,
    :final longitude,
    :final title,
    :final address,
  ) =>
    {
      'kind': 'location',
      'lat': latitude,
      'lon': longitude,
      'title': title,
      'address': address,
    },
  ContactMedia(:final name, :final phone, :final userId) => {
    'kind': 'contact',
    'name': name,
    'phone': phone,
    'userId': userId,
  },
  GameMedia(:final title, :final description, :final photo) => {
    'kind': 'game',
    'title': title,
    'description': description,
    'photo': photo == null ? null : encodeMedia(photo),
  },
  ChecklistMedia(:final title, :final tasks) => {
    'kind': 'checklist',
    'title': title,
    'tasks': [
      for (final t in tasks) {'text': t.text, 'done': t.done},
    ],
  },
  UnsupportedMedia(:final tdType) => {'kind': 'unsupported', 'tdType': tdType},
  ServiceNote(:final kind, :final title, :final messageId, :final seconds) => {
    'kind': 'service',
    'service': kind.name,
    'title': title,
    'messageId': messageId,
    'seconds': seconds,
  },
};

Media decodeMedia(Map<Object?, Object?> m) => switch (m['kind']) {
  'photo' => PhotoMedia(
    sizes: (m['sizes'] as List)
        .map((e) => decodeFileRef(e as Map<Object?, Object?>))
        .toList(),
    cover: _decodeCover(m['cover']),
    miniature: m['mini'] as String?,
  ),
  'video' => VideoMedia(
    file: decodeFileRef(m['file'] as Map<Object?, Object?>),
    durationSeconds: m['duration'] as int,
    thumbnail: _decodeFileOrNull(m['thumbnail']),
    isAnimation: m['isAnimation'] as bool,
    isVideoNote: (m['isVideoNote'] as bool?) ?? false,
    cover: _decodeCover(m['cover']),
    miniature: m['mini'] as String?,
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
    fileName: (m['fileName'] as String?) ?? '',
    mimeType: (m['mimeType'] as String?) ?? '',
  ),
  'document' => DocumentMedia(
    file: decodeFileRef(m['file'] as Map<Object?, Object?>),
    fileName: m['fileName'] as String,
    mimeType: m['mimeType'] as String,
    thumbnail: _decodeFileOrNull(m['thumbnail']),
  ),
  'location' => LocationMedia(
    latitude: (m['lat'] as num).toDouble(),
    longitude: (m['lon'] as num).toDouble(),
    title: (m['title'] as String?) ?? '',
    address: (m['address'] as String?) ?? '',
  ),
  'contact' => ContactMedia(
    name: m['name'] as String,
    phone: m['phone'] as String,
    userId: (m['userId'] as int?) ?? 0,
  ),
  'game' => GameMedia(
    title: m['title'] as String,
    description: (m['description'] as String?) ?? '',
    photo: m['photo'] == null
        ? null
        : decodeMedia(m['photo'] as Map<Object?, Object?>) as PhotoMedia,
  ),
  'checklist' => ChecklistMedia(
    title: m['title'] as String,
    tasks: [
      for (final t in (m['tasks'] as List?) ?? const [])
        ChecklistTask(
          text: (t as Map)['text'] as String,
          done: t['done'] == true,
        ),
    ],
  ),
  'unsupported' => UnsupportedMedia(m['tdType'] as String),
  'service' => ServiceNote(
    ServiceKind.values.asNameMap()[m['service']] ?? ServiceKind.other,
    title: m['title'] as String? ?? '',
    messageId: m['messageId'] as int? ?? 0,
    seconds: m['seconds'] as int? ?? 0,
  ),
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
  if (!p.canBeSaved) 'protected': true,
  if (p.signature.isNotEmpty) 'signature': p.signature,
  if (p.isPinned) 'pinned': true,
  if (p.captionAbove) 'captionAbove': true,
  if (p.hasUnreadComments) 'unreadComments': true,
  if (p.recentCommenters.isNotEmpty)
    'commenters': [
      for (final c in p.recentCommenters)
        {'id': c.id, 'name': c.name, 'photo': _fileOrNull(c.photo)},
    ],
  if (p.buttons.isNotEmpty)
    'buttons': [
      for (final row in p.buttons)
        [
          for (final b in row) {'text': b.text, 'url': b.url},
        ],
    ],
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
          'media': p.replyTo!.media == null
              ? null
              : encodeMedia(p.replyTo!.media!),
          'manualQuote': p.replyTo!.manualQuote,
          'photo': p.replyTo!.photo == null
              ? null
              : encodeMedia(p.replyTo!.photo!),
        },
};

Map<String, Object?> encodeLinkPreview(LinkPreview p) => {
  'url': p.url,
  if (p.kind != LinkKind.web) 'kind': p.kind.name,
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
  kind: m['kind'] == null
      ? LinkKind.web
      : LinkKind.values.byName(m['kind'] as String),
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
      if (e.language != null) 'g': e.language,
      if (e.expandable) 'x': true,
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
      language: e['g'] as String?,
      expandable: e['x'] == true,
    ),
];

Map<String, Object?> encodeReportStep(ReportStep s) => switch (s) {
  ReportDone() => {'step': 'done'},
  ReportChoice(:final title, :final options) => {
    'step': 'choice',
    'title': title,
    'options': [
      for (final o in options) {'id': o.id, 'text': o.text},
    ],
  },
  ReportText(:final optionId, :final optional) => {
    'step': 'text',
    'optionId': optionId,
    'optional': optional,
  },
};

ReportStep decodeReportStep(Map<Object?, Object?> m) => switch (m['step']) {
  'choice' => ReportChoice(
    title: (m['title'] as String?) ?? '',
    options: [
      for (final o in (m['options'] as List?) ?? const [])
        ReportOption(id: (o as Map)['id'] as String, text: o['text'] as String),
    ],
  ),
  'text' => ReportText(
    optionId: m['optionId'] as String,
    optional: m['optional'] == true,
  ),
  _ => const ReportDone(),
};

Map<String, Object?> encodeThread(Thread t) => {
  'chatId': t.chatId,
  'threadId': t.threadId,
  'postChatId': t.postChatId,
  'postMessageId': t.postMessageId,
  'replyCount': t.replyCount,
  'lastReadId': t.lastReadId,
  'unreadCount': t.unreadCount,
  'write': t.write.name,
  'slowModeWait': t.slowModeWait,
  'slowModeDelay': t.slowModeDelay,
};

Thread decodeThread(Map<Object?, Object?> m) => Thread(
  chatId: m['chatId'] as int,
  threadId: m['threadId'] as int,
  postChatId: m['postChatId'] as int,
  postMessageId: m['postMessageId'] as int,
  replyCount: m['replyCount'] as int,
  lastReadId: (m['lastReadId'] as int?) ?? 0,
  unreadCount: (m['unreadCount'] as int?) ?? 0,
  write: ThreadWrite.values.asNameMap()[m['write']] ?? ThreadWrite.allowed,
  slowModeWait: (m['slowModeWait'] as int?) ?? 0,
  slowModeDelay: (m['slowModeDelay'] as int?) ?? 0,
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
  'media': c.media == null ? null : encodeMedia(c.media!),
  if (c.reactions.isNotEmpty)
    'reactions': [
      for (final r in c.reactions)
        {'emoji': r.emoji, 'count': r.count, 'chosen': r.chosen},
    ],
  if (c.replyTo != null)
    'replyTo': {
      'messageId': c.replyTo!.messageId,
      'author': c.replyTo!.author,
      'text': c.replyTo!.text,
    },
  if (c.sendState != CommentSend.sent) 'sendState': c.sendState.name,
  if (c.edited) 'edited': true,
};

Map<String, Object?> encodeCommentPage(CommentPage p) => {
  'comments': p.comments.map(encodeComment).toList(),
  'totalCount': p.totalCount,
  'nextFromMessageId': p.nextFromMessageId,
};

CommentPage decodeCommentPage(Map<Object?, Object?> m) => CommentPage(
  comments: [
    for (final c in m['comments'] as List)
      decodeComment(c as Map<Object?, Object?>),
  ],
  totalCount: m['totalCount'] as int,
  nextFromMessageId: m['nextFromMessageId'] as int,
);

Map<String, Object?> encodeCommentsGone(CommentsGone g) => {
  'chatId': g.chatId,
  // A list of its own: the ids may be a view that does not cross isolates.
  'messageIds': [...g.messageIds],
};

CommentsGone decodeCommentsGone(Map<Object?, Object?> m) => CommentsGone(
  chatId: m['chatId'] as int,
  messageIds: (m['messageIds'] as List).cast<int>(),
);

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
  media: m['media'] == null
      ? null
      : decodeMedia(m['media'] as Map<Object?, Object?>),
  reactions: [
    for (final r in (m['reactions'] as List?) ?? const [])
      Reaction(
        emoji: (r as Map)['emoji'] as String,
        count: r['count'] as int,
        chosen: r['chosen'] == true,
      ),
  ],
  replyTo: m['replyTo'] == null
      ? null
      : CommentReply(
          messageId: (m['replyTo'] as Map)['messageId'] as int,
          author: ((m['replyTo'] as Map)['author'] as String?) ?? '',
          text: ((m['replyTo'] as Map)['text'] as String?) ?? '',
        ),
  sendState: CommentSend.values.asNameMap()[m['sendState']] ?? CommentSend.sent,
  edited: m['edited'] == true,
);

Post decodePost(Map<Object?, Object?> m) => Post(
  canBeSaved: m['protected'] != true,
  signature: (m['signature'] as String?) ?? '',
  isPinned: m['pinned'] == true,
  captionAbove: m['captionAbove'] == true,
  hasUnreadComments: m['unreadComments'] == true,
  recentCommenters: [
    for (final c in (m['commenters'] as List?) ?? const [])
      Commenter(
        id: (c as Map)['id'] as int,
        name: (c['name'] as String?) ?? '',
        photo: _decodeFileOrNull(c['photo']),
      ),
  ],
  buttons: [
    for (final row in (m['buttons'] as List?) ?? const [])
      [
        for (final b in row as List)
          UrlButton(
            text: (b as Map)['text'] as String,
            url: b['url'] as String,
          ),
      ],
  ],
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
      media: r['media'] == null
          ? null
          : decodeMedia(r['media'] as Map<Object?, Object?>),
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
    // A list of its own: the event's may be a view (`cast`) that no SendPort to another
    // isolate group takes.
    'messageIds': [...messageIds],
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
