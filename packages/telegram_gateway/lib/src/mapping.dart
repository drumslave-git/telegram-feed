import 'package:tdlib_bindings/tdlib_bindings.dart' as td;

import 'models.dart';

FileRef fileRef(td.File f, {int width = 0, int height = 0}) => FileRef(
  id: f.id,
  remoteId: f.remote?.id ?? '',
  size: f.size > 0 ? f.size : f.expectedSize,
  localPath: (f.local?.isDownloadingCompleted ?? false) ? f.local!.path : null,
  width: width,
  height: height,
);

FileRef? thumbRef(td.Thumbnail? t) => t?.file == null
    ? null
    : fileRef(t!.file!, width: t.width, height: t.height);

AuthState authState(td.AuthorizationState s) => switch (s) {
  td.AuthorizationStateWaitTdlibParameters() => const AuthStarting(),
  td.AuthorizationStateWaitPhoneNumber() => const AuthWaitPhoneNumber(),
  td.AuthorizationStateWaitOtherDeviceConfirmation(:final link) =>
    AuthWaitOtherDeviceConfirmation(link),
  td.AuthorizationStateWaitCode(:final codeInfo) => AuthWaitCode(
    phoneNumber: codeInfo?.phoneNumber ?? '',
    codeLength: switch (codeInfo?.type) {
      td.AuthenticationCodeTypeSms(:final length) => length,
      td.AuthenticationCodeTypeTelegramMessage(:final length) => length,
      td.AuthenticationCodeTypeCall(:final length) => length,
      td.AuthenticationCodeTypeFragment(:final length) => length,
      _ => 0,
    },
    viaSms: codeInfo?.type is td.AuthenticationCodeTypeSms,
  ),
  td.AuthorizationStateWaitRegistration() => const AuthWaitRegistration(),
  td.AuthorizationStateWaitPassword(:final passwordHint) => AuthWaitPassword(
    hint: passwordHint,
  ),
  td.AuthorizationStateReady() => const AuthReady(),
  td.AuthorizationStateLoggingOut() => const AuthLoggingOut(),
  td.AuthorizationStateClosing() => const AuthLoggingOut(),
  td.AuthorizationStateClosed() => const AuthClosed(),
  td.AuthorizationStateWaitEmailAddress() => const AuthWaitEmailAddress(),
  td.AuthorizationStateWaitEmailCode(:final codeInfo) => AuthWaitEmailCode(
    emailPattern: codeInfo?.emailAddressPattern ?? '',
    codeLength: codeInfo?.length ?? 0,
  ),
  // Telegram asks for a Premium purchase before the login goes on.
  _ => const AuthUnsupported(),
};

UserInfo user(td.User u, {String bio = ''}) => UserInfo(
  id: u.id,
  firstName: u.firstName,
  lastName: u.lastName,
  username: switch (u.usernames) {
    td.Usernames(:final editableUsername) when editableUsername.isNotEmpty =>
      editableUsername,
    td.Usernames(:final activeUsernames) when activeUsernames.isNotEmpty =>
      activeUsernames.first,
    _ => null,
  },
  phoneNumber: u.phoneNumber,
  photo: u.profilePhoto?.small == null ? null : fileRef(u.profilePhoto!.small!),
  bio: bio,
  isPremium: u.isPremium,
);

StorageStats storageStats(td.StorageStatisticsFast s) => StorageStats(
  filesBytes: s.filesSize,
  fileCount: s.fileCount,
  databaseBytes: s.databaseSize,
);

/// Chat id of a supergroup / channel as TDLib derives it.
int chatIdOfSupergroup(int supergroupId) => -1000000000000 - supergroupId;

bool isMemberStatus(td.ChatMemberStatus? s) => switch (s) {
  td.ChatMemberStatusCreator(:final isMember) => isMember,
  td.ChatMemberStatusAdministrator() => true,
  td.ChatMemberStatusMember() => true,
  td.ChatMemberStatusRestricted(:final isMember) => isMember,
  td.ChatMemberStatusLeft() => false,
  td.ChatMemberStatusBanned() => false,
  null => true,
};

