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
  // Email and premium-purchase states are not supported by this client.
  _ => const AuthStarting(),
};

UserInfo user(td.User u) => UserInfo(
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
);

Post post(td.Message m) {
  final (text, media) = content(m.content);
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
  );
}

/// Plain text plus media for a message content. Only text and captions are exposed, per SPEC.
(String, Media?) content(td.MessageContent? c) => switch (c) {
  td.MessageText(:final text) => (text?.text ?? '', null),
  td.MessagePhoto(:final photo, :final caption) => (
    caption?.text ?? '',
    PhotoMedia(
      sizes: [
        for (final s in (photo?.sizes ?? const <td.PhotoSize>[]).where(
          (s) => s.photo != null,
        ))
          fileRef(s.photo!, width: s.width, height: s.height),
      ]..sort((a, b) => a.width.compareTo(b.width)),
    ),
  ),
  td.MessageVideo(:final video, :final caption) when video?.video != null => (
    caption?.text ?? '',
    VideoMedia(
      file: fileRef(video!.video!, width: video.width, height: video.height),
      durationSeconds: video.duration,
      thumbnail: thumbRef(video.thumbnail),
    ),
  ),
  td.MessageAnimation(:final animation, :final caption)
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
  null => ('', null),
  final other => (_captionOf(other), UnsupportedMedia(other.tdType)),
};

String _captionOf(td.MessageContent c) {
  final caption = c.toJson()['caption'];
  if (caption is Map && caption['text'] is String) {
    return caption['text'] as String;
  }
  return '';
}
