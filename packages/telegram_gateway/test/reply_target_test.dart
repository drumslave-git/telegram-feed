import 'package:tdlib_bindings/tdlib_bindings.dart' as td;
import 'package:telegram_gateway/src/mapping.dart' as map;
import 'package:telegram_gateway/telegram_gateway.dart';
import 'package:test/test.dart';

import 'tdlib_gateway_test.dart' show FakeTransport, cfg, messageJson;

Map<String, Object?> _replying(Map<String, Object?> replyTo) => {
  ...messageJson(-1001, 30, text: 'the answer'),
  'reply_to': replyTo,
};

void main() {
  test('a quote the author picked is what the block says', () {
    final post = map.post(
      td.Message.fromJson(
        _replying({
          '@type': 'messageReplyToMessage',
          'chat_id': -1001,
          'message_id': 20,
          'quote': {
            '@type': 'textQuote',
            'text': {'@type': 'formattedText', 'text': 'these very words'},
            'position': 0,
            'is_manual': true,
          },
        }),
      ),
    );
    final reply = post.replyTo!;
    expect(reply.chatId, -1001);
    expect(reply.messageId, 20);
    expect(reply.text, 'these very words');
    expect(reply.manualQuote, isTrue);
    expect(reply.title, isEmpty); // inside the channel: its own name answers
  });

  test('a reply to another chat comes with its origin and content', () {
    final post = map.post(
      td.Message.fromJson(
        _replying({
          '@type': 'messageReplyToMessage',
          'chat_id': -1002,
          'message_id': 88,
          'origin': {
            '@type': 'messageOriginHiddenUser',
            'sender_name': 'Someone',
          },
          'content': {
            '@type': 'messageText',
            'text': {'@type': 'formattedText', 'text': 'what they said'},
          },
        }),
      ),
    );
    final reply = post.replyTo!;
    expect(reply.chatId, -1002);
    expect(reply.title, 'Someone');
    expect(reply.text, 'what they said');
    expect(reply.manualQuote, isFalse);
  });

  test('a reply to a post without words carries its media, not a label', () {
    final post = map.post(
      td.Message.fromJson(
        _replying({
          '@type': 'messageReplyToMessage',
          'chat_id': -1002,
          'message_id': 88,
          'content': {
            '@type': 'messageVoiceNote',
            'voice_note': {
              '@type': 'voiceNote',
              'duration': 3,
              'waveform': '',
              'mime_type': 'audio/ogg',
              'voice': {
                '@type': 'file',
                'id': 5,
                'size': 100,
                'expected_size': 100,
                'remote': {'@type': 'remoteFile', 'id': 'r5'},
              },
            },
            'caption': {'@type': 'formattedText', 'text': ''},
          },
        }),
      ),
    );
    final reply = post.replyTo!;
    // The app names it in the reader's language.
    expect(reply.text, isEmpty);
    expect(reply.media, isA<AudioMedia>());
    final back = decodePost(encodePost(post)).replyTo!;
    expect((back.media! as AudioMedia).isVoice, isTrue);
  });

  test('a channel whose newest post has no words names its media', () {
    const channel = Channel(
      chatId: -1,
      title: 'News',
      lastMessageMedia: PhotoMedia(
        sizes: [
          FileRef(id: 1, remoteId: 'r1', size: 10, width: 90, height: 90),
        ],
      ),
    );
    final back = decodeChannel(encodeChannel(channel));
    expect(back.lastMessageText, isEmpty);
    expect(back.lastMessageMedia, isA<PhotoMedia>());
    expect(
      decodeChannel(encodeChannel(const Channel(chatId: -1, title: 'x')))
          .lastMessageMedia,
      isNull,
    );
  });

  test('a post that answers nothing has no block', () {
    expect(
      map.post(td.Message.fromJson(messageJson(-1001, 30))).replyTo,
      isNull,
    );
    // A story cannot be answered here.
    expect(
      map
          .post(
            td.Message.fromJson(
              _replying({
                '@type': 'messageReplyToStory',
                'story_poster_chat_id': 5,
                'story_id': 1,
              }),
            ),
          )
          .replyTo,
      isNull,
    );
  });

  test('the block survives the trip between isolates', () {
    const post = Post(
      chatId: -1,
      messageId: 2,
      date: 3,
      text: 'the answer',
      replyTo: ReplyTarget(
        chatId: -1002,
        messageId: 88,
        title: 'Origin',
        text: 'what they said',
        manualQuote: true,
        photo: PhotoMedia(
          sizes: [
            FileRef(id: 1, remoteId: 'r1', size: 10, width: 90, height: 90),
          ],
        ),
      ),
    );
    final back = decodePost(encodePost(post)).replyTo!;
    expect(back.chatId, -1002);
    expect(back.messageId, 88);
    expect(back.title, 'Origin');
    expect(back.text, 'what they said');
    expect(back.manualQuote, isTrue);
    expect(back.photo!.sizes.single.width, 90);
    expect(decodePost(encodePost(post)..remove('replyTo')).replyTo, isNull);
  });

  test(
    'a reply inside the channel is filled from the answered post, once',
    () async {
      final t = FakeTransport();
      t.handlers['getOption'] = (_) => {
        '@type': 'optionValueString',
        'value': '1.8.67',
      };
      var fetches = 0;
      t.handlers['getMessage'] = (r) {
        fetches++;
        return messageJson(
          r['chat_id']! as int,
          r['message_id']! as int,
          text: 'the post it answers',
        );
      };
      t.handlers['getChatHistory'] = (_) => {
        '@type': 'messages',
        'total_count': 1,
        'messages': [
          _replying({
            '@type': 'messageReplyToMessage',
            'chat_id': 0, // TDLib leaves it out inside the same chat
            'message_id': 20,
          }),
        ],
      };
      final g = TdlibGateway(t, cfg);
      addTearDown(g.close);

      final first = await g.history(-1001, limit: 1);
      expect(first.single.replyTo!.text, 'the post it answers');
      expect(first.single.replyTo!.chatId, -1001);
      expect(fetches, 1);

      // The words are kept: reading the page again asks TDLib nothing.
      await g.history(-1001, limit: 1);
      expect(fetches, 1);
    },
  );
}
