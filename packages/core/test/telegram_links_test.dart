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

  test('telegramTargetOf reads the links the app can open itself', () {
    expect(telegramTargetOf(Uri.parse('https://t.me/alpha')), (
      username: 'alpha',
      chatId: null,
      messageId: null,
    ));
    expect(telegramTargetOf(Uri.parse('https://t.me/alpha/42')), (
      username: 'alpha',
      chatId: null,
      messageId: 42 << 20,
    ));
    expect(telegramTargetOf(Uri.parse('https://telegram.me/alpha/42')), (
      username: 'alpha',
      chatId: null,
      messageId: 42 << 20,
    ));
    expect(telegramTargetOf(Uri.parse('https://t.me/c/1446168251/5')), (
      username: null,
      chatId: -1001446168251,
      messageId: 5 << 20,
    ));
    expect(telegramTargetOf(Uri.parse('tg://resolve?domain=alpha&post=7')), (
      username: 'alpha',
      chatId: null,
      messageId: 7 << 20,
    ));
    expect(
      telegramTargetOf(Uri.parse('tg://privatepost?channel=1446168251&post=5')),
      (username: null, chatId: -1001446168251, messageId: 5 << 20),
    );
  });

  test('telegramTargetOf leaves everything else to other apps', () {
    for (final link in [
      'https://example.org/story',
      'https://t.me/+AbCdEf',
      'https://t.me/joinchat/AbCdEf',
      'https://t.me/addstickers/pack',
      'https://t.me/',
      'mailto:a@b.io',
      'tg://settings',
    ]) {
      expect(telegramTargetOf(Uri.parse(link)), isNull, reason: link);
    }
  });
}
