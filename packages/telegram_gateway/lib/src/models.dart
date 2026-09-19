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
    this.lastReadMessageId = 0,
    this.unreadCount = 0,
    this.lastMessageText = '',
    this.lastMessageDate = 0,
  });
  final int chatId;
  final String title;
  final String? username;
  final int memberCount;
  final FileRef? photo;

  /// Telegram's own unread counter for the channel.
  final int unreadCount;

  /// Text (or a media label) and unix time of the newest post, for channel lists.
  final String lastMessageText;
  final int lastMessageDate;

  /// Id of the newest post TDLib knows about (0 if none); cheap unread upper bound.
  final int lastMessageId;

  /// Telegram's own read position for the channel (`last_read_inbox_message_id`); a feed
  /// starts from it when the channel is added.
  final int lastReadMessageId;

  /// False once the account has left the channel (history may still be readable).
  final bool isMember;

  @override
  String toString() => 'Channel($chatId, $title)';
}

/// A Telegram chat folder, reduced to the channels in it (the app reads channels only).
final class ChatFolder {
  const ChatFolder({
    required this.id,
    required this.title,
    required this.channelIds,
  });
  final int id;
  final String title;

  /// Chat ids in Telegram's order for the folder (pinned first, then by last post).
  final List<int> channelIds;
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
    this.partialPath = '',
  });
  final int fileId;
  final int downloaded;
  final int total;

  /// Set once the whole file is on disk.
  final String? localPath;

  /// Where TDLib keeps the file while it downloads (bytes sit at their final offsets), or the
  /// finished file. Empty before anything is written. TDLib moves the file when it completes.
  final String partialPath;
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

/// A post's discussion thread, hosted in the channel's linked discussion group.
final class Thread {
  const Thread({
    required this.chatId,
    required this.threadId,
    required this.postChatId,
    required this.postMessageId,
    required this.replyCount,
  });

  /// The discussion group chat.
  final int chatId;

  /// Root message id of the thread inside [chatId] (what replies point at).
  final int threadId;
  final int postChatId;
  final int postMessageId;
  final int replyCount;
}

/// One comment in a thread.
final class Comment {
  const Comment({
    required this.chatId,
    required this.messageId,
    required this.threadId,
    required this.date,
    required this.text,
    required this.author,
    this.isOutgoing = false,
  });
  final int chatId;
  final int messageId;
  final int threadId;
  final int date;
  final String text;
  final String author;
  final bool isOutgoing;
}

/// An emoji reaction on a post with its count and whether this account chose it.
final class Reaction {
  const Reaction({
    required this.emoji,
    required this.count,
    this.chosen = false,
  });
  final String emoji;
  final int count;
  final bool chosen;
}

/// How a stretch of a post's text is set.
enum TextEntityKind {
  bold,
  italic,
  underline,
  strikethrough,
  spoiler,

  /// Inline monospace.
  code,

  /// A monospace block.
  pre,
  quote,

  /// Opens [TextEntity.url]: links, text links, mentions, e-mail addresses.
  link,

  /// Coloured like a link but without a target: hashtags, cashtags, bot commands.
  tag,
}

/// Formatting of one range of [Post.text]; offsets count UTF-16 code units, like Dart
/// strings and like TDLib.
final class TextEntity {
  const TextEntity({
    required this.offset,
    required this.length,
    required this.kind,
    this.url,
  });
  final int offset;
  final int length;
  final TextEntityKind kind;

  /// Target of a [TextEntityKind.link].
  final String? url;

  int get end => offset + length;

  @override
  bool operator ==(Object other) =>
      other is TextEntity &&
      other.offset == offset &&
      other.length == length &&
      other.kind == kind &&
      other.url == url;
  @override
  int get hashCode => Object.hash(offset, length, kind, url);
  @override
  String toString() =>
      'TextEntity($kind $offset+$length${url == null ? '' : ' $url'})';
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
    this.reactions = const [],
    this.replyCount = 0,
    this.canComment = false,
    this.entities = const [],
  });
  final int chatId;
  final int messageId;

  /// Unix seconds.
  final int date;

  /// Plain text: message text or media caption.
  final String text;

  /// Formatting and links of [text]. Rules, read-aloud and sharing use the plain text only.
  final List<TextEntity> entities;
  final int editDate;

  /// `media_album_id`, 0 when not part of an album.
  final int albumId;
  final Media? media;
  final int views;
  final bool isOutgoing;

  /// Emoji reactions (custom-emoji and paid reactions are not shown).
  final List<Reaction> reactions;

  /// Comments in the linked discussion group (0 when the channel has none).
  final int replyCount;

  /// True when the post has a comment thread (the channel has a discussion group).
  final bool canComment;

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

/// The logged-in account.
final class UserInfo {
  const UserInfo({
    required this.id,
    required this.firstName,
    this.lastName = '',
    this.username,
    this.phoneNumber = '',
    this.photo,
    this.bio = '',
    this.isPremium = false,
  });
  final int id;
  final String firstName;
  final String lastName;
  final String? username;

  /// Digits as Telegram stores them, without the leading `+`.
  final String phoneNumber;

  /// Small profile photo (160x160), if the account has one.
  final FileRef? photo;
  final String bio;
  final bool isPremium;

  /// [phoneNumber] the way people write it.
  String get phoneDisplay => phoneNumber.isEmpty || phoneNumber.startsWith('+')
      ? phoneNumber
      : '+$phoneNumber';

  String get displayName =>
      [firstName, lastName].where((s) => s.isNotEmpty).join(' ');
}

/// TDLib storage use in bytes.
final class StorageStats {
  const StorageStats({
    required this.filesBytes,
    required this.fileCount,
    required this.databaseBytes,
  });
  final int filesBytes;
  final int fileCount;
  final int databaseBytes;
  int get totalBytes => filesBytes + databaseBytes;
}

/// Error returned by Telegram / TDLib for a request.
final class TelegramException implements Exception {
  const TelegramException(this.code, this.message);
  final int code;
  final String message;
  @override
  String toString() => 'TelegramException($code, $message)';
}