Channel channel(td.Chat chat, td.Supergroup sg) => Channel(
  chatId: chat.id,
  title: chat.title,
  username: switch (sg.usernames) {
    td.Usernames(:final editableUsername) when editableUsername.isNotEmpty =>
      editableUsername,
    td.Usernames(:final activeUsernames) when activeUsernames.isNotEmpty =>
      activeUsernames.first,
    _ => null,
  },
  memberCount: sg.memberCount,
  photo: chat.photo?.small == null ? null : fileRef(chat.photo!.small!),
  isMember: isMemberStatus(sg.status),
  lastMessageId: chat.lastMessage?.id ?? 0,
  lastReadMessageId: chat.lastReadInboxMessageId,
  unreadCount: chat.unreadCount,
  lastMessageText: preview(chat.lastMessage?.content),
  lastMessageMedia: previewMedia(chat.lastMessage?.content),
  lastMessageDate: chat.lastMessage?.date ?? 0,
);

/// TDLib's filter for a [HistoryFilter]; null searches everything.
td.SearchMessagesFilter? searchFilter(HistoryFilter f) => switch (f) {
  HistoryFilter.any => null,
  HistoryFilter.photoAndVideo => const td.SearchMessagesFilterPhotoAndVideo(),
  HistoryFilter.document => const td.SearchMessagesFilterDocument(),
  HistoryFilter.url => const td.SearchMessagesFilterUrl(),
  HistoryFilter.audio => const td.SearchMessagesFilterAudio(),
  HistoryFilter.voice => const td.SearchMessagesFilterVoiceNote(),
};

/// One line for a channel list: the text or caption on one line; empty when there is
/// none, and [previewMedia] says what the post carries instead.
String preview(td.MessageContent? c) =>
    content(c).$1.replaceAll(RegExp(r'\s+'), ' ');

/// The media of a post without text, which the app names in its own language; null when
/// the post has text or nothing at all.
Media? previewMedia(td.MessageContent? c) {
  final (text, media) = content(c);
  return text.isEmpty ? media : null;
}

Post post(
  td.Message m, {
  ForwardOrigin? forwardedFrom,
  ReplyTarget? replyTo,
  List<Commenter> recentCommenters = const [],
}) {
  var (text, media) = content(m.content);
  // Content for adults is covered whatever else it is, as the official app covers it.
  if (m.restrictionInfo?.hasSensitiveContent ?? false) {
    media = switch (media) {
      final PhotoMedia photo => photo.covered(MediaCover.sensitive),
      final VideoMedia video => video.covered(MediaCover.sensitive),
      _ => media,
    };
  }
  return Post(
    chatId: m.chatId,
    messageId: m.id,
    date: m.date,
    editDate: m.editDate,
    text: text,
    albumId: m.mediaAlbumId,
    media: media,
    views: m.interactionInfo?.viewCount ?? 0,
    isOutgoing: m.isOutgoing,
    reactions: reactions(m.interactionInfo?.reactions),
    replyCount: m.interactionInfo?.replyInfo?.replyCount ?? 0,
    canComment: m.interactionInfo?.replyInfo != null,
    entities: entities(formattedText(m.content)),
    linkPreview: linkPreview(m.content),
    forwardedFrom: forwardedFrom ?? forwardOrigin(m),
    replyTo: replyTo ?? replyTarget(m),
    canBeSaved: m.canBeSaved,
    buttons: urlButtons(m.replyMarkup),
    signature: m.authorSignature,
    isPinned: m.isPinned,
    captionAbove: switch (m.content) {
      td.MessagePhoto(:final showCaptionAboveMedia) => showCaptionAboveMedia,
      td.MessageVideo(:final showCaptionAboveMedia) => showCaptionAboveMedia,
      td.MessageAnimation(:final showCaptionAboveMedia) =>
        showCaptionAboveMedia,
      _ => false,
    },
    recentCommenters: recentCommenters,
    hasUnreadComments: hasUnreadComments(m.interactionInfo?.replyInfo),
  );
}

