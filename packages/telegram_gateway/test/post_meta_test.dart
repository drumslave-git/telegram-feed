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

  td.Message commented({required int read, required int last}) =>
      td.Message.fromJson({
        '@type': 'message',
        'id': 7,
        'chat_id': -1001,
        'date': 1700000000,
        'interaction_info': {
          '@type': 'messageInteractionInfo',
          'view_count': 1,
          'forward_count': 0,
          'reply_info': {
            '@type': 'messageReplyInfo',
            'reply_count': 3,
            'recent_replier_ids': const <Object>[],
            'last_read_inbox_message_id': read,
            'last_read_outbox_message_id': 0,
            'last_message_id': last,
          },
        },
        'content': {
          '@type': 'messageText',
          'text': {
            '@type': 'formattedText',
            'text': 'words',
            'entities': const <Object>[],
          },
        },
      });

  test('comments are unread once the thread was read and has newer ones', () {
    expect(map.post(commented(read: 10, last: 12)).hasUnreadComments, isTrue);
    expect(map.post(commented(read: 12, last: 12)).hasUnreadComments, isFalse);
    // A thread that was never opened shows no dot, as in the official app.
    expect(map.post(commented(read: 0, last: 12)).hasUnreadComments, isFalse);
  });

  test('the commenters and the unread flag cross the core boundary', () {
    const post = Post(
      chatId: -1,
      messageId: 2,
      date: 3,
      text: 'words',
      replyCount: 2,
      canComment: true,
      hasUnreadComments: true,
      recentCommenters: [
        Commenter(
          id: 11,
          name: 'Mara',
          photo: FileRef(id: 5, remoteId: 'p', size: 9),
        ),
        Commenter(id: 12, name: 'Tomas'),
      ],
    );
    final back = decodePost(encodePost(post));
    expect(back.hasUnreadComments, isTrue);
    expect(back.recentCommenters, post.recentCommenters);
    expect(back.recentCommenters.first.photo!.remoteId, 'p');
  });
}
