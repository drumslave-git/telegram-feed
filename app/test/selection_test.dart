import 'dart:async';

import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/timeline_screen.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fixtures.dart';

void main() {
  late AppDatabase db;
  late TimelineGateway gw;
  late Feed feed;
  final clipboard = <String>[];
  final shared = <String>[];

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    gw = TimelineGateway({
      -1: [
        const Post(chatId: -1, messageId: 3, date: 300, text: 'third'),
        const Post(chatId: -1, messageId: 2, date: 200, text: 'second'),
        const Post(chatId: -1, messageId: 1, date: 100, text: 'first'),
      ],
    });
    clipboard.clear();
    shared.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
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
      feed = await db.createFeed('Pick');
      await db.addSource(feed.id, -1, title: 'One');
      gw.readPositions[-1] = 3;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          db: db,
          gateway: gw,
          feed: feed,
          share: (text, {required subject}) async => shared.add(text),
        ),
      ),
    );
    await settle(tester);
    await tester.pumpAndSettle();
  }

  /// Enters selection with a long press, as the official app does.
  Future<void> select(WidgetTester tester, String post) async {
    await tester.longPress(find.text(post));
    await tester.pumpAndSettle();
  }

  testWidgets('Select opens the bar; taps pick more; Cancel leaves it', (
    tester,
  ) async {
    await open(tester);
    await select(tester, 'second');
    expect(find.text('1 selected'), findsOneWidget);

    // A tap now picks instead of opening anything.
    await tester.tap(find.text('third'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);

    // The same tap again lets it go.
    await tester.tap(find.text('third'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);

    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();
    expect(find.textContaining('selected'), findsNothing);
    await unmount(tester);
  });

  testWidgets(
    'the finger of the long press picks the posts it is dragged over, '
    'and lets them go on its way back',
    (tester) async {
      await open(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('first')),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);

      await gesture.moveTo(tester.getCenter(find.text('second')));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      await gesture.moveTo(tester.getCenter(find.text('third')));
      await tester.pumpAndSettle();
      expect(find.text('3 selected'), findsOneWidget);

      await gesture.moveTo(tester.getCenter(find.text('second')));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      await unmount(tester);
    },
  );

  testWidgets('a selection holds a hundred posts and no more', (tester) async {
    final felt = recordHaptics(tester);
    await open(tester);
    final view = tester.state<TimelineViewState>(find.byType(TimelineView));
    TimelineItem row(int id) =>
        TimelineItem(Post(chatId: -1, messageId: id, date: id, text: 'p$id'));
    for (var id = 1; id <= TimelineViewState.maxSelected; id++) {
      view.toggleSelected(row(id));
    }
    await tester.pump();
    expect(find.text('100 selected'), findsOneWidget);
    expect(felt, isEmpty);
    view.toggleSelected(row(101));
    await tester.pump();
    expect(find.text('100 selected'), findsOneWidget);
    // Refused with the long buzz of the official app.
    expect(felt, ['buzz 200']);
    // One that is picked can still be let go.
    view.toggleSelected(row(1));
    await tester.pump();
    expect(find.text('99 selected'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('the long press that starts a selection is felt', (tester) async {
    final felt = recordHaptics(tester);
    await open(tester);
    await tester.longPress(find.text('second'));
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);
    expect(felt, ['vibrate']);
    await unmount(tester);
  });

  testWidgets('the menu has no Select: a long press is how posts are picked', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('first'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('Copy text'), findsOneWidget);
    expect(find.text('Select'), findsNothing);
    await unmount(tester);
  });

  testWidgets('back leaves the selection, then the search, then the screen', (
    tester,
  ) async {
    await tester.runAsync(() async {
      feed = await db.createFeed('Pick');
      await db.addSource(feed.id, -1, title: 'One');
      gw.readPositions[-1] = 3;
    });
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: nav, home: const Text('home')),
    );
    unawaited(
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => TimelineScreen(db: db, gateway: gw, feed: feed),
        ),
      ),
    );
    await settle(tester);
    await tester.pumpAndSettle();

    await select(tester, 'second');
    expect(find.text('1 selected'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.textContaining('selected'), findsNothing);
    expect(find.text('second'), findsOneWidget);

    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('second'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('the words of every picked post are copied, oldest first', (
    tester,
  ) async {
    await open(tester);
    await select(tester, 'third');
    await tester.tap(find.text('first'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Copy text'));
    await tester.pumpAndSettle();
    expect(clipboard.single.startsWith('first'), isTrue);
    expect(clipboard.single.contains('third'), isTrue);
    expect(find.textContaining('2 posts copied'), findsOneWidget);
    // The bar is gone once the action ran.
    expect(find.textContaining('selected'), findsNothing);
    await unmount(tester);
  });

  testWidgets('every picked post is saved, and shared, in one go', (
    tester,
  ) async {
    await open(tester);
    await select(tester, 'first');
    await tester.tap(find.text('second'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Save to Saved Messages'));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(gw.saved, ['-1:1,2']);

    await select(tester, 'first');
    await tester.tap(find.byTooltip('Share'));
    await tester.pumpAndSettle();
    expect(shared.single.contains('first'), isTrue);
    await unmount(tester);
  });

  testWidgets('an album is shared with its caption, whichever part holds it', (
    tester,
  ) async {
    const file = FileRef(id: 1, remoteId: 'r', size: 1, width: 4, height: 3);
    gw.histories[-1] = [
      // The caption sits on the first picture, which is not the newest part.
      const Post(
        chatId: -1,
        messageId: 5,
        date: 500,
        text: '',
        albumId: 9,
        media: PhotoMedia(sizes: [file]),
      ),
      const Post(
        chatId: -1,
        messageId: 4,
        date: 500,
        text: 'three views of the quay',
        albumId: 9,
        media: PhotoMedia(sizes: [file]),
      ),
    ];
    await tester.runAsync(() async {
      feed = await db.createFeed('Pick');
      await db.addSource(feed.id, -1, title: 'One', username: 'one');
      gw.readPositions[-1] = 5;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          db: db,
          gateway: gw,
          feed: feed,
          share: (text, {required subject}) async => shared.add(text),
        ),
      ),
    );
    await settle(tester);
    // The pictures never arrive, so their spinners never settle.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('three views of the quay'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Share'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(shared.single, contains('three views of the quay'));
    await unmount(tester);
  });
}