/// The official app's rule for the dot on the comments bar: the thread has been read up to
/// somewhere, and its last comment is newer than that.
bool hasUnreadComments(td.MessageReplyInfo? info) =>
    info != null &&
    info.lastReadInboxMessageId != 0 &&
    info.lastReadInboxMessageId < info.lastMessageId;

/// The link buttons of an inline keyboard, in their rows; a row left with none is dropped.
List<List<UrlButton>> urlButtons(td.ReplyMarkup? markup) {
  if (markup is! td.ReplyMarkupInlineKeyboard) return const [];
  return [
    for (final row in markup.rows)
      if (row.any((b) => b.type is td.InlineKeyboardButtonTypeUrl))
        [
          for (final b in row)
            if (b.type case td.InlineKeyboardButtonTypeUrl(:final url))
              UrlButton(text: b.text, url: url),
        ],
  ];
}

/// A sticker on its own (custom emoji), null when TDLib sent no file with it.
StickerMedia? sticker(td.Sticker s) {
  final file = s.sticker;
  if (file == null) return null;
  return StickerMedia(
    file: fileRef(file, width: s.width, height: s.height),
    format: switch (s.format) {
      td.StickerFormatTgs() => StickerFormat.tgs,
      td.StickerFormatWebm() => StickerFormat.webm,
      _ => StickerFormat.webp,
    },
    width: s.width,
    height: s.height,
    emoji: s.emoji,
    thumbnail: thumbRef(s.thumbnail),
  );
}

/// The post a post answers. A reply inside the same channel carries nothing but the ids, so
/// the gateway fetches that post for its words; a reply to another chat comes with the
/// origin and the content already.
ReplyTarget? replyTarget(td.Message m) {
  // Stories are out of scope (SPEC 5), and so is answering one.
  if (m.replyTo is! td.MessageReplyToMessage) return null;
  final r = m.replyTo! as td.MessageReplyToMessage;
  return ReplyTarget(
    chatId: r.chatId == 0 ? m.chatId : r.chatId,
    messageId: r.messageId,
    title: switch (r.origin) {
      td.MessageOriginHiddenUser(:final senderName) => senderName,
      _ => '',
    },
    text: r.quote?.text?.text ?? (r.content == null ? '' : preview(r.content)),
    media: r.quote?.text?.text == null ? previewMedia(r.content) : null,
    manualQuote: r.quote?.isManual ?? false,
    photo: replyPhoto(r.content),
  );
}

/// Thumbnail of the answered post's media, for the little square in the block.
PhotoMedia? replyPhoto(td.MessageContent? c) {
  if (c == null) return null;
  final (_, media) = content(c);
  return switch (media) {
    PhotoMedia(:final sizes) when sizes.isNotEmpty => PhotoMedia(sizes: sizes),
    VideoMedia(:final thumbnail) when thumbnail != null => PhotoMedia(
      sizes: [thumbnail],
    ),
    DocumentMedia(:final thumbnail) when thumbnail != null => PhotoMedia(
      sizes: [thumbnail],
    ),
    _ => null,
  };
}

/// The origin of a reply to a post of another chat, for the gateway to name. A reply inside
/// the channel has none: its own name is the answer.
ForwardOrigin? replyOrigin(td.Message m) {
  if (m.replyTo is! td.MessageReplyToMessage) return null;
  return switch ((m.replyTo! as td.MessageReplyToMessage).origin) {
    td.MessageOriginChannel(:final chatId, :final messageId) => ForwardOrigin(
      chatId: chatId,
      messageId: messageId,
    ),
    td.MessageOriginChat(:final senderChatId) => ForwardOrigin(
      chatId: senderChatId,
    ),
    td.MessageOriginUser(:final senderUserId) => ForwardOrigin(
      userId: senderUserId,
    ),
    _ => null,
  };
}

