/// Text preparation for read-aloud (ARCHITECTURE.md section 7): strip URLs (say "link"),
/// drop emoji and formatting markers, collapse whitespace, prepend the channel, truncate.
library;

final _url = RegExp(r'(https?://|www\.)[^\s<>()]+', caseSensitive: false);
final _mention = RegExp(r'(?<![\p{L}\p{N}_])@[A-Za-z0-9_]{3,}', unicode: true);
final _emoji = RegExp(
  r'[\p{Extended_Pictographic}\p{Emoji_Modifier}‍️]',
  unicode: true,
);
final _markers = RegExp(r'[*_~`#>|]+');
final _ws = RegExp(r'\s+');

/// The text to hand to the TTS engine, or an empty string when nothing is worth reading.
String prepareForSpeech(
  String text, {
  String? channelTitle,
  int maxChars = 600,
  String linkWord = 'link',
  String moreSuffix = '… and more',
}) {
  var t = text
      .replaceAll(_url, ' $linkWord ')
      .replaceAll(_mention, ' ')
      .replaceAll(_emoji, ' ')
      .replaceAll(_markers, ' ')
      .replaceAll(_ws, ' ')
      .trim();
  if (t.isEmpty) return '';
  if (t.length > maxChars) {
    var cut = t.lastIndexOf(RegExp(r'[.!?]\s'), maxChars);
    if (cut < maxChars ~/ 2) cut = t.lastIndexOf(' ', maxChars);
    if (cut < maxChars ~/ 2) cut = maxChars;
    t = '${t.substring(0, cut + 1).trimRight()}$moreSuffix';
  }
  final title = channelTitle?.trim();
  if (title != null && title.isNotEmpty) {
    final cleanTitle = title
        .replaceAll(_emoji, ' ')
        .replaceAll(_ws, ' ')
        .trim();
    return 'New post in $cleanTitle. $t';
  }
  return t;
}
