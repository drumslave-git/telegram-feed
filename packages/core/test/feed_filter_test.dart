import 'package:core/core.dart';
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
    expect(parts.describe(), 'video · matching parts only');
    // Unchecked with nothing else set hides nothing, but the box stays unchecked.
    final bare = FeedFilter.none.copyWith(wholePost: false);
    expect(bare.describe(), 'Everything');
    expect(FeedFilter.decode(bare.encode()), bare);
  });

  test('JSON round trip, unknown values ignored, broken JSON shows everything', () {
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
      'with media · photo, video · videos from 2 min · text from 10 characters',
    );
  });
}