/// Origin of a forwarded post, with the ids the gateway turns into a name.
ForwardOrigin? forwardOrigin(td.Message m) => switch (m.forwardInfo?.origin) {
  td.MessageOriginChannel(
    :final chatId,
    :final messageId,
    :final authorSignature,
  ) =>
    ForwardOrigin(
      chatId: chatId,
      messageId: messageId,
      signature: authorSignature,
    ),
  td.MessageOriginChat(:final senderChatId, :final authorSignature) =>
    ForwardOrigin(chatId: senderChatId, signature: authorSignature),
  td.MessageOriginUser(:final senderUserId) => ForwardOrigin(
    userId: senderUserId,
  ),
  // Someone whose privacy settings hide the account: TDLib gives the name itself.
  td.MessageOriginHiddenUser(:final senderName) => ForwardOrigin(
    title: senderName,
    hidden: true,
  ),
  null => null,
};

/// The card of a post that carries a link (TDLib's `linkPreview`, only on `messageText`).
LinkPreview? linkPreview(td.MessageContent? c) {
  if (c is! td.MessageText) return null;
  final p = c.linkPreview;
  if (p == null) return null;
  final (photo, isVideo, duration) = _previewPicture(p.type);
  return LinkPreview(
    url: p.url,
    kind: linkKind(p.type),
    displayUrl: p.displayUrl,
    siteName: p.siteName,
    title: p.title,
    author: p.author,
    description: p.description?.text ?? '',
    photo: photo,
    isVideo: isVideo,
    durationSeconds: duration,
    largeMedia: p.showLargeMedia,
    photoAbove: p.showMediaAboveDescription,
    aboveText: p.showAboveText,
  );
}

/// What a preview's link leads to inside Telegram, for the button on its card.
LinkKind linkKind(td.LinkPreviewType? t) => switch (t) {
  td.LinkPreviewTypeChat(:final type) =>
    type is td.InviteLinkChatTypeChannel ? LinkKind.channel : LinkKind.group,
  td.LinkPreviewTypeDirectMessagesChat() => LinkKind.channel,
  td.LinkPreviewTypeMessage() => LinkKind.message,
  td.LinkPreviewTypeUser(:final isBot) => isBot ? LinkKind.bot : LinkKind.user,
  td.LinkPreviewTypeBackground() => LinkKind.background,
  td.LinkPreviewTypeTheme() => LinkKind.theme,
  td.LinkPreviewTypeStickerSet() => LinkKind.stickers,
  td.LinkPreviewTypeVideoChat() ||
  td.LinkPreviewTypeGroupCall() => LinkKind.videoChat,
  td.LinkPreviewTypeStory() => LinkKind.story,
  td.LinkPreviewTypeChannelBoost() ||
  td.LinkPreviewTypeSupergroupBoost() => LinkKind.boost,
  td.LinkPreviewTypeShareableChatFolder() => LinkKind.chatFolder,
  td.LinkPreviewTypeWebApp() => LinkKind.webApp,
  _ => LinkKind.web,
};

/// Picture, video flag and length of a preview, by the kind of link it is. Kinds without a
/// picture (a chat, a sticker set, an invoice, anything newer than this app) give none and
/// the card is drawn from its text alone.
(PhotoMedia?, bool, int) _previewPicture(td.LinkPreviewType? t) => switch (t) {
  td.LinkPreviewTypePhoto(:final photo) => (_photo(photo), false, 0),
  td.LinkPreviewTypeArticle(:final photo) => (_photo(photo), false, 0),
  td.LinkPreviewTypeApp(:final photo) => (_photo(photo), false, 0),
  td.LinkPreviewTypeAlbum(:final media) => (
    _photo(switch (media.firstOrNull) {
      td.LinkPreviewAlbumMediaPhoto(:final photo) => photo,
      _ => null,
    }),
    false,
    0,
  ),
  td.LinkPreviewTypeVideo(:final video, :final cover) => (
    _photo(cover) ?? _thumb(video?.thumbnail),
    true,
    video?.duration ?? 0,
  ),
  td.LinkPreviewTypeEmbeddedVideoPlayer(:final thumbnail, :final duration) => (
    _photo(thumbnail),
    true,
    duration,
  ),
  td.LinkPreviewTypeEmbeddedAnimationPlayer(:final thumbnail) => (
    _photo(thumbnail),
    true,
    0,
  ),
  // An external video file has no picture of its own, only its length.
  td.LinkPreviewTypeExternalVideo(:final duration) => (null, true, duration),
  td.LinkPreviewTypeAnimation(:final animation) => (
    _thumb(animation?.thumbnail),
    true,
    animation?.duration ?? 0,
  ),
  td.LinkPreviewTypeDocument(:final document) => (
    _thumb(document?.thumbnail),
    false,
    0,
  ),
  td.LinkPreviewTypeAudio(:final audio) => (
    _thumb(audio?.albumCoverThumbnail),
    false,
    audio?.duration ?? 0,
  ),
  _ => (null, false, 0),
};

