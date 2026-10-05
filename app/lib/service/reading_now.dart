/// What the app's banner shows of read-aloud (ARCHITECTURE 7): the post being read and how
/// many wait after it. The alerts report it after every change.
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
