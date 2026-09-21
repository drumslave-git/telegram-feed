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
    'the badge counts the posts the timeline would show, an album as one',
    () async {
      final gw = twoChannels();
      final feed = await fixtureFeed(
        db,
        'F',
        {-1: 'One', -2: 'Two'},
        marks: {-1: 6, -2: 3},
      );
      final c = await start(gw);
      expect(c.countPosts, isTrue);
      // One: 7 to 10. Two: post 4 and the album of 5 to 7.
      expect(c.unreadOf(feed.id), 6);
      expect(c.unreadChannelsOf(feed.id), 2);
      expect(c.unreadOnTab, 6);
    },
  );

  test('reading lowers the count without asking the history again', () async {
    final gw = twoChannels();
    final feed = await fixtureFeed(
      db,
      'F',
      {-1: 'One', -2: 'Two'},
      marks: {-1: 6, -2: 3},
    );
    final c = await start(gw);
    final asked = gw.historyCalls;
    await db.markRead(feed.id, -1, 8);
    await settle();
    expect(c.unreadOf(feed.id), 4); // 9, 10 and Two's two
    await db.markRead(feed.id, -2, 7);
    await settle();
    expect(c.unreadOf(feed.id), 2);
    expect(c.unreadChannelsOf(feed.id), 1);
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
      );
      final c = await start(gw);
      expect(c.unreadOf(feed.id), 0);
      gw.arrive(fixturePost(-1, 11));
      await settle();
      expect(c.unreadOf(feed.id), 1);
      gw.arrive(fixturePost(-1, 12));
      await settle();
      expect(c.unreadOf(feed.id), 2);
      // Deleted before it was read: nothing is left to read past it.
      gw.posts.add(const PostsDeleted(chatId: -1, messageIds: [12]));
      await settle();
      expect(c.unreadOf(feed.id), 1);
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
    final feed = await fixtureFeed(db, 'F', {-1: 'One'}, marks: {-1: 1});
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
  });

  test(
    'the switch off counts channels, from one page of history each',
    () async {
      await db.setSetting(SettingKeys.countUnreadPosts, 'false');
      final gw = twoChannels();
      final feed = await fixtureFeed(
        db,
        'F',
        {-1: 'One', -2: 'Two'},
        marks: {-1: 6, -2: 7},
      );
      await fixtureFeed(db, 'Quiet', {-2: 'Two'}, marks: {-2: 7});
      final c = await start(gw);
      expect(c.countPosts, isFalse);
      expect(c.unreadOf(feed.id), 1);
      expect(c.unreadOnTab, 1); // feeds with news, not their posts
      expect(gw.historyCalls, 1); // One only: Two is read in both feeds

      await db.setSetting(SettingKeys.countUnreadPosts, 'true');
      await settle();
      expect(c.unreadOf(feed.id), 4);
      expect(c.unreadOnTab, 4);
    },
  );

  test(
    'a channel never read counts from its newest post, up to the cap',
    () async {
      final gw = TimelineGateway(
        {-1: fixtureHistory(-1, to: 1500)},
        channels: [_channel(-1, 1500)],
      );
      final feed = await fixtureFeed(db, 'F', {-1: 'One'}, marks: {-1: 0});
      final c = await start(gw);
      await settle();
      expect(c.unreadOf(feed.id), FeedsController.cap);
      // Reading the first half lets the count go on towards the newest post.
      await db.markRead(feed.id, -1, 900);
      await settle();
      await settle();
      expect(c.unreadOf(feed.id), 600);
    },
  );
}