/// A TDLib photo as the sizes the card picks from, smallest first.
PhotoMedia? _photo(td.Photo? p) {
  final sizes = [
    for (final s in (p?.sizes ?? const <td.PhotoSize>[]).where(
      (s) => s.photo != null,
    ))
      fileRef(s.photo!, width: s.width, height: s.height),
  ]..sort((a, b) => a.width.compareTo(b.width));
  return sizes.isEmpty ? null : PhotoMedia(sizes: sizes);
}

/// A thumbnail as a one-size photo, for the kinds that carry no full picture.
PhotoMedia? _thumb(td.Thumbnail? t) {
  final ref = thumbRef(t);
  return ref == null ? null : PhotoMedia(sizes: [ref]);
}

/// The text or caption of a message with its formatting, for the kinds [content] reads.
td.FormattedText? formattedText(td.MessageContent? c) => switch (c) {
  td.MessageText(:final text) => text,
  td.MessagePhoto(:final caption) => caption,
  td.MessageVideo(:final caption) => caption,
  td.MessageAnimation(:final caption) => caption,
  td.MessageAudio(:final caption) => caption,
  td.MessageVoiceNote(:final caption) => caption,
  td.MessageDocument(:final caption) => caption,
  _ => null,
};

/// Formatting the app draws, custom emoji included; bank cards and the like stay plain
/// text.
List<TextEntity> entities(td.FormattedText? t) {
  if (t == null) return const [];
  final text = t.text;
  final out = <TextEntity>[];
  for (final e in t.entities) {
    if (e.length <= 0 || e.offset < 0 || e.offset + e.length > text.length) {
      continue;
    }
    final piece = text.substring(e.offset, e.offset + e.length);
    final (TextEntityKind?, String?) mapped = switch (e.type) {
      td.TextEntityTypeBold() => (TextEntityKind.bold, null),
      td.TextEntityTypeItalic() => (TextEntityKind.italic, null),
      td.TextEntityTypeUnderline() => (TextEntityKind.underline, null),
      td.TextEntityTypeStrikethrough() => (TextEntityKind.strikethrough, null),
      td.TextEntityTypeSpoiler() => (TextEntityKind.spoiler, null),
      td.TextEntityTypeCode() => (TextEntityKind.code, null),
      td.TextEntityTypePre() => (TextEntityKind.pre, null),
      td.TextEntityTypePreCode() => (TextEntityKind.pre, null),
      td.TextEntityTypeBlockQuote() => (TextEntityKind.quote, null),
      td.TextEntityTypeExpandableBlockQuote() => (TextEntityKind.quote, null),
      td.TextEntityTypeTextUrl(:final url) => (TextEntityKind.link, url),
      td.TextEntityTypeUrl() => (
        TextEntityKind.link,
        piece.contains('://') ? piece : 'https://$piece',
      ),
      td.TextEntityTypeMention() => (
        TextEntityKind.link,
        'https://t.me/${piece.replaceFirst('@', '')}',
      ),
      td.TextEntityTypeEmailAddress() => (TextEntityKind.link, 'mailto:$piece'),
      td.TextEntityTypeHashtag() => (TextEntityKind.hashtag, null),
      td.TextEntityTypeCashtag() => (TextEntityKind.hashtag, null),
      td.TextEntityTypePhoneNumber() => (
        TextEntityKind.phone,
        'tel:${piece.replaceAll(RegExp(r'[^0-9+]'), '')}',
      ),
      td.TextEntityTypeBotCommand() => (TextEntityKind.tag, null),
      // The id travels in the url slot; the app asks TDLib for the sticker behind it.
      td.TextEntityTypeCustomEmoji(:final customEmojiId) => (
        TextEntityKind.customEmoji,
        '$customEmojiId',
      ),
      _ => (null, null),
    };
    final kind = mapped.$1;
    if (kind == null) continue;
    final isEmoji = kind == TextEntityKind.customEmoji;
    out.add(
      TextEntity(
        offset: e.offset,
        length: e.length,
        kind: kind,
        url: isEmoji ? null : mapped.$2,
        customEmojiId: isEmoji ? mapped.$2 : null,
        language: switch (e.type) {
          td.TextEntityTypePreCode(:final language) when language.isNotEmpty =>
            language,
          _ => null,
        },
        expandable: e.type is td.TextEntityTypeExpandableBlockQuote,
      ),
    );
  }
  return out;
}

