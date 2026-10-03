/// App-level types exposed by [TelegramGateway]. Nothing above the gateway sees TDLib types.
library;

/// Authorization state machine as the UI needs it.
/// What TDLib says about its connection (`updateConnectionState`), for the line the
/// official app shows instead of the title while it is not [ready].
enum ConnectionStatus {
  waitingForNetwork,
  connecting,
  connectingToProxy,
  updating,
  ready,
}

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

/// Telegram wants an email address for this account: login codes will go there.
final class AuthWaitEmailAddress extends AuthState {
  const AuthWaitEmailAddress();
}

/// Telegram sent the login code to the account's email address.
final class AuthWaitEmailCode extends AuthState {
  const AuthWaitEmailCode({
    required this.emailPattern,
    required this.codeLength,
  });

  /// The address with most of it hidden, as Telegram gives it ("a***@example.com").
  final String emailPattern;

  /// 0 when the code length is unknown.
  final int codeLength;
}

/// A step of the login this app cannot do (Telegram asks for a Premium purchase first).
final class AuthUnsupported extends AuthState {
  const AuthUnsupported();
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
    this.lastMessageMedia,
    this.lastMessageDate = 0,
  });
  final int chatId;
  final String title;
  final String? username;
  final int memberCount;
  final FileRef? photo;

  /// Telegram's own unread counter for the channel.
  final int unreadCount;

  /// Text, media and unix time of the newest post, for channel lists. The app names the
  /// media in its own language when there is no text.
  final String lastMessageText;
  final Media? lastMessageMedia;
  final int lastMessageDate;

  /// Id of the newest post TDLib knows about (0 if none); cheap unread upper bound.
  final int lastMessageId;

  /// Telegram's own read position for the channel (`last_read_inbox_message_id`); a feed
  /// starts from it when the channel is added.
  final int lastReadMessageId;

  /// False once the account has left the channel (history may still be readable).
  final bool isMember;

  /// The same channel under another name: Saved Messages in the reader's language.
  Channel withTitle(String title) => Channel(
    chatId: chatId,
    title: title,
    username: username,
    memberCount: memberCount,
    photo: photo,
    isMember: isMember,
    lastMessageId: lastMessageId,
    lastReadMessageId: lastReadMessageId,
    unreadCount: unreadCount,
    lastMessageText: lastMessageText,
    lastMessageMedia: lastMessageMedia,
    lastMessageDate: lastMessageDate,
  );

  /// The same channel after its read state changed.
  Channel withRead(ReadState r) => Channel(
    chatId: chatId,
    title: title,
    username: username,
    memberCount: memberCount,
    photo: photo,
    isMember: isMember,
    lastMessageId: r.lastMessageId == 0 ? lastMessageId : r.lastMessageId,
    lastReadMessageId: r.lastReadMessageId,
    unreadCount: r.unreadCount,
    lastMessageText: lastMessageText,
    lastMessageMedia: lastMessageMedia,
    lastMessageDate: lastMessageDate,
  );

  @override
  String toString() => 'Channel($chatId, $title)';
}

/// Telegram's own read state of a channel. There is one per channel, shared by every feed
/// that holds it, the channel's own timeline and the official app.
final class ReadState {
  const ReadState({
    required this.chatId,
    required this.lastReadMessageId,
    this.unreadCount = 0,
    this.lastMessageId = 0,
  });
  final int chatId;

  /// `last_read_inbox_message_id`: every post up to it is read.
  final int lastReadMessageId;

  /// Telegram's count of the unread posts after it.
  final int unreadCount;

  /// Newest post TDLib knows of; 0 where the answer does not say (a change of the read
  /// state alone).
  final int lastMessageId;

  @override
  String toString() =>
      'ReadState($chatId, read $lastReadMessageId, unread $unreadCount)';
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

/// What a search of a channel's history looks for: words in everything, or one kind of
/// attachment (the shared media tabs of the official app).
enum HistoryFilter {
  /// Text search over every post.
  any,
  photoAndVideo,
  document,

  /// Posts containing a link.
  url,

