import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  test('supergroup id from chat id', () {
    expect(supergroupIdOf(-1001446168251), 1446168251);
    expect(supergroupIdOf(-1000000000001), 1);
    expect(supergroupIdOf(7), isNull);
    expect(supergroupIdOf(-42), isNull);
  });

  test(
    'public channel post links use the username and the server message id',
    () {
      // TDLib id 439610245120 = server id 419230 << 20.
      final u = telegramPostUri(
        chatId: -1001446168251,
        messageId: 419230 << 20,
        username: 'news',
      );
      expect(u.toString(), 'https://t.me/news/419230');
    },
  );

  test('private channels use tg://privatepost and a t.me/c web fallback', () {
    final u = telegramPostUri(chatId: -1001446168251, messageId: 5 << 20);
    expect(u.toString(), 'tg://privatepost?channel=1446168251&post=5');
    expect(
      telegramPostWebUri(chatId: -1001446168251, messageId: 5 << 20).toString(),
      'https://t.me/c/1446168251/5',
    );
    expect(telegramPostUri(chatId: 7, messageId: 5 << 20), isNull);
  });

  test('share link is the public link, else t.me/c, else nothing', () {
    expect(
      telegramShareUri(
        chatId: -1001446168251,
        messageId: 5 << 20,
        username: 'news',
      ).toString(),
      'https://t.me/news/5',
    );
    expect(
      telegramShareUri(chatId: -1001446168251, messageId: 5 << 20).toString(),
      'https://t.me/c/1446168251/5',
    );
    expect(telegramShareUri(chatId: 7, messageId: 5 << 20), isNull);
  });

  test('share text: title, trimmed and truncated body, link', () {
    final link = Uri.parse('https://t.me/news/5');
    expect(
      shareText(channelTitle: 'News', text: '  hello \n  world ', link: link),
      'News\n\nhello\nworld\n\nhttps://t.me/news/5',
    );
    expect(
      shareText(channelTitle: '', text: '', link: link),
      'https://t.me/news/5',
    );
    final long = shareText(
      channelTitle: 'News',
      text: 'a' * 300,
      link: link,
      maxChars: 10,
    );
    expect(long, 'News\n\n${'a' * 10}…\n\nhttps://t.me/news/5');
  });
}