/// Thread a message belongs to (discussion threads are `messageTopicThread`), else 0.
int threadIdOf(td.Message m) => switch (m.topicId) {
  td.MessageTopicThread(:final messageThreadId) => messageThreadId,
  _ => 0,
};

/// Who wrote a comment: a user, or a channel or group commenting as itself.
typedef Sender = ({int id, String name, FileRef? photo});

Comment comment(td.Message m, Sender sender) => Comment(
  chatId: m.chatId,
  messageId: m.id,
  threadId: threadIdOf(m),
  date: m.date,
  text: content(m.content).$1,
  media: content(m.content).$2,
  author: sender.name,
  authorId: sender.id,
  authorPhoto: sender.photo,
  isOutgoing: m.isOutgoing,
  entities: entities(formattedText(m.content)),
);

List<Reaction> reactions(td.MessageReactions? r) => [
  for (final x in r?.reactions ?? const <td.MessageReaction>[])
    if (reactionName(x.type) case final name?)
      Reaction(emoji: name, count: x.totalCount, chosen: x.isChosen),
];

/// What the app calls a reaction (`Reaction.emoji`); null for a kind it does not know.
String? reactionName(td.ReactionType? type) => switch (type) {
  td.ReactionTypeEmoji(:final emoji) => emoji,
  td.ReactionTypeCustomEmoji(:final customEmojiId) => customReaction(
    '$customEmojiId',
  ),
  td.ReactionTypePaid() => paidReaction,
  _ => null,
};

/// Telegram's type for a reaction the app can send; null for the paid one.
td.ReactionType? reactionType(String name) {
  if (name == paidReaction) return null;
  final custom = customReactionId(name);
  if (custom == null) return td.ReactionTypeEmoji(emoji: name);
  final id = int.tryParse(custom);
  return id == null ? null : td.ReactionTypeCustomEmoji(customEmojiId: id);
}

/// The reactions a chat allows on a message, plain and custom emoji, each once: those
/// Telegram puts on top first. The paid one and those only Premium may send are left out.
List<String> availableEmoji(td.AvailableReactions a) => {
  for (final r in [...a.topReactions, ...a.popularReactions])
    if (!r.needsPremium && r.type is! td.ReactionTypePaid)
      ?reactionName(r.type),
}.toList();

String? _miniature(td.Minithumbnail? mini) =>
    mini == null || mini.data.isEmpty ? null : mini.data;

StickerMedia? _diceSticker(td.DiceStickers? state) => switch (state) {
  td.DiceStickersRegular(sticker: final dice?) => sticker(dice),
  _ => null,
};

MediaCover _spoiler(bool hasSpoiler) =>
    hasSpoiler ? MediaCover.spoiler : MediaCover.none;