  /// Music files, not voice messages.
  audio,
  voice,
}

/// One page of [TelegramGateway.searchHistory], newest first.
final class SearchPage {
  const SearchPage({
    this.posts = const [],
    this.totalCount = 0,
    this.nextFromMessageId = 0,
  });

  final List<Post> posts;

  /// Telegram's approximate count for the whole query; -1 when it does not know.
  final int totalCount;

  /// Where the next page starts; 0 when the end is reached.
  final int nextFromMessageId;

  bool get isLast => nextFromMessageId == 0;
}

/// What a channel's info screen shows beyond what a channel list needs ([Channel]).
/// One page of a search over every channel the account follows: TDLib pages this one with a
/// token of its own instead of a message id.
final class GlobalSearchPage {
  const GlobalSearchPage({
    required this.posts,
    required this.totalCount,
    required this.nextOffset,
  });
  final List<Post> posts;

  /// Telegram's estimate, -1 when it does not know.
  final int totalCount;

  /// Empty when there is nothing more.
  final String nextOffset;
}

final class ChannelInfo {
  const ChannelInfo({
    required this.chatId,
    this.description = '',
    this.memberCount = 0,
    this.inviteLink = '',
    this.bigPhoto,
  });
  final int chatId;
  final String description;
  final int memberCount;

  /// Primary invite link; empty unless this account may see it (administrators only).
  /// Public channels are linked by their username instead.
  final String inviteLink;

  /// Large profile photo for the header; the small one is [Channel.photo].
  final FileRef? bigPhoto;
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

/// Why a picture or a video is covered until the reader taps it: its author put it under
/// a spoiler, or Telegram marks the post as content for adults.
enum MediaCover { none, spoiler, sensitive }

final class PhotoMedia extends Media {
  const PhotoMedia({
    required this.sizes,
    this.cover = MediaCover.none,
    this.miniature,
  });

  /// Ascending by width; pick by target width.
  final List<FileRef> sizes;
  final MediaCover cover;

  /// Telegram's tiny preview of the picture (a JPEG of some forty pixels, in base64),
  /// which comes with the post itself: drawn blurred while the picture loads.
  final String? miniature;
  FileRef get largest => sizes.last;

  PhotoMedia covered(MediaCover cover) =>
      PhotoMedia(sizes: sizes, cover: cover, miniature: miniature);
}

final class VideoMedia extends Media {
  const VideoMedia({
    required this.file,
    required this.durationSeconds,
    this.thumbnail,
    this.isAnimation = false,
    this.isVideoNote = false,
    this.cover = MediaCover.none,
    this.miniature,
  });
  final FileRef file;
  final int durationSeconds;
  final FileRef? thumbnail;
  final MediaCover cover;

  /// Telegram's tiny preview of the video, as [PhotoMedia.miniature].
  final String? miniature;

  VideoMedia covered(MediaCover cover) => VideoMedia(
    file: file,
    durationSeconds: durationSeconds,
    thumbnail: thumbnail,
    isAnimation: isAnimation,
    isVideoNote: isVideoNote,
    cover: cover,
    miniature: miniature,
  );

  /// GIF-like animation (`messageAnimation`).
  final bool isAnimation;

  /// A round video message (`messageVideoNote`), drawn as a circle.
  final bool isVideoNote;
}

/// How a sticker is drawn: a picture, a Lottie animation or a small video.
enum StickerFormat { webp, tgs, webm }

/// A sticker (`messageSticker`). Animated ones are Lottie inside gzip (`tgs`) or WebM.
final class StickerMedia extends Media {
  const StickerMedia({
    required this.file,
    required this.format,
    this.width = 0,
    this.height = 0,
    this.emoji = '',
    this.thumbnail,
  });
  final FileRef file;
  final StickerFormat format;
  final int width;
  final int height;

  /// The emoji the sticker stands for; read aloud and search use it.
  final String emoji;

