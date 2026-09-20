import 'package:tdlib_bindings/tdlib_bindings.dart' as td;
import 'package:telegram_gateway/src/mapping.dart' as map;
import 'package:telegram_gateway/telegram_gateway.dart';
import 'package:test/test.dart';

import 'tdlib_gateway_test.dart'
    show FakeTransport, cfg, chatJson, messageJson, supergroupJson;

Map<String, Object?> _message(Map<String, Object?>? origin) => {
  ...messageJson(-1001, 30, text: 'forwarded'),
  'forward_info': ?(origin == null
      ? null
      : {'@type': 'messageForwardInfo', 'origin': origin, 'date': 1699999999}),
};

void main() {
  test('the four origins map to their ids, names and signatures', () {
    ForwardOrigin? origin(Map<String, Object?>? o) =>
        map.post(td.Message.fromJson(_message(o))).forwardedFrom;

    final channel = origin({
      '@type': 'messageOriginChannel',
      'chat_id': -1002,
      'message_id': 88,
      'author_signature': 'Ed',
    })!;
    expect(channel.chatId, -1002);
    expect(channel.messageId, 88);
    expect(channel.signature, 'Ed');
    expect(channel.hidden, isFalse);
    expect(channel.title, isEmpty); // the gateway fills it

    final chat = origin({
      '@type': 'messageOriginChat',
      'sender_chat_id': -1003,
      'author_signature': '',
    })!;
    expect(chat.chatId, -1003);
    expect(chat.messageId, 0);

    expect(
      origin({'@type': 'messageOriginUser', 'sender_user_id': 7})!.userId,
      7,
    );

    final hidden = origin({
      '@type': 'messageOriginHiddenUser',
      'sender_name': 'Someone',
    })!;
    expect(hidden.hidden, isTrue);
    expect(hidden.title, 'Someone');

    // A post that was not forwarded has no origin at all.
    expect(origin(null), isNull);
  });

  test('the origin survives the trip between isolates', () {
    const post = Post(
      chatId: -1,
      messageId: 2,
      date: 3,
      text: 'forwarded',
      forwardedFrom: ForwardOrigin(
        title: 'Alpha News',
        chatId: -1002,
        messageId: 88,
        signature: 'Ed',
      ),
    );
    final back = decodePost(encodePost(post)).forwardedFrom!;
    expect(back.title, 'Alpha News');
    expect(back.chatId, -1002);
    expect(back.messageId, 88);
    expect(back.signature, 'Ed');
    expect(back.hidden, isFalse);
    // A post encoded by a core that predates origins has none.
    expect(
      decodePost(encodePost(post)..remove('forwardedFrom')).forwardedFrom,
      isNull,
    );
  });

  test('the gateway names the channel a post came from, once', () async {
    final t = FakeTransport();
    t.handlers['getOption'] = (_) => {
      '@type': 'optionValueString',
      'value': '1.8.67',
    };
    var chatCalls = 0;
    t.handlers['getChat'] = (r) {
      chatCalls++;
      return chatJson(r['chat_id']! as int, 'Origin Channel', supergroupId: 2);
    };
    t.handlers['getChatHistory'] = (_) => {
      '@type': 'messages',
      'total_count': 2,
      'messages': [
        _message({
          '@type': 'messageOriginChannel',
          'chat_id': -1002,
          'message_id': 88,
          'author_signature': '',
        }),
        {...messageJson(-1001, 20, text: 'own post'), 'forward_info': null},
      ],
    };
    final g = TdlibGateway(t, cfg);
    addTearDown(g.close);
    t.update({'@type': 'updateSupergroup', 'supergroup': supergroupJson(1)});

    final posts = await g.history(-1001, limit: 2);
    expect(posts.first.forwardedFrom!.title, 'Origin Channel');
    expect(posts.last.forwardedFrom, isNull);
    expect(chatCalls, 1);

    // A second page with the same origin asks TDLib nothing more.
    await g.history(-1001, limit: 2);
    expect(chatCalls, 1);
  });
}
