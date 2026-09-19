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

  FeedFilter copyWith({
    MediaPresence? media,
    Set<MediaKind>? kinds,
    int? minVideoSeconds,
    int? minTextLength,
  }) => FeedFilter(
    media: media ?? this.media,
    kinds: kinds ?? this.kinds,
    minVideoSeconds: minVideoSeconds ?? this.minVideoSeconds,
    minTextLength: minTextLength ?? this.minTextLength,
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
  };

  /// Null for a filter that shows everything, so the column stays empty.
  String? encode() => isEmpty ? null : jsonEncode(toJson());

  /// Unknown values (from a newer version on another device) are ignored rather than fatal.
  static FeedFilter fromJson(Map<String, Object?> m) => FeedFilter(
    media: MediaPresence.values.asNameMap()[m['media']] ?? MediaPresence.any,
    kinds: {
      for (final k in (m['kinds'] as List?) ?? const [])
        ?MediaKind.values.asNameMap()[k],
    },
    minVideoSeconds: (m['minVideoSeconds'] as num?)?.toInt() ?? 0,
    minTextLength: (m['minTextLength'] as num?)?.toInt() ?? 0,
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

  /// Short description for lists, e.g. "with media · photo, video · videos from 1 min".
  String describe() {
    if (isEmpty) return 'Everything';
    String duration(int s) => s % 60 == 0 ? '${s ~/ 60} min' : '$s s';
    return [
      if (media == MediaPresence.withMedia) 'with media',
      if (media == MediaPresence.textOnly) 'text only',
      if (kinds.isNotEmpty)
        [
          for (final k in MediaKind.values)
            if (kinds.contains(k)) k.name,
        ].join(', '),
      if (minVideoSeconds > 0) 'videos from ${duration(minVideoSeconds)}',
      if (minTextLength > 0) 'text from $minTextLength characters',
    ].join(' · ');
  }

  @override
  bool operator ==(Object other) =>
      other is FeedFilter &&
      other.media == media &&
      other.minVideoSeconds == minVideoSeconds &&
      other.minTextLength == minTextLength &&
      other.kinds.length == kinds.length &&
      other.kinds.containsAll(kinds);

  @override
  int get hashCode => Object.hash(
    media,
    minVideoSeconds,
    minTextLength,
    Object.hashAllUnordered(kinds),
  );
}