  /// Still picture of the sticker, shown until the file is there.
  final FileRef? thumbnail;
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

/// The post a post answers (TDLib's `message.reply_to`), as the official app shows it above
/// the text: whose post it was and a line of what it said, or the quote the author picked.
final class ReplyTarget {
  const ReplyTarget({
    required this.chatId,
    required this.messageId,
    this.title = '',
    this.text = '',
    this.media,
    this.manualQuote = false,
    this.photo,
  });

  /// The post answered. [chatId] is the post's own chat for a reply inside the channel.
  final int chatId;
  final int messageId;

  /// Whose post it is; empty for a reply inside the same channel, where the channel's own
  /// name is the answer.
  final String title;

  /// The quote, or the beginning of what the answered post said. Plain text: the block is
  /// one tap target.
  final String text;

  /// What the answered post carried, which the app names when it had no words.
  final Media? media;

  /// The author picked these words out of the post instead of answering all of it.
  final bool manualQuote;

  /// Thumbnail of the answered post's media, when it had any.
  final PhotoMedia? photo;

  ReplyTarget withTitle(String title) => ReplyTarget(
    chatId: chatId,
    messageId: messageId,
    title: title,
    text: text,
    media: media,
    manualQuote: manualQuote,
    photo: photo,
  );

  ReplyTarget withText(String text, {Media? media, PhotoMedia? photo}) =>
      ReplyTarget(
        chatId: chatId,
        messageId: messageId,
        title: title,
        text: text,
        media: media ?? this.media,
        manualQuote: manualQuote,
        photo: photo ?? this.photo,
      );

  @override
  String toString() => 'ReplyTarget($chatId/$messageId, "$text")';
}

/// Where a forwarded post came from (TDLib's `message.forward_info`): the line the official
/// app draws above the post, "Forwarded from `<name>`". The gateway fills [title] from
/// the id.
final class ForwardOrigin {
  const ForwardOrigin({
    this.title = '',
    this.chatId = 0,
    this.messageId = 0,
    this.userId = 0,
    this.signature = '',
    this.hidden = false,
  });

  /// Name of the channel, group or person the post came from.
  final String title;

  /// Origin channel or group, and the original post in it (0 when the origin is a person or
  /// hides itself); a tap can open it.
  final int chatId;
  final int messageId;

  /// Origin user, when a person forwarded their own message (0 otherwise).
  final int userId;

  /// Author signature the original post carried.
  final String signature;

  /// The sender hides their account: [title] is only the name they show.
  final bool hidden;

  ForwardOrigin withTitle(String title) => ForwardOrigin(
    title: title,
    chatId: chatId,
    messageId: messageId,
    userId: userId,
    signature: signature,
    hidden: hidden,
  );

  @override
  String toString() => 'ForwardOrigin($title, chat $chatId/$messageId)';
}

/// What a link in a post leads to, when it leads into Telegram: the card names it on a
/// button of its own, as the official app does. Everything else is [web].
enum LinkKind {
  web,
  channel,
  group,
  message,
  user,
  bot,
  background,
  theme,
  stickers,
  videoChat,
  story,
  boost,
  chatFolder,
  webApp,
}

/// The card under (or above) a post with a link: what TDLib hands over as `linkPreview` and
/// the official app draws with the site, the title, a description and a picture. It is not
/// [Post.media]: a post with a link stays a text post for a feed's filters.
final class LinkPreview {
  const LinkPreview({
    required this.url,
    this.kind = LinkKind.web,
    this.displayUrl = '',
    this.siteName = '',
    this.title = '',
    this.author = '',
    this.description = '',
    this.photo,
    this.isVideo = false,
    this.durationSeconds = 0,
    this.largeMedia = false,
    this.photoAbove = false,
    this.aboveText = false,
  });

  /// The link itself, which a tap on the card opens.
  final String url;
  final LinkKind kind;

  /// The link as the official app shows it in the card's corner.
  final String displayUrl;
  final String siteName;
  final String title;
  final String author;

  /// Plain text: the description carries formatting in TDLib, but the whole card is one tap
  /// target, so nothing inside it needs to be clickable.
  final String description;

  /// The card's picture, in the sizes TDLib offers.
  final PhotoMedia? photo;