/// Plain text plus media for a message content. Only text and captions are exposed, per SPEC.
(String, Media?) content(td.MessageContent? c) => switch (c) {
  td.MessageText(:final text) => (text?.text ?? '', null),
  td.MessagePhoto(:final photo, :final caption, :final hasSpoiler) => (
    caption?.text ?? '',
    PhotoMedia(
      sizes: [
        for (final s in (photo?.sizes ?? const <td.PhotoSize>[]).where(
          (s) => s.photo != null,
        ))
          fileRef(s.photo!, width: s.width, height: s.height),
      ]..sort((a, b) => a.width.compareTo(b.width)),
      cover: _spoiler(hasSpoiler),
      miniature: _miniature(photo?.minithumbnail),
    ),
  ),
  td.MessageVideo(:final video, :final caption, :final hasSpoiler)
      when video?.video != null =>
    (
      caption?.text ?? '',
      VideoMedia(
        file: fileRef(video!.video!, width: video.width, height: video.height),
        durationSeconds: video.duration,
        thumbnail: thumbRef(video.thumbnail),
        cover: _spoiler(hasSpoiler),
        miniature: _miniature(video.minithumbnail),
      ),
    ),
  td.MessageAnimation(:final animation, :final caption, :final hasSpoiler)
      when animation?.animation != null =>
    (
      caption?.text ?? '',
      VideoMedia(
        file: fileRef(
          animation!.animation!,
          width: animation.width,
          height: animation.height,
        ),
        durationSeconds: animation.duration,
        thumbnail: thumbRef(animation.thumbnail),
        isAnimation: true,
        cover: _spoiler(hasSpoiler),
        miniature: _miniature(animation.minithumbnail),
      ),
    ),
  td.MessageAudio(:final audio, :final caption) when audio?.audio != null => (
    caption?.text ?? '',
    AudioMedia(
      file: fileRef(audio!.audio!),
      durationSeconds: audio.duration,
      title: audio.title,
      performer: audio.performer,
    ),
  ),
  td.MessageVoiceNote(:final voiceNote, :final caption)
      when voiceNote?.voice != null =>
    (
      caption?.text ?? '',
      AudioMedia(
        file: fileRef(voiceNote!.voice!),
        durationSeconds: voiceNote.duration,
        isVoice: true,
      ),
    ),
  td.MessageSticker(:final sticker) when sticker?.sticker != null => (
    sticker!.emoji,
    StickerMedia(
      file: fileRef(
        sticker.sticker!,
        width: sticker.width,
        height: sticker.height,
      ),
      format: switch (sticker.format) {
        td.StickerFormatTgs() => StickerFormat.tgs,
        td.StickerFormatWebm() => StickerFormat.webm,
        _ => StickerFormat.webp,
      },
      width: sticker.width,
      height: sticker.height,
      emoji: sticker.emoji,
      thumbnail: thumbRef(sticker.thumbnail),
    ),
  ),
  td.MessageVideoNote(:final videoNote) when videoNote?.video != null => (
    '',
    VideoMedia(
      file: fileRef(
        videoNote!.video!,
        width: videoNote.length,
        height: videoNote.length,
      ),
      durationSeconds: videoNote.duration,
      thumbnail: thumbRef(videoNote.thumbnail),
      isVideoNote: true,
    ),
  ),
  td.MessageDocument(:final document, :final caption)
      when document?.document != null =>
    (
      caption?.text ?? '',
      DocumentMedia(
        file: fileRef(document!.document!),
        fileName: document.fileName,
        mimeType: document.mimeType,
        thumbnail: thumbRef(document.thumbnail),
      ),
    ),
  // One emoji that Telegram animates is still a post with that emoji as its text.
  td.MessageAnimatedEmoji(:final emoji) => (emoji, null),
  td.MessagePinMessage(:final messageId) => (
    '',
    ServiceNote(ServiceKind.pinned, messageId: messageId),
  ),
  td.MessageChatChangeTitle(:final title) => (
    '',
    ServiceNote(ServiceKind.titleChanged, title: title),
  ),
  td.MessageChatChangePhoto() => (
    '',
    const ServiceNote(ServiceKind.photoChanged),
  ),
  td.MessageChatDeletePhoto() => (
    '',
    const ServiceNote(ServiceKind.photoRemoved),
  ),
  td.MessageSupergroupChatCreate() => (
    '',
    const ServiceNote(ServiceKind.channelCreated),
  ),
  td.MessageVideoChatStarted() => (
    '',
    const ServiceNote(ServiceKind.liveStarted),
  ),
  td.MessageVideoChatEnded(:final duration) => (
    '',
    ServiceNote(ServiceKind.liveEnded, seconds: duration),
  ),
  td.MessageVideoChatScheduled(:final startDate) => (
    '',
    ServiceNote(ServiceKind.liveScheduled, seconds: startDate),
  ),
  td.MessageLocation(:final location) when location != null => (
    '',
    LocationMedia(latitude: location.latitude, longitude: location.longitude),
  ),
  td.MessageVenue(:final venue) when venue?.location != null => (
    '',
    LocationMedia(
      latitude: venue!.location!.latitude,
      longitude: venue.location!.longitude,
      title: venue.title,
      address: venue.address,
    ),
  ),
  td.MessageContact(:final contact) when contact != null => (
    '',
    ContactMedia(
      name: [
        contact.firstName,
        contact.lastName,
      ].where((s) => s.isNotEmpty).join(' '),
      phone: contact.phoneNumber,
      userId: contact.userId,
    ),
  ),
  // A dice is the sticker of what it came to; one TDLib has no sticker for (the slot
  // machine is drawn from parts) is its emoji, which a post of one emoji shows large.
  td.MessageDice(:final finalState, :final initialState)
      when _diceSticker(finalState ?? initialState) != null =>
    ('', _diceSticker(finalState ?? initialState)),
  td.MessageDice(:final emoji) when emoji.isNotEmpty => (emoji, null),
  td.MessageGame(:final game) when game != null => (
    game.text?.text ?? '',
    GameMedia(
      title: game.title,
      description: game.description,
      photo: _photo(game.photo),
    ),
  ),
  td.MessageChecklist(:final list) when list != null => (
    '',
    ChecklistMedia(
      title: list.title?.text ?? '',
      tasks: [
        for (final t in list.tasks)
          ChecklistTask(text: t.text?.text ?? '', done: t.completionDate != 0),
      ],
    ),
  ),
  null => ('', null),
  final other when _isContent(other) => (
    _captionOf(other),
    UnsupportedMedia(other.tdType),
  ),
  _ => ('', const ServiceNote(ServiceKind.other)),
};

