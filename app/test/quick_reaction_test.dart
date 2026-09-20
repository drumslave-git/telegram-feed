import 'package:app_db/app_db.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/post_card.dart';
import 'package:telegram_feed/feeds/timeline_screen.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fixtures.dart';

void main() {
  late AppDatabase db;
  late TimelineGateway gw;
  late Feed feed;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    gw = TimelineGateway({
      -1: [
        const Post(
          chatId: -1,
          messageId: 3,
          date: 300,
          text: 'react to me',
          reactions: [Reaction(emoji: 'X', count: 2)],
        ),
      ],
    });
  });

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

  /// Two taps close enough together for the double tap recognizer.
  Future<void> doubleTap(WidgetTester tester, Finder target) async {
    await tester.tap(target);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    await tester.runAsync(() async {
      feed = await db.createFeed('Quick');
      await db.addSource(feed.id, -1, title: 'One');
    });
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(db: db, gateway: gw, feed: feed),
      ),
    );
    await settle(tester);
    await tester.pumpAndSettle();
  }

  testWidgets('a double tap sends the thumbs up, and takes it back', (
    tester,
  ) async {
    await open(tester);
    final post = find.text('react to me');
    await doubleTap(tester, post);
    expect(gw.reactions, ['-1/3 +$defaultQuickReaction']);

    // Telegram reports it as chosen; the next double tap removes it.
    gw.histories[-1] = [
      Post(
        chatId: -1,
        messageId: 3,
        date: 300,
        text: 'react to me',
        reactions: [
          Reaction(emoji: defaultQuickReaction, count: 1, chosen: true),
        ],
      ),
    ];
    gw.posts.add(PostEdited(gw.histories[-1]!.single));
    await settle(tester);
    await tester.pumpAndSettle();
    await doubleTap(tester, post);
    expect(gw.reactions.last, '-1/3 -$defaultQuickReaction');
    await unmount(tester);
  });

  testWidgets('reacting from the menu makes that emoji the quick one', (
    tester,
  ) async {
    await open(tester);
    await tester.longPress(find.text('react to me'));
    await tester.pumpAndSettle();
    // The scripted channel allows a thumbs up and a flame.
    const flame = 'fire';
    await tester.tap(
      find
          .byWidgetPredicate(
            (w) =>
                w is Text &&
                w.data != null &&
                w.data != defaultQuickReaction &&
                w.data!.isNotEmpty &&
                w.data!.length <= 2,
          )
          .last,
    );
    await tester.pumpAndSettle();
    expect(gw.reactions.length, 1);
    final chosen = gw.reactions.single.split('+').last;
    expect(
      await tester.runAsync(() => db.setting(SettingKeys.quickReaction)),
      chosen,
    );
    expect(flame, 'fire'); // keeps the intent readable

    // A double tap now sends the same emoji.
    await doubleTap(tester, find.text('react to me'));
    expect(gw.reactions.last, '-1/3 +$chosen');
    await unmount(tester);
  });
}