  /// The link points at a video (a play badge goes on the picture; the tap still opens the
  /// link, since the app has no player for other sites).
  final bool isVideo;
  final int durationSeconds;

  /// TDLib's `show_large_media`: a wide picture of its own instead of a small square beside
  /// the text.
  final bool largeMedia;

  /// TDLib's `show_media_above_description`: the picture goes over the card's words.
  final bool photoAbove;

  /// TDLib's `show_above_text`: the card stands above the post's own text.
  final bool aboveText;

  @override
  String toString() =>
      'LinkPreview($url${title.isEmpty ? '' : ', $title'}'
      '${photo == null ? '' : ', photo'})';
}

/// What a service message says.
enum ServiceKind {
  pinned,
  titleChanged,
  photoChanged,
  photoRemoved,
  channelCreated,
  liveStarted,
  liveEnded,
  liveScheduled,

  /// A service message the app has no words for.
  other,
}

/// A service message: the channel pinned a post, changed its name or photo, started a
/// live stream. It is a line of its own in the timeline, not a post: no rule matches it.
final class ServiceNote extends Media {
  const ServiceNote(
    this.kind, {
    this.title = '',
    this.messageId = 0,
    this.seconds = 0,
  });
  final ServiceKind kind;

  /// The channel's new name ([ServiceKind.titleChanged]).
  final String title;

  /// The pinned post ([ServiceKind.pinned]); 0 when Telegram does not name it.
  final int messageId;

  /// How long the live stream ran ([ServiceKind.liveEnded]), or the unix time it is
  /// scheduled for ([ServiceKind.liveScheduled]).
  final int seconds;

  @override
  bool operator ==(Object other) =>
      other is ServiceNote &&
      other.kind == kind &&
      other.title == title &&
      other.messageId == messageId &&
      other.seconds == seconds;

  @override
  int get hashCode => Object.hash(kind, title, messageId, seconds);
}

/// Content the app does not draw (polls, locations, invoices, ...); [tdType] names it.
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
    this.authorId = 0,
    this.authorPhoto,
    this.isOutgoing = false,
    this.entities = const [],
    this.media,
  });
  final int chatId;
  final int messageId;
  final int threadId;
  final int date;

  /// The comment's words, or the caption of what it carries.
  final String text;

  /// The picture, video, sticker, voice message or file of the comment, if it has one.
  final Media? media;
  final String author;

  /// User id, or chat id of a channel or group commenting as itself; picks the colour of
  /// the name. 0 when unknown.
  final int authorId;

  /// Small profile photo of the author, if there is one.
  final FileRef? authorPhoto;
  final bool isOutgoing;

  /// Formatting of [text], as in [Post.entities].
  final List<TextEntity> entities;
}

/// An emoji reaction on a post with its count and whether this account chose it.
final class Reaction {
  const Reaction({
    required this.emoji,
    required this.count,
    this.chosen = false,
  });

  /// What the reaction is: a plain emoji, a custom emoji as [customReaction] names it, or
  /// [paidReaction].
  final String emoji;
  final int count;
  final bool chosen;
}

/// The reaction paid for with Telegram Stars. The app draws it and cannot send it.
const paidReaction = 'paid';

const _customReactionPrefix = 'custom:';

/// The name of a custom-emoji reaction: the id of its sticker behind a prefix no emoji has.
String customReaction(String stickerId) => '$_customReactionPrefix$stickerId';

/// The sticker id of a custom-emoji reaction; null for any other reaction.
String? customReactionId(String reaction) =>
    reaction.startsWith(_customReactionPrefix)
    ? reaction.substring(_customReactionPrefix.length)
    : null;

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

  /// Coloured like a link but without a target: bot commands.
  tag,

  /// A hashtag or a cashtag: a tap searches the timeline for it.
  hashtag,

  /// A phone number: [TextEntity.url] is its `tel:` address. A tap offers to call or copy.
  phone,

  /// A custom (premium) emoji: [TextEntity.customEmojiId] names the sticker to draw in
  /// place of the plain emoji the text carries.
  customEmoji,
}

