import 'package:telegram_gateway/telegram_gateway.dart';

/// What the kinds of media are called, in the interface language; English by default.
final class MediaWords {
  const MediaWords({
    this.photo = 'Photo',
    this.video = 'Video',
    this.gif = 'GIF',
    this.videoMessage = 'Video message',
    this.voiceMessage = 'Voice message',
    this.audio = 'Audio',
    this.sticker = 'Sticker',
    this.stickerWithEmoji = _englishSticker,
    this.post = 'Post',
  });

  final String photo;
  final String video;
  final String gif;
  final String videoMessage;
  final String voiceMessage;
  final String audio;
  final String sticker;

  /// A sticker named by the emoji it stands for.
  final String Function(String emoji) stickerWithEmoji;

  /// A post without text whose media the app does not show.
  final String post;

  static String _englishSticker(String emoji) => '$emoji Sticker';
}

/// What a post without text is called: in a search result, in the dry run of a rule and in
/// the notification of a rule with no condition, which notifies about such posts too.
String mediaLabel(Media? m, [MediaWords words = const MediaWords()]) =>
    switch (m) {
      PhotoMedia() => words.photo,
      VideoMedia(:final isAnimation, :final isVideoNote) =>
        isVideoNote
            ? words.videoMessage
            : isAnimation
            ? words.gif
            : words.video,
      // Read aloud says the emoji the sticker stands for, as the official app's preview
      // does.
      StickerMedia(:final emoji) =>
        emoji.isEmpty ? words.sticker : words.stickerWithEmoji(emoji),
      AudioMedia(:final isVoice) => isVoice ? words.voiceMessage : words.audio,
      DocumentMedia(:final fileName) => fileName,
      UnsupportedMedia() => words.post,
      ServiceNote() => words.post,
      null => words.post,
    };

/// The post's text, or what its media is called when it has none.
String postLabel(Post post, [MediaWords words = const MediaWords()]) =>
    post.text.trim().isEmpty ? mediaLabel(post.media, words) : post.text;
