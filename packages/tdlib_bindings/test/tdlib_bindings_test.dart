import 'package:tdlib_bindings/tdlib_bindings.dart' as td;
import 'package:test/test.dart';

void main() {
  test('decodes a sealed type by @type and round-trips to JSON', () {
    final json = <String, Object?>{
      '@type': 'authenticationCodeTypeSms',
      'length': 5,
    };
    final t = td.AuthenticationCodeType.fromJson(json);
    expect(t, isA<td.AuthenticationCodeTypeSms>());
    expect((t as td.AuthenticationCodeTypeSms).length, 5);
    expect(t.toJson(), json);
  });

  test(
    'decodes an update with a nested message, int64 as string, absent objects',
    () {
      final update = td.tdObjectFromJson({
        '@type': 'updateNewMessage',
        'message': {
          '@type': 'message',
          'id': 439610245120,
          'chat_id': -1001446168251,
          'sender_id': {
            '@type': 'messageSenderChat',
            'chat_id': -1001446168251,
          },
          'is_outgoing': false,
          'date': 1789657000,
          'media_album_id': '13284789234',
          'content': {
            '@type': 'messageText',
            'text': {'@type': 'formattedText', 'text': 'hello', 'entities': []},
          },
        },
      });
      expect(update, isA<td.UpdateNewMessage>());
      final m = (update as td.UpdateNewMessage).message!;
      expect(m.id, 439610245120);
      expect(m.mediaAlbumId, 13284789234);
      expect(m.forwardInfo, isNull);
      expect((m.content as td.MessageText).text!.text, 'hello');
      expect(m.toJson()['media_album_id'], '13284789234');
      expect((m.toJson()['content'] as Map)['@type'], 'messageText');
    },
  );

  test('functions carry their result decoder', () {
    const f = td.GetChatHistory(
      chatId: 1,
      fromMessageId: 0,
      offset: 0,
      limit: 30,
      onlyLocal: true,
    );
    expect(f.toJson()['@type'], 'getChatHistory');
    final r = f.decodeResult({
      '@type': 'messages',
      'total_count': 0,
      'messages': [],
    });
    expect(r.totalCount, 0);
    expect(r.messages, isEmpty);
  });

  test('error is renamed to avoid dart:core', () {
    final e = td.tdObjectFromJson({
      '@type': 'error',
      'code': 400,
      'message': 'x',
    });
    expect(e, isA<td.TdError>());
  });
}
