import 'package:tdlib_bindings/tdlib_bindings.dart' as td;
import 'package:telegram_gateway/src/mapping.dart' as map;
import 'package:telegram_gateway/telegram_gateway.dart';
import 'package:test/test.dart';

td.Message _message(Map<String, Object?>? markup) => td.Message.fromJson({
  '@type': 'message',
  'id': 7,
  'chat_id': -1001,
  'date': 1700000000,
  'content': {
    '@type': 'messageText',
    'text': {'@type': 'formattedText', 'text': 'words', 'entities': const []},
  },
  'reply_markup': ?markup,
});

Map<String, Object?> _url(String text, String url) => {
  '@type': 'inlineKeyboardButton',
  'text': text,
  'type': {'@type': 'inlineKeyboardButtonTypeUrl', 'url': url},
};

Map<String, Object?> _callback(String text) => {
  '@type': 'inlineKeyboardButton',
  'text': text,
  'type': {'@type': 'inlineKeyboardButtonTypeCallback', 'data': 'eA=='},
};

void main() {
  test('link buttons keep their rows; buttons for a bot are left out', () {
    final post = map.post(
      _message({
        '@type': 'replyMarkupInlineKeyboard',
        'rows': [
          [_url('Read', 'https://example.org/a')],
          [_callback('Vote'), _url('Site', 'https://example.org')],
          [_callback('Like')],
        ],
      }),
    );
    expect(post.buttons, const [
      [UrlButton(text: 'Read', url: 'https://example.org/a')],
      [UrlButton(text: 'Site', url: 'https://example.org')],
    ]);
  });

  test('a post without a keyboard, or with a reply keyboard, has none', () {
    expect(map.post(_message(null)).buttons, isEmpty);
    expect(
      map.post(_message({'@type': 'replyMarkupRemoveKeyboard'})).buttons,
      isEmpty,
    );
  });

  test('the buttons cross the core boundary', () {
    const post = Post(
      chatId: -1,
      messageId: 2,
      date: 3,
      text: 'words',
      buttons: [
        [UrlButton(text: 'Read', url: 'https://example.org/a')],
        [
          UrlButton(text: 'One', url: 'https://example.org/1'),
          UrlButton(text: 'Two', url: 'https://t.me/two'),
        ],
      ],
    );
    expect(decodePost(encodePost(post)).buttons, post.buttons);
    expect(decodePost(encodePost(post)..remove('buttons')).buttons, isEmpty);
  });
}