/// Whether [c] is something a channel posted, which the app names when it cannot show it;
/// every other kind of message is a service message.
bool _isContent(td.MessageContent c) =>
    c is td.MessagePoll ||
    c is td.MessageLocation ||
    c is td.MessageLiveLocation ||
    c is td.MessageVenue ||
    c is td.MessageContact ||
    c is td.MessageDice ||
    c is td.MessageStakeDice ||
    c is td.MessageGame ||
    c is td.MessageInvoice ||
    c is td.MessageGiveaway ||
    c is td.MessageGiveawayWinners ||
    c is td.MessageStory ||
    c is td.MessageChecklist ||
    c is td.MessagePaidMedia ||
    c is td.MessageRichMessage ||
    c is td.MessageExpiredPhoto ||
    c is td.MessageExpiredVideo ||
    c is td.MessageExpiredVideoNote ||
    c is td.MessageExpiredVoiceNote ||
    c is td.MessageUnsupported ||
    // The kinds the app shows, when Telegram sends one without its file.
    c is td.MessageText ||
    c is td.MessagePhoto ||
    c is td.MessageVideo ||
    c is td.MessageAnimation ||
    c is td.MessageVideoNote ||
    c is td.MessageVoiceNote ||
    c is td.MessageAudio ||
    c is td.MessageDocument ||
    c is td.MessageSticker;

String _captionOf(td.MessageContent c) {
  final caption = c.toJson()['caption'];
  if (caption is Map && caption['text'] is String) {
    return caption['text'] as String;
  }
  return '';
}
