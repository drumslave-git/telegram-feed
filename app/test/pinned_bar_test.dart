import 'package:app_db/app_db.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/timeline_screen.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fixtures.dart';

void main() {
  late AppDatabase db;
  const channel = Channel(chatId: -1, title: 'One', lastMessageId: 3);

  Post post(int id, String text) =>
      Post(chatId: -1, messageId: id, date: id * 100, text: text);

  setUp(() => db = AppDatabase(NativeDatabase.memory()));

  Future<void> settle(WidgetTester tester) => tester.runAsync(() async {
    for (var i = 0; i < 3; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await tester.pump();
    }
  });

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('a channel with a pinned post shows the bar, and can hide it', (
    tester,
  ) async {
    final gw = TimelineGateway(
      {
        -1: [post(3, 'newest'), post(1, 'the pinned one')],
      },
      channels: const [channel],
    )..pinned = post(1, 'the pinned one');
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(db: db, gateway: gw, channel: channel),
      ),
    );
    await settle(tester);
    await tester.pumpAndSettle();

    expect(gw.pinnedAsked, [-1]);
    expect(find.byType(PinnedBar), findsOneWidget);
    expect(find.text('Pinned post'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(PinnedBar),
        matching: find.text('the pinned one'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Hide'));
    await tester.pumpAndSettle();
    expect(find.byType(PinnedBar), findsNothing);
    await unmount(tester);
  });

  testWidgets('a channel without one shows no bar', (tester) async {
    final gw = TimelineGateway(
      {
        -1: [post(3, 'newest')],
      },
      channels: const [channel],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(db: db, gateway: gw, channel: channel),
      ),
    );
    await settle(tester);
    await tester.pumpAndSettle();
    expect(find.byType(PinnedBar), findsNothing);
    await unmount(tester);
  });

  testWidgets('a feed has no bar: it mixes channels', (tester) async {
    final gw = TimelineGateway(
      {
        -1: [post(3, 'newest')],
      },
      channels: const [channel],
    )..pinned = post(1, 'the pinned one');
    late Feed feed;
    await tester.runAsync(() async {
      feed = await db.createFeed('Mix');
      await db.addSource(feed.id, -1, title: 'One');
    });
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(db: db, gateway: gw, feed: feed),
      ),
    );
    await settle(tester);
    await tester.pumpAndSettle();
    expect(gw.pinnedAsked, isEmpty);
    expect(find.byType(PinnedBar), findsNothing);
    await unmount(tester);
  });
}
