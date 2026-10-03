import 'package:tdlib_bindings/tdlib_bindings.dart' as td;
import 'package:telegram_gateway/src/mapping.dart' as map;
import 'package:telegram_gateway/telegram_gateway.dart';
import 'package:test/test.dart';

td.Message _message(Map<String, Object?> content) => td.Message.fromJson({
  '@type': 'message',
  'id': 7,
  'chat_id': -1001,
  'date': 1700000000,
  'content': content,
});

void main() {
  test('a single animated emoji is a post with that emoji as its text', () {
    final post = map.post(
      _message({'@type': 'messageAnimatedEmoji', 'emoji': '🔥'}),
    );
    expect((post.text, post.media), ('🔥', null));
  });

  test('service messages map to what they say', () {
    ServiceNote note(Map<String, Object?> content) =>
        map.post(_message(content)).media! as ServiceNote;

    expect(
      note({'@type': 'messagePinMessage', 'message_id': 42}),
      const ServiceNote(ServiceKind.pinned, messageId: 42),
    );
    expect(
      note({'@type': 'messageChatChangeTitle', 'title': 'New name'}),
      const ServiceNote(ServiceKind.titleChanged, title: 'New name'),
    );
    expect(
      note({'@type': 'messageChatChangePhoto'}).kind,
      ServiceKind.photoChanged,
    );
    expect(
      note({'@type': 'messageChatDeletePhoto'}).kind,
      ServiceKind.photoRemoved,
    );
    expect(
      note({'@type': 'messageSupergroupChatCreate', 'title': 'x'}).kind,
      ServiceKind.channelCreated,
    );
    expect(
      note({'@type': 'messageVideoChatStarted', 'group_call_id': 1}).kind,
      ServiceKind.liveStarted,
    );
    expect(
      note({'@type': 'messageVideoChatEnded', 'duration': 245}),
      const ServiceNote(ServiceKind.liveEnded, seconds: 245),
    );
    expect(
      note({
        '@type': 'messageVideoChatScheduled',
        'group_call_id': 1,
        'start_date': 1700003600,
      }),
      const ServiceNote(ServiceKind.liveScheduled, seconds: 1700003600),
    );
    // One the app has no words for is still a service message, not a post.
    expect(note({'@type': 'messageChatSetTheme'}).kind, ServiceKind.other);
  });

  test('content the app does not show keeps its kind', () {
    for (final type in const [
      'messagePoll',
      'messageChecklist',
      'messageDice',
    ]) {
      final media = map.post(_message({'@type': type})).media;
      expect((media! as UnsupportedMedia).tdType, type);
    }
  });

  test('a post Telegram does not let be saved is protected, and stays so '
      'across the isolate boundary', () {
    Post of(bool canBeSaved) => map.post(
      td.Message.fromJson({
        '@type': 'message',
        'id': 7,
        'chat_id': -1001,
        'date': 1700000000,
        'can_be_saved': canBeSaved,
        'content': {
          '@type': 'messageText',
          'text': {'@type': 'formattedText', 'text': 'hello'},
        },
      }),
    );
    expect(of(true).canBeSaved, isTrue);
    expect(of(false).canBeSaved, isFalse);
    expect(decodePost(encodePost(of(false))).canBeSaved, isFalse);
    expect(decodePost(encodePost(of(true))).canBeSaved, isTrue);
  });

  test('a service note crosses the isolate boundary', () {
    const note = ServiceNote(ServiceKind.pinned, messageId: 42);
    expect(decodeMedia(encodeMedia(note)), note);
    expect(
      decodeMedia({'kind': 'service', 'service': 'from a newer build'}),
      const ServiceNote(ServiceKind.other),
    );
  });
}
