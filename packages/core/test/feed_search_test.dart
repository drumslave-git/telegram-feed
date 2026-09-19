import 'package:core/core.dart';
import 'package:telegram_gateway/telegram_gateway.dart';
import 'package:test/test.dart';

import 'feed_timeline_test.dart' show HistoryGateway;

Post p(
  int chat,
  int id,
  int date, {
  String text = '',
  Media? media,
  int album = 0,
}) => Post(
  chatId: chat,
  messageId: id,
  date: date,
  text: text.isEmpty ? 'm$id' : text,
  media: media,
  albumId: album,
);

const photo = PhotoMedia(sizes: [FileRef(id: 1, remoteId: 'r', size: 1)]);
const shortVideo = VideoMedia(
  file: FileRef(id: 2, remoteId: 'r', size: 1),
  durationSeconds: 5,
);
const doc = DocumentMedia(
  file: FileRef(id: 3, remoteId: 'r', size: 1),
  fileName: 'a.pdf',
  mimeType: 'application/pdf',
);

void main() {
  test('merges the sources by date and pages through them', () async {
    final g = HistoryGateway({
      -1: [
        p(-1, 50, 500, text: 'rain in Berlin'),
        p(-1, 40, 300, text: 'sun'),
        p(-1, 30, 100, text: 'rain again'),
      ],
      -2: [
        p(-2, 60, 400, text: 'RAIN over Prague'),
        p(-2, 20, 50, text: 'clouds'),
      ],
    });
    final s = FeedSearch(g, [-1, -2], query: 'rain', pageSize: 2);

    final first = await s.loadMore();
    expect(first.map((p) => p.messageId), [50, 60]); // 500, 400
    expect(s.exhausted, isFalse);

    final second = await s.loadMore();
    expect(second.map((p) => p.messageId), [30]);
    expect(s.results.map((p) => p.date), [500, 400, 100]);

    // Telegram's approximate total counts both sources.
    expect(s.totalCount, 3);

    await s.loadMore();
    expect(s.exhausted, isTrue);
  });

  test('a media tab searches with a filter and no query', () async {
    final g = HistoryGateway({
      -1: [
        p(-1, 50, 500, media: photo),
        p(-1, 40, 400),
        p(-1, 30, 300, media: doc),
      ],
    });
    final s = FeedSearch(g, [-1], filter: HistoryFilter.photoAndVideo);
    await s.loadMore();
    expect(s.results.map((p) => p.messageId), [50]);
    expect(g.calls.first, startsWith('search:-1::photoAndVideo:'));
  });

  test("the feed's filter hides results the server matched", () async {
    final g = HistoryGateway({
      -1: [
        p(-1, 50, 500, media: photo),
        p(-1, 40, 400, media: shortVideo),
        p(-1, 30, 300, media: doc),
      ],
    });
    final s = FeedSearch(
      g,
      [-1],
      filter: HistoryFilter.photoAndVideo,
      feedFilter: const FeedFilter(
        kinds: {MediaKind.photo, MediaKind.video},
        minVideoSeconds: 60,
      ),
    );
    await s.loadMore();
    // The short video is hidden here, but Telegram counted it as a match.
    expect(s.results.map((p) => p.messageId), [50]);
    expect(s.totalCount, 2);
  });

  test('a word search finds the caption its album carries', () async {
    const videos = FeedFilter(kinds: {MediaKind.video});
    final g = HistoryGateway({
      -1: [
        p(-1, 50, 500, text: 'rain over Kyiv', media: photo, album: 4),
        p(-1, 49, 500, media: shortVideo, album: 4),
      ],
    });
    final s = FeedSearch(g, [-1], query: 'rain', feedFilter: videos);
    await s.loadMore();
    expect(s.results.map((p) => p.messageId), [50]);

    // Off, the picture is not shown and not found either.
    final parts = FeedSearch(
      g,
      [-1],
      query: 'rain',
      feedFilter: videos.copyWith(wholePost: false),
    );
    await parts.loadMore();
    expect(parts.results, isEmpty);

    // The media tabs list single media items, so the picture stays out of them.
    final tab = FeedSearch(
      g,
      [-1],
      filter: HistoryFilter.photoAndVideo,
      feedFilter: videos,
    );
    await tab.loadMore();
    expect(tab.results.map((p) => p.messageId), [49]);
  });

  test('a deleted post leaves the results', () async {
    final g = HistoryGateway({
      -1: [p(-1, 50, 500, text: 'rain'), p(-1, 40, 400, text: 'rain')],
    });
    final s = FeedSearch(g, [-1], query: 'rain');
    await s.loadMore();
    expect(s.removePosts(-1, [50]), isTrue);
    expect(s.results.single.messageId, 40);
    expect(s.removePosts(-1, [999]), isFalse);
  });

  test(
    'anchorsForDate takes the newest post of each source up to the date',
    () async {
      final g = HistoryGateway({
        -1: [p(-1, 50, 500), p(-1, 40, 300), p(-1, 30, 100)],
        -2: [p(-2, 60, 400), p(-2, 20, 350)],
        -3: [p(-3, 70, 900)], // nothing that old
      });
      final anchors = await anchorsForDate(g, [-1, -2, -3], 380);
      expect(anchors, {-1: 40, -2: 20});
    },
  );
}