/// Formatting of one range of [Post.text]; offsets count UTF-16 code units, like Dart
/// strings and like TDLib.
final class TextEntity {
  const TextEntity({
    required this.offset,
    required this.length,
    required this.kind,
    this.url,
    this.customEmojiId,
    this.language,
    this.expandable = false,
  });
  final int offset;
  final int length;
  final TextEntityKind kind;

  /// The programming language of a [TextEntityKind.pre] block, as its author named it;
  /// null or empty when they named none.
  final String? language;

  /// A [TextEntityKind.quote] that shows its first lines until the reader opens it.
  final bool expandable;

  /// Target of a [TextEntityKind.link].
  final String? url;

  /// Sticker id of a [TextEntityKind.customEmoji] (TDLib's int64 as a string).
  final String? customEmojiId;

  int get end => offset + length;

  @override
  bool operator ==(Object other) =>
      other is TextEntity &&
      other.offset == offset &&
      other.length == length &&
      other.kind == kind &&
      other.url == url &&
      other.customEmojiId == customEmojiId &&
      other.language == language &&
      other.expandable == expandable;
  @override
  int get hashCode => Object.hash(
    offset,
    length,
    kind,
    url,
    customEmojiId,
    language,
    expandable,
  );
  @override
  String toString() =>
      'TextEntity($kind $offset+$length${url == null ? '' : ' $url'})';
}

/// One channel post.
/// Someone who commented on a post: a user, or a chat that comments as itself.
final class Commenter {
  const Commenter({required this.id, this.name = '', this.photo});
  final int id;
  final String name;

  /// The small profile photo, when there is one.
  final FileRef? photo;

  @override
  bool operator ==(Object other) =>
      other is Commenter &&
      other.id == id &&
      other.name == name &&
      other.photo?.id == photo?.id;

  @override
  int get hashCode => Object.hash(id, name, photo?.id);
}

/// A button under a post that opens [url].
final class UrlButton {
  const UrlButton({required this.text, required this.url});
  final String text;
  final String url;

  @override
  bool operator ==(Object other) =>
      other is UrlButton && other.text == text && other.url == url;

  @override
  int get hashCode => Object.hash(text, url);

  @override
  String toString() => 'UrlButton($text, $url)';
}

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
    this.linkPreview,
    this.forwardedFrom,
    this.replyTo,
    this.canBeSaved = true,
    this.buttons = const [],
    this.signature = '',
    this.isPinned = false,
    this.captionAbove = false,
    this.recentCommenters = const [],
    this.hasUnreadComments = false,
  });
  final int chatId;
  final int messageId;

  /// Up to three of the people who commented last, newest first, for their photos on the
  /// comments bar.
  final List<Commenter> recentCommenters;

  /// The account has opened the comments before and there are newer ones since.
  final bool hasUnreadComments;

  /// The author's signature, in a channel that signs its posts; empty otherwise.
  final String signature;

  /// The post is pinned in its channel.
  final bool isPinned;

  /// The author put the caption over the picture or the video, not under it.
  final bool captionAbove;

  /// The buttons under the post that open a link, row by row as the channel laid them
  /// out. Buttons of other kinds talk to a bot and are left out.
  final List<List<UrlButton>> buttons;

  /// False for a post of a channel that protects its content: it may not be copied,
  /// forwarded, shared or saved, as Telegram says of it.
  final bool canBeSaved;

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

  /// The post's reactions: plain emoji, custom emoji and the paid one ([Reaction.emoji]).
  final List<Reaction> reactions;

  /// Comments in the linked discussion group (0 when the channel has none).
  final int replyCount;

  /// True when the post has a comment thread (the channel has a discussion group).
  final bool canComment;

  /// The link preview TDLib attached to the post, if it has one.
  final LinkPreview? linkPreview;

  /// Where the post was forwarded from, if it was.
  final ForwardOrigin? forwardedFrom;

  /// The post this one answers, if it answers one.
  final ReplyTarget? replyTo;

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
