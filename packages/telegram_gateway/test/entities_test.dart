import 'package:tdlib_bindings/tdlib_bindings.dart' as td;
import 'package:telegram_gateway/src/mapping.dart' as map;
import 'package:telegram_gateway/telegram_gateway.dart';
import 'package:test/test.dart';

td.Message _message(String text, List<Map<String, Object?>> entities) =>
    td.Message.fromJson({
      '@type': 'message',
      'id': 7,
      'chat_id': -1001,
      'date': 1700000000,
      'content': {
        '@type': 'messageText',
        'text': {'@type': 'formattedText', 'text': text, 'entities': entities},
      },
    });

Map<String, Object?> _entity(
  int offset,
  int length,
  String type, [
  Map<String, Object?> more = const {},
]) => {
  '@type': 'textEntity',
  'offset': offset,
  'length': length,
  'type': {'@type': type, ...more},
};

void main() {
  test('formatting and links of a post are mapped, the rest stays plain', () {
    //             0         1         2         3         4         5
    //             0123456789012345678901234567890123456789012345678901234
    const text = 'Bold news at example.org by @durov #tag a@b.io here 1:23';
    final post = map.post(
      _message(text, [
        _entity(0, 4, 'textEntityTypeBold'),
        _entity(0, 9, 'textEntityTypeItalic'),
        _entity(13, 11, 'textEntityTypeUrl'),
        _entity(28, 6, 'textEntityTypeMention'),
        _entity(35, 4, 'textEntityTypeHashtag'),
        _entity(40, 6, 'textEntityTypeEmailAddress'),
        _entity(47, 4, 'textEntityTypeTextUrl', {'url': 'https://t.me/x/1'}),
        _entity(52, 4, 'textEntityTypeMediaTimestamp', {'media_timestamp': 83}),
        _entity(50, 99, 'textEntityTypeBold'), // runs past the text: dropped
      ]),
    );
    expect(post.text, text);
    expect(post.entities, const [
      TextEntity(offset: 0, length: 4, kind: TextEntityKind.bold),
      TextEntity(offset: 0, length: 9, kind: TextEntityKind.italic),
      TextEntity(
        offset: 13,
        length: 11,
        kind: TextEntityKind.link,
        url: 'https://example.org',
      ),
      TextEntity(
        offset: 28,
        length: 6,
        kind: TextEntityKind.link,
        url: 'https://t.me/durov',
      ),
      TextEntity(offset: 35, length: 4, kind: TextEntityKind.tag),
      TextEntity(
        offset: 40,
        length: 6,
        kind: TextEntityKind.link,
        url: 'mailto:a@b.io',
      ),
      TextEntity(
        offset: 47,
        length: 4,
        kind: TextEntityKind.link,
        url: 'https://t.me/x/1',
      ),
    ]);
  });

  test('entities survive the trip between isolates', () {
    const post = Post(
      chatId: -1,
      messageId: 2,
      date: 3,
      text: 'hidden link',
      entities: [
        TextEntity(offset: 0, length: 6, kind: TextEntityKind.spoiler),
        TextEntity(
          offset: 7,
          length: 4,
          kind: TextEntityKind.link,
          url: 'https://example.org',
        ),
      ],
    );
    expect(decodePost(encodePost(post)).entities, post.entities);
    // A post encoded by an older core has none.
    expect(decodePost(encodePost(post)..remove('entities')).entities, isEmpty);
  });
}
