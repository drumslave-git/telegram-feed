import 'package:telegram_gateway/telegram_gateway.dart';

/// What a post without text is called: in a search result, in the dry run of a rule and in
/// the notification of a rule with no condition, which notifies about such posts too.
String mediaLabel(Media? m) => switch (m) {
  PhotoMedia() => 'Photo',
  VideoMedia(:final isAnimation, :final isVideoNote) =>
    isVideoNote
        ? 'Video message'
        : isAnimation
        ? 'GIF'
        : 'Video',
  // Read aloud says the emoji the sticker stands for, as the official app's preview does.
  StickerMedia(:final emoji) => emoji.isEmpty ? 'Sticker' : '$emoji Sticker',
  AudioMedia(:final isVoice) => isVoice ? 'Voice message' : 'Audio',
  DocumentMedia(:final fileName) => fileName,
  UnsupportedMedia() => 'Post',
  null => 'Post',
};

/// The post's text, or what its media is called when it has none.
String postLabel(Post post) =>
    post.text.trim().isEmpty ? mediaLabel(post.media) : post.text;
