import 'package:tdlib_bindings/tdlib_bindings.dart' as td;
import 'package:telegram_gateway/src/mapping.dart' as map;
import 'package:telegram_gateway/telegram_gateway.dart';
import 'package:test/test.dart';

td.Message _message({String signature = '', bool pinned = false}) =>
    td.Message.fromJson({
      '@type': 'message',
      'id': 7,
      'chat_id': -1001,
      'date': 1700000000,
      'author_signature': signature,
      'is_pinned': pinned,
      'content': {
        '@type': 'messageText',
        'text': {
          '@type': 'formattedText',
          'text': 'words',
          'entities': const <Object>[],
        },
      },
    });

void main() {
  test('a post carries its author signature and whether it is pinned', () {
    final signed = map.post(_message(signature: 'Ada', pinned: true));
    expect(signed.signature, 'Ada');
    expect(signed.isPinned, isTrue);
    final back = decodePost(encodePost(signed));
    expect(back.signature, 'Ada');
    expect(back.isPinned, isTrue);

    final plain = map.post(_message());
    expect(plain.signature, isEmpty);
    expect(plain.isPinned, isFalse);
    expect(decodePost(encodePost(plain)).isPinned, isFalse);
  });
}
