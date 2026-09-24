/// What the app's banner shows of read-aloud (ARCHITECTURE 7): the post being read and how
/// many wait after it. The service host sends it to the app with
/// `FlutterForegroundTask.sendDataToMain` as `{'reading': ReadingNow.encode() or null}`
/// after every change, and the app asks for it with [askReading].
final class ReadingNow {
  const ReadingNow({
    required this.chatId,
    required this.messageId,
    required this.channelTitle,
    required this.waiting,
  });
  final int chatId;
  final int messageId;
  final String channelTitle;

  /// Posts queued after this one.
  final int waiting;

  Map<String, Object> encode() => {
    'chatId': chatId,
    'messageId': messageId,
    'title': channelTitle,
    'waiting': waiting,
  };

  static ReadingNow? decode(Object? m) => m is Map
      ? ReadingNow(
          chatId: m['chatId'] as int,
          messageId: m['messageId'] as int,
          channelTitle: m['title'] as String? ?? '',
          waiting: m['waiting'] as int? ?? 0,
        )
      : null;

  @override
  bool operator ==(Object other) =>
      other is ReadingNow &&
      other.chatId == chatId &&
      other.messageId == messageId &&
      other.channelTitle == channelTitle &&
      other.waiting == waiting;

  @override
  int get hashCode => Object.hash(chatId, messageId, channelTitle, waiting);
}

/// What the app sends the service host with `FlutterForegroundTask.sendDataToTask`.
const askReading = {'tts': 'state'};
const clearReading = {'tts': 'clear'};
Map<String, Object> stopReadingOf(ReadingNow r) => {
  'tts': 'stop',
  'chatId': r.chatId,
  'messageId': r.messageId,
};
