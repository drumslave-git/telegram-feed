import 'package:app_db/app_db.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/mark_read.dart';
import 'package:telegram_feed/home/home_screen.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fixtures.dart';

void main() {
  late AppDatabase db;
  late TimelineGateway gw;

  const channels = [
    Channel(chatId: -1, title: 'One', lastMessageId: 100),
    Channel(chatId: -2, title: 'Two', lastMessageId: 200),
  ];

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    gw = TimelineGateway(
      const {},
      channels: channels,
      folders: const [
        ChatFolder(id: 5, title: 'Work', channelIds: [-2, -1]),
      ],
    );
  });

  tearDown(() => db.close());

  test(
    'a feed is marked read up to the newest post of every channel',
    () async {
      final feed = await db.createFeed('News');
      await db.addSource(feed.id, -1, title: 'One');
      await db.addSource(feed.id, -2, title: 'Two');
      final moved = await MarkRead(db: db, gateway: gw).feed(feed.id);
      expect(moved, 2);
      expect(await db.readMarks(feed.id), {-1: 100, -2: 200});
      // Telegram was told as well, since read sync is on by default.
      expect(gw.markedViewed, {
        -1: [100],
        -2: [200],
      });
    },
  );

  test('channels are marked read in every feed that holds them', () async {
    final a = await db.createFeed('A');
    final b = await db.createFeed('B');
    await db.addSource(a.id, -1, title: 'One');
    await db.addSource(b.id, -1, title: 'One');
    await db.addSource(b.id, -2, title: 'Two');

    final moved = await MarkRead(db: db, gateway: gw).channels([-1]);
    expect(moved, 1);
    expect(await db.readMarks(a.id), {-1: 100});
    // The other channel of B keeps the mark it started with.
    expect(await db.readMarks(b.id), {-1: 100, -2: 0});
    expect(gw.markedViewed, {
      -1: [100],
    });
  });

  test('with read sync off Telegram is left alone', () async {
    await db.setSetting(SettingKeys.syncReadToTelegram, 'false');
    final feed = await db.createFeed('News');
    await db.addSource(feed.id, -1, title: 'One');
    await MarkRead(db: db, gateway: gw).feed(feed.id);
    expect(await db.readMarks(feed.id), {-1: 100});
    expect(gw.markedViewed, isEmpty);
  });

  testWidgets('the feed menu and the folder tab carry the action', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final feed = await db.createFeed('News');
      await db.addSource(feed.id, -1, title: 'One');
    });
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(db: db, gateway: gw),
      ),
    );
    await tester.runAsync(() async {
      for (var i = 0; i < 3; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        await tester.pump();
      }
    });

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Mark all read'), findsOneWidget);
    await tester.tap(find.text('Mark all read'));
    await tester.runAsync(() async {
      for (var i = 0; i < 4; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        await tester.pump();
      }
    });
    expect(find.textContaining('marked read'), findsOneWidget);
    expect(
      await tester.runAsync(
        () async => db.readMarks((await db.allFeeds()).single.id),
      ),
      {-1: 100},
    );

    // The folder tab offers it too.
    await tester.longPress(find.text('Work'));
    await tester.pumpAndSettle();
    expect(find.text('Mark all read'), findsOneWidget);
    await tester.tapAt(const Offset(10, 700));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
  });
}
