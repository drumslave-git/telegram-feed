import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/feed_editor_screen.dart';
import 'package:telegram_feed/feeds/timeline_screen.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fixtures.dart';

void main() {
  late AppDatabase db;
  late TimelineGateway gw;
  late Feed feed;

  const file = FileRef(
    id: 1,
    remoteId: 'r',
    size: 1,
    width: 10,
    height: 10,
    localPath: 'missing.png',
  );
  Post text(int id) =>
      Post(chatId: -1, messageId: id, date: id, text: 'text-$id');
  Post voice(int id) => Post(
    chatId: -1,
    messageId: id,
    date: id,
    text: 'voice-$id',
    media: const AudioMedia(file: file, durationSeconds: 5, isVoice: true),
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    gw = TimelineGateway({
      -1: [text(6), text(5), voice(4), text(3), voice(2), text(1)],
    });
  });

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
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets(
    'timeline shows only what the filter lets through; hidden posts get read',
    (tester) async {
      await tester.runAsync(() async {
        feed = await db.createFeed('Voices');
        await db.addSource(feed.id, -1, title: 'One');
        await db.markRead(feed.id, -1, 1);
        await db.setFeedFilter(
          feed.id,
          const FeedFilter(media: MediaPresence.withMedia).encode(),
        );
        feed = (await db.allFeeds()).single;
      });
      await tester.pumpWidget(
        MaterialApp(
          home: TimelineScreen(db: db, gateway: gw, feed: feed),
        ),
      );
      await settle(tester);
      await tester.pumpAndSettle();
      expect(find.text('voice-2'), findsOneWidget);
      expect(find.text('voice-4'), findsOneWidget);
      expect(find.textContaining('text-'), findsNothing);

      await unmount(tester); // flushes the marks
      final marks = await tester.runAsync(() => db.readMarks(feed.id));
      // Both voice posts were on screen; the text posts after the last one are covered too.
      expect(marks![-1], 6);
    },
  );

  testWidgets('a filter that hides everything says so', (tester) async {
    await tester.runAsync(() async {
      feed = await db.createFeed('Photos');
      await db.addSource(feed.id, -1, title: 'One');
      await db.setFeedFilter(
        feed.id,
        const FeedFilter(
          kinds: {MediaKind.photo},
          media: MediaPresence.withMedia,
        ).encode(),
      );
      feed = (await db.allFeeds()).single;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(db: db, gateway: gw, feed: feed),
      ),
    );
    await settle(tester);
    expect(
      find.textContaining("No posts pass this feed's filter"),
      findsOneWidget,
    );
    await unmount(tester);
  });

  testWidgets('feed editor: the Show row edits and saves the filter', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      feed = await db.createFeed('Tech');
      await db.addSource(feed.id, -1, title: 'One');
    });
    await tester.pumpWidget(
      MaterialApp(
        home: FeedEditorScreen(db: db, gateway: gw, feedId: feed.id),
      ),
    );
    await settle(tester);
    expect(find.text('Everything'), findsOneWidget);

    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('With media'));
    await tester.pump();
    await tester.tap(find.text('Videos'));
    await tester.pump();
    await tester.tap(find.text('Any length').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('From 2 min').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    await settle(tester);

    final saved = await tester.runAsync(() => db.allFeeds());
    expect(
      FeedFilter.decode(saved!.single.filterJson),
      const FeedFilter(
        media: MediaPresence.withMedia,
        kinds: {MediaKind.video},
        minVideoSeconds: 120,
      ),
    );
    expect(find.text('with media · video · videos from 2 min'), findsOneWidget);

    // Whole posts are on by default; unchecking travels into the feed as well.
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isTrue,
    );
    await tester.tap(find.text('Show the whole post'));
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    await settle(tester);
    final again = await tester.runAsync(() => db.allFeeds());
    expect(FeedFilter.decode(again!.single.filterJson).wholePost, isFalse);
    expect(find.textContaining('matching parts only'), findsOneWidget);
    await unmount(tester);
  });
}
