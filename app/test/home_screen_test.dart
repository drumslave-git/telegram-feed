import 'package:app_db/app_db.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/feed_editor_screen.dart';
import 'package:telegram_feed/feeds/timeline_screen.dart';
import 'package:telegram_feed/home/channel_list.dart';
import 'package:telegram_feed/home/home_screen.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'timeline_screen_test.dart' show TimelineGateway;

// Drift does real I/O, so every step runs under tester.runAsync (real clock).
void main() {
  late AppDatabase db;
  late TimelineGateway gw;

  Post post(int chat, int id, String text) =>
      Post(chatId: chat, messageId: id, date: id, text: text);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    gw = TimelineGateway(
      {
        -1: [post(-1, 100, 'one-post')],
        -2: [post(-2, 200, 'two-post')],
      },
      channels: const [
        Channel(
          chatId: -1,
          title: 'One',
          lastMessageId: 100,
          lastMessageText: 'one-post',
          lastReadMessageId: 100,
        ),
        Channel(
          chatId: -2,
          title: 'Two',
          lastMessageId: 200,
          unreadCount: 7,
          lastMessageText: 'two-post',
        ),
        Channel(chatId: -3, title: 'Three'),
      ],
      folders: const [
        ChatFolder(id: 5, title: 'Work', channelIds: [-2, -1]),
      ],
    );
  });

  Widget app() => MaterialApp(
    home: HomeScreen(db: db, gateway: gw),
  );

  /// Lets real async work (database, streams) happen, then rebuilds.
  Future<void> settle(WidgetTester tester) => tester.runAsync(() async {
    for (var i = 0; i < 3; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await tester.pump();
    }
  });

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    await tester.pump(
      const Duration(seconds: 4),
    ); // the channel reload debounce
  }

  List<String> tabs(WidgetTester tester) => [
    for (final t in tester.widgetList<Tab>(find.byType(Tab)))
      t.text ?? ((t.child! as Row).children.first as Text).data!,
  ];

  testWidgets('tabs: Feeds, then folders with channels, then All channels', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await db.createFeed('Tech');
      await db.createFeed('Sports');
    });
    await tester.pumpWidget(app());
    await settle(tester);
    expect(tabs(tester), ['Feeds', 'Work', 'All channels']);
    expect(find.byTooltip('New feed'), findsOneWidget);
    // The Feeds tab is up first and lists the feeds.
    expect(find.text('Tech'), findsOneWidget);
    expect(find.text('Sports'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('empty state; + creates a feed and asks for its channels', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await settle(tester);
    expect(find.textContaining('No feeds yet'), findsOneWidget);

    await tester.tap(find.byTooltip('New feed'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Tech');
    await tester.tap(find.text('Create'));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(find.byType(FeedEditorScreen), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await settle(tester);
    expect(find.widgetWithText(ListTile, 'Tech'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('feed menu: rename and delete; a tap opens the timeline', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final f = await db.createFeed('A');
      await db.addSource(f.id, -1, title: 'One');
    });
    await tester.pumpWidget(app());
    await settle(tester);

    await tester.tap(find.text('A'));
    await tester.pumpAndSettle();
    await settle(tester);
    await tester.pumpAndSettle();
    expect(find.byType(TimelineScreen), findsOneWidget);
    expect(find.text('one-post'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Alpha');
    await tester.tap(find.text('Rename').last);
    await tester.pumpAndSettle();
    await settle(tester);
    expect(find.text('Alpha'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    await settle(tester);
    expect(find.textContaining('No feeds yet'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets(
    'badges: channels with new posts per feed, feeds with news on the tab',
    (tester) async {
      await tester.runAsync(() async {
        final f = await db.createFeed('News');
        await db.addSource(f.id, -1, title: 'One');
        await db.addSource(f.id, -2, title: 'Two');
        await db.markRead(f.id, -1, 100); // One fully read, Two not
        await db.createFeed('Quiet');
      });
      await tester.pumpWidget(app());
      await settle(tester);
      expect(find.text('1 channel with new posts'), findsOneWidget);
      final onTab = find.descendant(
        of: find.byType(TabBar),
        matching: find.byType(Badge),
      );
      expect(
        find.descendant(of: onTab, matching: find.text('1')),
        findsOneWidget,
      );

      await tester.runAsync(() async {
        final f = (await db.allFeeds()).first;
        await db.markRead(f.id, -2, 200);
      });
      await settle(tester);
      expect(find.textContaining('with new posts'), findsNothing);
      expect(onTab, findsNothing);

      gw.posts.add(PostAdded(post(-2, 201, 'x')));
      await settle(tester);
      expect(find.text('1 channel with new posts'), findsOneWidget);
      await unmount(tester);
    },
  );

  testWidgets('reordering feeds persists', (tester) async {
    late int a, b;
    await tester.runAsync(() async {
      a = (await db.createFeed('A')).id;
      b = (await db.createFeed('B')).id;
    });
    await tester.pumpWidget(app());
    await settle(tester);
    await tester.runAsync(() => db.reorderFeeds([b, a]));
    await settle(tester);
    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect((tiles.first.title! as Text).data, 'B');
    await unmount(tester);
  });

  testWidgets(
    'folder tab lists its channels in Telegram order; a channel opens',
    (tester) async {
      await tester.pumpWidget(app());
      await settle(tester);
      await tester.tap(find.text('Work'));
      await tester.pumpAndSettle();
      // Telegram's order for the folder: Two before One, with preview and unread count.
      final titles = [
        for (final t in tester.widgetList<ChannelTile>(
          find.byType(ChannelTile),
        ))
          t.channel.title,
      ];
      expect(titles, ['Two', 'One']);
      expect(find.text('two-post'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);

      await tester.tap(find.text('Two'));
      await tester.pumpAndSettle();
      await settle(tester);
      await tester.pumpAndSettle();
      expect(find.byType(TimelineScreen), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(PostCard),
          matching: find.text('two-post'),
        ),
        findsOneWidget,
      );
      // Telegram's read position is 0 here, so the post is unread and gets the divider.
      expect(find.text('Unread posts'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await unmount(tester);
    },
  );

  testWidgets('all channels: every channel, with search', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);
    await tester.tap(find.text('All channels'));
    await tester.pumpAndSettle();
    expect(find.byType(ChannelTile), findsNWidgets(3));
    await tester.enterText(find.byType(TextField), 'thr');
    await tester.pump();
    expect(find.byType(ChannelTile), findsOneWidget);
    expect(find.text('Three'), findsOneWidget);
    await unmount(tester);
  });

  test('formatListDate: time today, weekday this week, date before', () {
    final now = DateTime(2026, 9, 19, 12);
    expect(formatListDate(DateTime(2026, 9, 19, 8, 5), now: now), '08:05');
    expect(formatListDate(DateTime(2026, 9, 17, 8, 5), now: now), 'Thu');
    expect(formatListDate(DateTime(2026, 8, 1), now: now), '2026-08-01');
  });
}
