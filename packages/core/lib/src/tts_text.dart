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

/// A language guess from the script of [text], for platforms without a language
/// identifier (web). Latin script is ambiguous and yields null (the default language applies).
String? guessLanguageByScript(String text) {
  final counts = <String, int>{};
  for (final rune in text.runes) {
    final lang = switch (rune) {
      >= 0x0400 && <= 0x04FF => 'ru',
      >= 0x0370 && <= 0x03FF => 'el',
      >= 0x0590 && <= 0x05FF => 'he',
      >= 0x0600 && <= 0x06FF => 'ar',
      >= 0x0900 && <= 0x097F => 'hi',
      >= 0x0E00 && <= 0x0E7F => 'th',
      >= 0x3040 && <= 0x30FF => 'ja',
      >= 0xAC00 && <= 0xD7AF => 'ko',
      >= 0x4E00 && <= 0x9FFF => 'zh',
      _ => null,
    };
    if (lang != null) counts[lang] = (counts[lang] ?? 0) + 1;
  }
  if (counts.isEmpty) return null;
  // Japanese text mixes kana with CJK ideographs; any kana decides.
  if (counts.containsKey('ja')) return 'ja';
  return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}

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
