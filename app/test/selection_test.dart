import 'package:app_db/app_db.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/timeline_screen.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'timeline_screen_test.dart' show TimelineGateway;

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
      await db.markRead(feed.id, -1, 3);
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

  /// Enters selection through the menu, as the official app does.
  Future<void> select(WidgetTester tester, String post) async {
    await tester.longPress(find.text(post));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select'));
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
}
