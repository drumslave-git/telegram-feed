import 'dart:convert';

/// Where the reader left a timeline scrolled up, kept on the device the way the official app
/// keeps a chat's position (ARCHITECTURE.md 5.3): the lowest row on the screen and how far
/// its bottom edge stood above the bottom of the screen. Nothing is kept when the reader
/// left at the newest post, or while that lowest row was still unread.
final class SavedPosition {
  const SavedPosition({
    required this.chatId,
    required this.rowId,
    required this.edge,
  });
  final int chatId;

  /// The row's id within its chat: the album, or the post.
  final int rowId;

  /// The row's bottom edge, as a fraction of the screen from the bottom.
  final double edge;

  String encode() => jsonEncode({'chat': chatId, 'row': rowId, 'edge': edge});

  /// Null for anything that is not a position this app wrote.
  static SavedPosition? decode(String? json) {
    if (json == null) return null;
    try {
      final m = jsonDecode(json) as Map<String, Object?>;
      return SavedPosition(
        chatId: m['chat']! as int,
        rowId: m['row']! as int,
        edge: (m['edge']! as num).toDouble(),
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}
