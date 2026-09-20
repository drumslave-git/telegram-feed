import 'package:app_db/app_db.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/timeline_screen.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fixtures.dart';

void main() {
  late AppDatabase db;
  late TimelineGateway gw;
  late Feed feed;

  const channels = [
    Channel(chatId: -1, title: 'One', username: 'one'),
    Channel(chatId: -1001446168251, title: 'Private', lastMessageId: 5 << 20),
  ];

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    gw = TimelineGateway({
      -1: [
        const Post(
          chatId: -1,
          messageId: 3,
          date: 300,
          text: 'see t.me/one/42 and t.me/c/1446168251/5 and example.org',
          entities: [
            TextEntity(
              offset: 4,
              length: 11,
              kind: TextEntityKind.link,
              url: 'https://t.me/one/42',
            ),
            TextEntity(
              offset: 20,
              length: 22,
              kind: TextEntityKind.link,
              url: 'https://t.me/c/1446168251/5',
            ),
            TextEntity(
              offset: 47,
              length: 11,
              kind: TextEntityKind.link,
              url: 'https://example.org',
            ),
          ],
        ),
      ],
      -1001446168251: [
        const Post(
          chatId: -1001446168251,
          messageId: 5 << 20,
          date: 100,
          text: 'the private post',
        ),
      ],
    }, channels: channels);
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

  Future<void> open(WidgetTester tester) async {
    await tester.runAsync(() async {
      feed = await db.createFeed('Links');
      await db.addSource(feed.id, -1, title: 'One');
      await db.markRead(feed.id, -1, 3);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(db: db, gateway: gw, feed: feed),
      ),
    );
    await settle(tester);
    await tester.pumpAndSettle();
  }

  testWidgets('a t.me link to a followed channel opens its timeline here', (
    tester,
  ) async {
    await open(tester);
    final state = tester.state<TimelineViewState>(find.byType(TimelineView));

    // A private channel of the account, with the post it names.
    expect(state.openLinkForTest('https://t.me/c/1446168251/5'), isTrue);
    await settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('Private'), findsWidgets);
    expect(find.text('the private post'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // A channel by username.
    expect(state.openLinkForTest('https://t.me/one/42'), isTrue);
    await settle(tester);
    await tester.pumpAndSettle();
    // The feed's screen is below, offstage under the channel's.
    expect(find.byType(TimelineScreen, skipOffstage: false), findsNWidgets(2));
    await tester.pageBack();
    await tester.pumpAndSettle();

    // A web page, and a channel the account does not follow, are for other apps.
    expect(state.openLinkForTest('https://example.org/story'), isFalse);
    expect(state.openLinkForTest('https://t.me/someone-else/1'), isFalse);
    await unmount(tester);
  });
}
