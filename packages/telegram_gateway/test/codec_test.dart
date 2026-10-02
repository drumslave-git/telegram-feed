import 'package:telegram_gateway/telegram_gateway.dart';
import 'package:test/test.dart';

void main() {
  test('a deleted event carries its ids in a list of its own', () {
    // What a core hands on after decoding a request: a view, not a list.
    final ids = <Object?>[9, 8].cast<int>();
    final encoded = encodePostEvent(PostsDeleted(chatId: 42, messageIds: ids));
    expect(encoded['messageIds'], [9, 8]);
    expect(identical(encoded['messageIds'], ids), isFalse);
    final decoded = decodePostEvent(encoded) as PostsDeleted;
    expect(decoded.chatId, 42);
    expect(decoded.messageIds, [9, 8]);
  });
}
