import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'urls become "link", mentions and emoji are dropped, whitespace collapses',
    () {
      expect(
        prepareForSpeech(
          'Big news 🚀🚀 see https://example.com/a?b=1 and www.x.org now\n\n @someone',
        ),
        'Big news see link and link now',
      );
    },
  );

  test('markdown-ish markers are removed', () {
    expect(
      prepareForSpeech('**Bold** _it_ `code` > quote #tag'),
      'Bold it code quote tag',
    );
  });

  test('channel prefix and empty results', () {
    expect(
      prepareForSpeech('hello', channelTitle: 'News 📰'),
      'New post in News. hello',
    );
    expect(prepareForSpeech('🚀🚀', channelTitle: 'x'), '');
    expect(prepareForSpeech('   '), '');
  });

  test('truncation prefers a sentence end, then a word boundary', () {
    final s = List.generate(40, (i) => 'Sentence number $i is here.').join(' ');
    final out = prepareForSpeech(s, maxChars: 100);
    expect(out.length, lessThanOrEqualTo(100 + '… and more'.length + 1));
    expect(out, endsWith('.… and more'));
    final words = List.filled(50, 'word').join(' ');
    final out2 = prepareForSpeech(words, maxChars: 30);
    expect(out2, 'word word word word word word… and more');
  });

  test('Cyrillic and CJK survive', () {
    expect(prepareForSpeech('Курс рубля 📉 вырос'), 'Курс рубля вырос');
    expect(prepareForSpeech('比特币涨了'), '比特币涨了');
  });

  test('language guess by script', () {
    expect(guessLanguageByScript('Курс рубля вырос'), 'ru');
    expect(guessLanguageByScript('比特币涨了'), 'zh');
    expect(guessLanguageByScript('ビットコインが上がった'), 'ja');
    expect(guessLanguageByScript('שלום world'), 'he');
    expect(guessLanguageByScript('plain latin text'), isNull);
    expect(guessLanguageByScript(''), isNull);
  });
}
