import 'package:core/core.dart';
import 'package:rules/rules.dart';
import 'package:telegram_gateway/telegram_gateway.dart';
import 'package:test/test.dart';

const _file = FileRef(id: 1, remoteId: 'r', size: 10);

Post _post({String text = '', Media? media, int album = 0}) => Post(
  chatId: -1,
  messageId: 1,
  date: 1,
  text: text,
  media: media,
  albumId: album,
);

final _text = _post(text: 'a long enough text');
final _photo = _post(media: const PhotoMedia(sizes: [_file]));
final _clip = _post(media: const VideoMedia(file: _file, durationSeconds: 20));
final _film = _post(media: const VideoMedia(file: _file, durationSeconds: 600));
final _gif = _post(
  media: const VideoMedia(file: _file, durationSeconds: 3, isAnimation: true),
);
final _voice = _post(
  media: const AudioMedia(file: _file, durationSeconds: 5, isVoice: true),
);

void main() {
  test('no filter shows everything and is stored as null', () {
    expect(FeedFilter.none.isEmpty, isTrue);
    expect(FeedFilter.none.encode(), isNull);
    for (final p in [_text, _photo, _clip, _gif, _voice]) {
      expect(FeedFilter.none.allows(p), isTrue);
    }
  });

  test('a service line shows only in a feed that shows everything', () {
    final pin = _post(media: const ServiceNote(ServiceKind.pinned));
    expect(FeedFilter.none.shownParts([pin]), [pin]);
    for (final f in const [
      FeedFilter(media: MediaPresence.withMedia),
      FeedFilter(media: MediaPresence.textOnly),
      FeedFilter(kinds: {MediaKind.other}),
      FeedFilter(minTextLength: 1),
    ]) {
      expect(f.shownParts([pin]), isEmpty, reason: '${f.toJson()}');
    }
  });

  test('media presence', () {
    const media = FeedFilter(media: MediaPresence.withMedia);
    expect(media.allows(_text), isFalse);
    expect(media.allows(_photo), isTrue);
    const text = FeedFilter(media: MediaPresence.textOnly);
    expect(text.allows(_text), isTrue);
    expect(text.allows(_photo), isFalse);
  });

  test('media kinds restrict media posts, not text posts', () {
    const f = FeedFilter(kinds: {MediaKind.video, MediaKind.gif});
    expect(f.allows(_clip), isTrue);
    expect(f.allows(_gif), isTrue);
    expect(f.allows(_photo), isFalse);
    expect(f.allows(_voice), isFalse);
    expect(f.allows(_text), isTrue);
  });

  test('minimum video length hides short videos only', () {
    const f = FeedFilter(minVideoSeconds: 60);
    expect(f.allows(_clip), isFalse);
    expect(f.allows(_film), isTrue);
    expect(f.allows(_gif), isTrue); // an animation is not a video here
    expect(f.allows(_photo), isTrue);
  });

  test('minimum text length applies to posts without media', () {
    const f = FeedFilter(minTextLength: 50);
    expect(f.allows(_text), isFalse);
    expect(f.allows(_post(text: 'x' * 50)), isTrue);
    expect(f.allows(_photo), isTrue);
  });

  test('whole posts: an album part rides along, a single post does not', () {
    final albumPhoto = _post(media: const PhotoMedia(sizes: [_file]), album: 7);
    const videos = FeedFilter(kinds: {MediaKind.video});
    expect(videos.allows(albumPhoto), isFalse);
    expect(videos.mayShow(albumPhoto), isTrue);
    expect(videos.mayShow(_photo), isFalse); // alone, not in an album
    expect(videos.mayShow(_clip), isTrue);

    const parts = FeedFilter(kinds: {MediaKind.video}, wholePost: false);
    expect(parts.mayShow(albumPhoto), isFalse);

    // A feed without media never carries an album, whole posts or not.
    const textOnly = FeedFilter(media: MediaPresence.textOnly);
    expect(textOnly.mayShow(albumPhoto), isFalse);

    // On by default, including for a filter written before the option existed.
    expect(FeedFilter.decode('{"kinds":["video"]}'), videos);
    expect(FeedFilter.decode(parts.encode()), parts);
    expect(parts.describe(), 'videos · matching parts only');
    // Unchecked with nothing else set hides nothing, but the box stays unchecked.
    final bare = FeedFilter.none.copyWith(wholePost: false);
    expect(bare.describe(), 'Everything');
    expect(FeedFilter.decode(bare.encode()), bare);
  });

  test(
    'JSON round trip, unknown values ignored, broken JSON shows everything',
    () {
      const f = FeedFilter(
        media: MediaPresence.withMedia,
        kinds: {MediaKind.video, MediaKind.photo},
        minVideoSeconds: 120,
        minTextLength: 10,
      );
      expect(FeedFilter.decode(f.encode()), f);
      expect(
        FeedFilter.decode('{"media":"holograms","kinds":["video","smell"]}'),
        const FeedFilter(kinds: {MediaKind.video}),
      );
      expect(FeedFilter.decode('not json'), FeedFilter.none);
      expect(
        f.describe(),
        'with media · photos, videos · videos from 2 min · text from 10 characters',
      );
    },
  );

  group('text condition', () {
    const bitcoin = FeedFilter(text: Term('bitcoin'));
    const noAds = FeedFilter(text: Not(Term('#ad', wholeWord: false)));
    Post part(int id, {String text = ''}) => Post(
      chatId: -1,
      messageId: id,
      date: 1,
      text: text,
      albumId: 7,
      media: const PhotoMedia(sizes: [_file]),
    );

    test('a post is shown when its words match, as a rule matches them', () {
      expect(bitcoin.isEmpty, isFalse);
      expect(bitcoin.allows(_post(text: 'Bitcoin is up')), isTrue);
      expect(bitcoin.allows(_post(text: 'bitcoins')), isFalse); // whole word
      expect(bitcoin.allows(_text), isFalse);
      // A post without words has none of the words it should have...
      expect(bitcoin.allows(_photo), isFalse);
      // ...and none of the words it must not have.
      expect(noAds.allows(_photo), isTrue);
      expect(noAds.allows(_post(text: 'Buy now #advert')), isFalse);
      expect(noAds.mayShow(_post(text: 'Buy now #advert')), isFalse);
    });

    test('an album is judged by its captions, whichever part carries them', () {
      final album = [part(3), part(2), part(1, text: 'bitcoin news')];
      expect(bitcoin.shownParts(album), album);
      expect(noAds.shownParts(album), album);
      final ad = [part(3), part(2, text: 'sale #ad'), part(1)];
      expect(noAds.shownParts(ad), isEmpty);
      expect(bitcoin.shownParts(ad), isEmpty);
      // One part alone cannot tell: a rule or a search lets it through.
      expect(bitcoin.mayShow(part(3)), isTrue);
      expect(noAds.allows(part(3)), isTrue);
      // The media settings still judge the parts one by one.
      final withVideo = [
        part(3, text: 'bitcoin'),
        Post(
          chatId: -1,
          messageId: 2,
          date: 1,
          text: '',
          albumId: 7,
          media: const VideoMedia(file: _file, durationSeconds: 20),
        ),
      ];
      final videos = bitcoin.copyWith(kinds: {MediaKind.video});
      expect(videos.shownParts(withVideo), withVideo);
      expect(videos.copyWith(wholePost: false).shownParts(withVideo), [
        withVideo[1],
      ]);
    });

    test('stored with the filter, described in the text form', () {
      const f = FeedFilter(
        text: Or([
          Term('bitcoin'),
          And([Term('btc'), Not(Term('ad'))]),
        ]),
        minimize: true,
      );
      expect(FeedFilter.decode(f.encode()), f);
      expect(
        f.describe(),
        'text: bitcoin OR btc AND NOT ad · the rest minimized',
      );
      expect(bitcoin.copyWith(text: null), FeedFilter.none);
      expect(bitcoin.copyWith(minVideoSeconds: 60).text, bitcoin.text);
      // A condition every post matches, or one that cannot be read, is none.
      expect(FeedFilter.decode('{"text":{"and":[]}}'), FeedFilter.none);
      expect(FeedFilter.decode('{"text":{"xor":1}}'), FeedFilter.none);
    });
  });

  test('minimize alone hides nothing but is kept', () {
    const f = FeedFilter(minimize: true);
    expect(f.isEmpty, isTrue);
    expect(f.encode(), isNotNull);
    expect(FeedFilter.decode(f.encode()), f);
    expect(f.describe(), 'Everything');
  });
}
