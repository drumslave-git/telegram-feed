import 'dart:convert';

import 'package:telegram_gateway/telegram_gateway.dart';

/// Whether a feed wants posts with media, without, or both.
enum MediaPresence { any, withMedia, textOnly }

/// Kinds of media a filter can name. `other` is what the app shows as a label only
/// (polls, stickers, ...).
enum MediaKind { photo, video, gif, audio, voice, document, other }

MediaKind? mediaKindOf(Media? m) => switch (m) {
  null => null,
  PhotoMedia() => MediaKind.photo,
  VideoMedia(:final isAnimation) =>
    isAnimation ? MediaKind.gif : MediaKind.video,
  AudioMedia(:final isVoice) => isVoice ? MediaKind.voice : MediaKind.audio,
  DocumentMedia() => MediaKind.document,
  // A sticker is neither a picture nor a film; a feed of photos should not show one.
  StickerMedia() => MediaKind.other,
  UnsupportedMedia() => MediaKind.other,
};

/// What a feed shows of its channels' posts (`feeds.filter_json`). A post a feed hides also
/// raises no rule notification, unless another feed with the same channel shows it.
final class FeedFilter {
  const FeedFilter({
    this.media = MediaPresence.any,
    this.kinds = const {},
    this.minVideoSeconds = 0,
    this.minTextLength = 0,
    this.wholePost = true,
  });

  /// Shows everything.
  static const none = FeedFilter();

  final MediaPresence media;

  /// Media kinds that pass; empty means every kind. Posts without media are not affected.
  final Set<MediaKind> kinds;

  /// Videos shorter than this are hidden (GIFs are not videos here). 0 = no limit.
  final int minVideoSeconds;

  /// Posts without media whose text is shorter than this are hidden. 0 = no limit.
  final int minTextLength;

  /// An album whose parts do not all pass is shown whole, with the parts the filter would
  /// drop (founder decision 2026-09-19): the picture beside the video, and the caption
  /// that usually sits on it. Off shows only the parts that pass.
  final bool wholePost;

  /// True when nothing is hidden; [wholePost] alone changes nothing, it only softens the
  /// other four.
  bool get isEmpty =>
      media == MediaPresence.any &&
      kinds.isEmpty &&
      minVideoSeconds <= 0 &&
      minTextLength <= 0;

  bool allows(Post post) {
    final m = post.media;
    if (m == null) {
      if (media == MediaPresence.withMedia) return false;
      return post.text.trim().length >= minTextLength;
    }
    if (media == MediaPresence.textOnly) return false;
    if (kinds.isNotEmpty && !kinds.contains(mediaKindOf(m))) return false;
    if (m is VideoMedia &&
        !m.isAnimation &&
        m.durationSeconds < minVideoSeconds) {
      return false;
    }
    return true;
  }

  /// Whether the feed may show [post] on its own or in an album beside its siblings. With
  /// [wholePost] a part rides along with them; which siblings there are is not visible
  /// here, so only the media presence is judged and the row decides the rest
  /// ([FeedTimeline]). Where single messages are listed by kind — the shared media tabs —
  /// use [allows] instead.
  bool mayShow(Post post) =>
      allows(post) ||
      (wholePost && post.albumId != 0 && media != MediaPresence.textOnly);

  FeedFilter copyWith({
    MediaPresence? media,
    Set<MediaKind>? kinds,
    int? minVideoSeconds,
    int? minTextLength,
    bool? wholePost,
  }) => FeedFilter(
    media: media ?? this.media,
    kinds: kinds ?? this.kinds,
    minVideoSeconds: minVideoSeconds ?? this.minVideoSeconds,
    minTextLength: minTextLength ?? this.minTextLength,
    wholePost: wholePost ?? this.wholePost,
  );

  Map<String, Object?> toJson() => {
    if (media != MediaPresence.any) 'media': media.name,
    if (kinds.isNotEmpty)
      'kinds': [
        for (final k in MediaKind.values)
          if (kinds.contains(k)) k.name,
      ],
    if (minVideoSeconds > 0) 'minVideoSeconds': minVideoSeconds,
    if (minTextLength > 0) 'minTextLength': minTextLength,
    if (!wholePost) 'wholePost': false,
  };

  /// Null for a filter that shows everything, so the column stays empty.
  String? encode() => isEmpty && wholePost ? null : jsonEncode(toJson());

  /// Unknown values (from a newer version on another device) are ignored rather than fatal.
  static FeedFilter fromJson(Map<String, Object?> m) => FeedFilter(
    media: MediaPresence.values.asNameMap()[m['media']] ?? MediaPresence.any,
    kinds: {
      for (final k in (m['kinds'] as List?) ?? const [])
        ?MediaKind.values.asNameMap()[k],
    },
    minVideoSeconds: (m['minVideoSeconds'] as num?)?.toInt() ?? 0,
    minTextLength: (m['minTextLength'] as num?)?.toInt() ?? 0,
    // Absent in a filter written before the option existed: those feeds show whole posts
    // from now on too (founder decision 2026-09-19).
    wholePost: m['wholePost'] as bool? ?? true,
  );

  static FeedFilter decode(String? json) {
    if (json == null || json.isEmpty) return none;
    try {
      return fromJson((jsonDecode(json) as Map).cast<String, Object?>());
    } on FormatException {
      return none;
    } on TypeError {
      return none;
    }
  }

  /// Short description for lists, e.g. "with media · photos, videos · videos from 1 min".
  String describe() {
    if (isEmpty) return 'Everything';
    String duration(int s) => s % 60 == 0 ? '${s ~/ 60} min' : '$s s';
    return [
      if (media == MediaPresence.withMedia) 'with media',
      if (media == MediaPresence.textOnly) 'text only',
      if (kinds.isNotEmpty)
        [
          for (final k in MediaKind.values)
            if (kinds.contains(k)) k.label,
        ].join(', '),
      if (minVideoSeconds > 0) 'videos from ${duration(minVideoSeconds)}',
      if (minTextLength > 0) 'text from $minTextLength characters',
      if (!wholePost) 'matching parts only',
    ].join(' · ');
  }

  @override
  bool operator ==(Object other) =>
      other is FeedFilter &&
      other.media == media &&
      other.minVideoSeconds == minVideoSeconds &&
      other.minTextLength == minTextLength &&
      other.wholePost == wholePost &&
      other.kinds.length == kinds.length &&
      other.kinds.containsAll(kinds);

  @override
  int get hashCode => Object.hash(
    media,
    minVideoSeconds,
    minTextLength,
    wholePost,
    Object.hashAllUnordered(kinds),
  );
}

/// What each kind of media is called. The feed's filter sheet and [FeedFilter.describe]
/// take their words from here, so a filter reads the same wherever it is shown.
extension MediaKindLabel on MediaKind {
  String get label => switch (this) {
    MediaKind.photo => 'photos',
    MediaKind.video => 'videos',
    MediaKind.gif => 'GIFs',
    MediaKind.audio => 'audio',
    MediaKind.voice => 'voice messages',
    MediaKind.document => 'files',
    MediaKind.other => 'other (polls, stickers, …)',
  };

  /// The same word to start a line with, as the filter's chips show it.
  String get chipLabel => label.startsWith('GIF')
      ? label
      : label[0].toUpperCase() + label.substring(1);
}
