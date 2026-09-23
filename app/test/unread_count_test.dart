import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/feeds_screen.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fixtures.dart';

Channel _channel(int id, int last) =>
    Channel(chatId: id, title: 'C$id', lastMessageId: last);

void main() {
  late AppDatabase db;
  FeedsController? controller;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async {
    controller?.dispose();
    controller = null;
    await db.close();
  });

  Future<void> settle() async {
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  /// One channel of ten posts read to 6, one with a post and an album of three after 3.
  TimelineGateway twoChannels() => TimelineGateway(
    {
      -1: fixtureHistory(-1, to: 10),
      -2: [
        fixturePost(-2, 7, albumId: 5),
        fixturePost(-2, 6, albumId: 5),
        fixturePost(-2, 5, albumId: 5),
        fixturePost(-2, 4),
      ],
    },
    channels: [_channel(-1, 10), _channel(-2, 7)],
  );

  Future<FeedsController> start(TimelineGateway gw) async {
    final c = controller = FeedsController(db: db, gateway: gw);
    await settle();
    return c;
  }

  test(
    'the badge counts unread posts as Telegram does, album parts too',
    () async {
      final gw = twoChannels();
      final feed = await fixtureFeed(
        db,
        'F',
        {-1: 'One', -2: 'Two'},
        marks: {-1: 6, -2: 3},
        gateway: gw,
      );
      final c = await start(gw);
      expect(c.countPosts, isTrue);
      // One: 7 to 10. Two: post 4 and the three parts of the album.
      expect(c.unreadOf(feed.id), 8);
      expect(c.unreadChannelsOf(feed.id), 2);
      expect(c.unreadOnTab, 8);
    },
  );

  test('reading here or in the official app lowers every feed at once', () async {
    final gw = twoChannels();
    final feed = await fixtureFeed(
      db,
      'F',
      {-1: 'One', -2: 'Two'},
      marks: {-1: 6, -2: 3},
      gateway: gw,
    );
    // Another feed with the same channel: one read position is shared by both.
    final other = await fixtureFeed(db, 'G', {-1: 'One'});
    final c = await start(gw);
    expect(c.unreadOf(other.id), 4);
    final asked = gw.historyCalls;
    await gw.markViewed(-1, [8]);
    await settle();
    expect(c.unreadOf(feed.id), 6); // 9, 10 and Two's four
    expect(c.unreadOf(other.id), 2);
    await gw.markViewed(-2, [7]);
    await settle();
    expect(c.unreadOf(feed.id), 2);
    expect(c.unreadChannelsOf(feed.id), 1);
    // Telegram's own count: no history is read for a feed that shows everything.
    expect(gw.historyCalls, asked);
  });

  test(
    'a post that comes in counts at once, a deleted one stops counting',
    () async {
      final gw = twoChannels();
      final feed = await fixtureFeed(
        db,
        'F',
        {-1: 'One', -2: 'Two'},
        marks: {-1: 10, -2: 7},
        gateway: gw,
      );
      final c = await start(gw);
      expect(c.unreadOf(feed.id), 0);
      gw.arrive(fixturePost(-1, 11));
      await settle();
      expect(c.unreadOf(feed.id), 1);
      gw.arrive(fixturePost(-1, 12));
      await settle();
      expect(c.unreadOf(feed.id), 2);
    },
  );

  test('what the feed hides does not count', () async {
    final gw = TimelineGateway(
      {
        -1: [
          fixturePost(
            -1,
            4,
            media: const PhotoMedia(
              sizes: [FileRef(id: 1, remoteId: 'p', size: 10)],
            ),
          ),
          fixturePost(-1, 3),
          fixturePost(-1, 2),
        ],
      },
      channels: [_channel(-1, 4)],
    );
    final feed = await fixtureFeed(
      db,
      'F',
      {-1: 'One'},
      marks: {-1: 1},
      gateway: gw,
    );
    await db.setFeedFilter(
      feed.id,
      const FeedFilter(media: MediaPresence.withMedia).encode(),
    );
    final c = await start(gw);
    expect(c.unreadOf(feed.id), 1);

    // The same channel's text posts only: the photo is hidden now.
    await db.setFeedFilter(
      feed.id,
      const FeedFilter(media: MediaPresence.textOnly).encode(),
    );
    await settle();
    expect(c.unreadOf(feed.id), 2);

    // A deleted post stops counting.
    gw.posts.add(const PostsDeleted(chatId: -1, messageIds: [3]));
    await settle();
    expect(c.unreadOf(feed.id), 1);
  });

  test(
    'a shown album counts with every part in a feed of whole posts',
    () async {
      const photo = PhotoMedia(
        sizes: [FileRef(id: 1, remoteId: 'p', size: 10)],
      );
      const video = VideoMedia(
        file: FileRef(id: 2, remoteId: 'v', size: 10),
        durationSeconds: 30,
      );
      final gw = TimelineGateway(
        {
          -1: [
            fixturePost(-1, 3, albumId: 9, media: photo),
            fixturePost(-1, 2, albumId: 9, media: video),
            fixturePost(-1, 1),
          ],
        },
        channels: [_channel(-1, 3)],
      );
      final feed = await fixtureFeed(db, 'F', {-1: 'One'}, gateway: gw);
      await db.setFeedFilter(
        feed.id,
        const FeedFilter(kinds: {MediaKind.video}).encode(),
      );
      final c = await start(gw);
      // The text post, and the video bringing the picture of its album along.
      expect(c.unreadOf(feed.id), 3);

      await db.setFeedFilter(
        feed.id,
        const FeedFilter(kinds: {MediaKind.video}, wholePost: false).encode(),
      );
      await settle();
      expect(c.unreadOf(feed.id), 2);
    },
  );

  test('a channel in two feeds counts once on the tab', () async {
    final gw = twoChannels();
    final a = await fixtureFeed(
      db,
      'A',
      {-1: 'One'},
      marks: {-1: 6},
      gateway: gw,
    );
    // The read position lives in the gateway, so both feeds share it.
    final b = await fixtureFeed(db, 'B', {-1: 'One'});
    final c = await start(gw);
    // Posts 7 to 10, in both feeds; the tab counts the channel, not the rows.
    expect(c.unreadOf(a.id), 4);
    expect(c.unreadOf(b.id), 4);
    expect(c.unreadOnTab, 4);
  });

  test('the switch off counts channels', () async {
    await db.setSetting(SettingKeys.countUnreadPosts, 'false');
    final gw = twoChannels();
    final feed = await fixtureFeed(
      db,
      'F',
      {-1: 'One', -2: 'Two'},
      marks: {-1: 6, -2: 7},
      gateway: gw,
    );
    await fixtureFeed(db, 'Quiet', {-2: 'Two'});
    final c = await start(gw);
    expect(c.countPosts, isFalse);
    expect(c.unreadOf(feed.id), 1);
    expect(c.unreadOnTab, 1); // feeds with news, not their posts

    await db.setSetting(SettingKeys.countUnreadPosts, 'true');
    await settle();
    expect(c.unreadOf(feed.id), 4);
    expect(c.unreadOnTab, 4);
  });

  test('a filtered channel never read counts up to the cap', () async {
    final gw = TimelineGateway(
      {-1: fixtureHistory(-1, to: 1500)},
      channels: [_channel(-1, 1500)],
    );
    final feed = await fixtureFeed(db, 'F', {-1: 'One'}, gateway: gw);
    await db.setFeedFilter(
      feed.id,
      const FeedFilter(media: MediaPresence.textOnly).encode(),
    );
    final c = await start(gw);
    await settle();
    expect(c.unreadOf(feed.id), FeedsController.cap);
    // Reading the first half lets the count go on towards the newest post.
    await gw.markViewed(-1, [900]);
    await settle();
    await settle();
    expect(c.unreadOf(feed.id), 600);
  });
}
