/// App-level types exposed by [TelegramGateway]. Nothing above the gateway sees TDLib types.
library;

/// Authorization state machine as the UI needs it.
sealed class AuthState {
  const AuthState();
}

/// TDLib is starting; nothing to do yet.
final class AuthStarting extends AuthState {
  const AuthStarting();
}

final class AuthWaitPhoneNumber extends AuthState {
  const AuthWaitPhoneNumber();
}

/// A login link for QR authentication; the phone app confirms it.
final class AuthWaitOtherDeviceConfirmation extends AuthState {
  const AuthWaitOtherDeviceConfirmation(this.link);
  final String link;
}

final class AuthWaitCode extends AuthState {
  const AuthWaitCode({
    required this.phoneNumber,
    required this.codeLength,
    required this.viaSms,
  });
  final String phoneNumber;

  /// 0 when the code length is unknown.
  final int codeLength;
  final bool viaSms;
}

final class AuthWaitRegistration extends AuthState {
  const AuthWaitRegistration();
}

final class AuthWaitPassword extends AuthState {
  const AuthWaitPassword({required this.hint});
  final String hint;
}

final class AuthReady extends AuthState {
  const AuthReady();
}

final class AuthLoggingOut extends AuthState {
  const AuthLoggingOut();
}

final class AuthClosed extends AuthState {
  const AuthClosed();
}

/// A channel the account is a member of.
final class Channel {
  const Channel({
    required this.chatId,
    required this.title,
    this.username,
    this.memberCount = 0,
    this.photo,
    this.isMember = true,
    this.lastMessageId = 0,
  });
  final int chatId;
  final String title;
  final String? username;
  final int memberCount;
  final FileRef? photo;

  /// Id of the newest post TDLib knows about (0 if none); cheap unread upper bound.
  final int lastMessageId;

  /// False once the account has left the channel (history may still be readable).
  final bool isMember;

  @override
  String toString() => 'Channel($chatId, $title)';
}

final class ChannelMembershipEvent {
  const ChannelMembershipEvent({required this.chatId, required this.isMember});
  final int chatId;
  final bool isMember;
}

/// A reference to a TDLib-managed file. [localPath] is set once downloaded.
final class FileRef {
  const FileRef({
    required this.id,
    required this.remoteId,
    required this.size,
    this.localPath,
    this.width = 0,
    this.height = 0,
  });
  final int id;
  final String remoteId;
  final int size;
  final String? localPath;
  final int width;
  final int height;

  bool get isDownloaded => localPath != null && localPath!.isNotEmpty;

  FileRef copyWith({String? localPath}) => FileRef(
    id: id,
    remoteId: remoteId,
    size: size,
    localPath: localPath ?? this.localPath,
    width: width,
    height: height,
  );
}

final class FileProgress {
  const FileProgress({
    required this.fileId,
    required this.downloaded,
    required this.total,
    this.localPath,
  });
  final int fileId;
  final int downloaded;
  final int total;
  final String? localPath;
  bool get isComplete => localPath != null && localPath!.isNotEmpty;
}

sealed class Media {
  const Media();
}

final class PhotoMedia extends Media {
  const PhotoMedia({required this.sizes});

  /// Ascending by width; pick by target width.
  final List<FileRef> sizes;
  FileRef get largest => sizes.last;
}

final class VideoMedia extends Media {
  const VideoMedia({
    required this.file,
    required this.durationSeconds,
    this.thumbnail,
    this.isAnimation = false,
  });
  final FileRef file;
  final int durationSeconds;
  final FileRef? thumbnail;

  /// GIF-like animation (`messageAnimation`).
  final bool isAnimation;
}

final class AudioMedia extends Media {
  const AudioMedia({
    required this.file,
    required this.durationSeconds,
    this.title = '',
    this.performer = '',
    this.isVoice = false,
  });
  final FileRef file;
  final int durationSeconds;
  final String title;
  final String performer;
  final bool isVoice;
}

final class DocumentMedia extends Media {
  const DocumentMedia({
    required this.file,
    required this.fileName,
    required this.mimeType,
    this.thumbnail,
  });
  final FileRef file;
  final String fileName;
  final String mimeType;
  final FileRef? thumbnail;
}

/// Content the app does not render yet (polls, stickers, ...); [tdType] names it.
final class UnsupportedMedia extends Media {
  const UnsupportedMedia(this.tdType);
  final String tdType;
}

/// One channel post.
final class Post {
  const Post({
    required this.chatId,
    required this.messageId,
    required this.date,
    required this.text,
    this.editDate = 0,
    this.albumId = 0,
    this.media,
    this.views = 0,
    this.isOutgoing = false,
  });
  final int chatId;
  final int messageId;

  /// Unix seconds.
  final int date;

  /// Plain text: message text or media caption.
  final String text;
  final int editDate;

  /// `media_album_id`, 0 when not part of an album.
  final int albumId;
  final Media? media;
  final int views;
  final bool isOutgoing;

  @override
  String toString() => 'Post($chatId/$messageId, ${text.length} chars)';
}

sealed class PostEvent {
  const PostEvent();
}

final class PostAdded extends PostEvent {
  const PostAdded(this.post);
  final Post post;
}

final class PostEdited extends PostEvent {
  const PostEdited(this.post);
  final Post post;
}

final class PostsDeleted extends PostEvent {
  const PostsDeleted({required this.chatId, required this.messageIds});
  final int chatId;
  final List<int> messageIds;
}

/// Error returned by Telegram / TDLib for a request.
final class TelegramException implements Exception {
  const TelegramException(this.code, this.message);
  final int code;
  final String message;
  @override
  String toString() => 'TelegramException($code, $message)';
}
