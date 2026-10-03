import 'package:app_db/app_db.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/timeline_screen.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fixtures.dart';

void main() {
  const saved = ChannelsGateway.savedChatId;
  late AppDatabase db;
  late TimelineGateway gw;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    gw = TimelineGateway({
      saved: [
        const Post(chatId: saved, messageId: 3, date: 300, text: 'third'),
        const Post(chatId: saved, messageId: 2, date: 200, text: 'second'),
        const Post(chatId: saved, messageId: 1, date: 100, text: 'first'),
      ],
    });
    gw.readPositions[saved] = 3;
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

  Future<void> open(WidgetTester tester, {bool savedMessages = true}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          db: db,
          gateway: gw,
          channel: const Channel(chatId: saved, title: 'Saved Messages'),
          savedMessages: savedMessages,
        ),
      ),
    );
    await settle(tester);
    await tester.pumpAndSettle();
  }

  /// Opens the post's menu and scrolls it to [entry], which sits low in the sheet.
  Future<void> menuTo(WidgetTester tester, String post, String entry) async {
    await tester.longPress(find.text(post));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text(entry),
      120,
      scrollable: find.byType(Scrollable).last,
    );
  }

  Finder inDialog(String text) =>
      find.descendant(of: find.byType(AlertDialog), matching: find.text(text));

  testWidgets('a post of Saved Messages is deleted after asking', (
    tester,
  ) async {
    await open(tester);

    // Cancel keeps it.
    await menuTo(tester, 'second', 'Delete');
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(inDialog('Delete post'), findsOneWidget);
    expect(
      inDialog('Are you sure you want to delete this post?'),
      findsOneWidget,
    );
    await tester.tap(inDialog('Cancel'));
    await tester.pumpAndSettle();
    expect(gw.deletedSaved, isEmpty);
    expect(find.text('second'), findsOneWidget);

    await menuTo(tester, 'second', 'Delete');
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(inDialog('Delete'));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(gw.deletedSaved, ['2']);
    expect(find.text('second'), findsNothing);
    expect(find.text('third'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('the selection bar deletes the picked posts together', (
    tester,
  ) async {
    await open(tester);
    await menuTo(tester, 'second', 'Select');
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('first'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(inDialog('Delete 2 posts'), findsOneWidget);
    expect(
      inDialog('Are you sure you want to delete these posts?'),
      findsOneWidget,
    );
    await tester.tap(inDialog('Delete'));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(gw.deletedSaved.single.split(',').toSet(), {'1', '2'});
    expect(find.textContaining('selected'), findsNothing);
    expect(find.text('second'), findsNothing);
    expect(find.text('first'), findsNothing);
    expect(find.text('third'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('Saved Messages offers no Share, Copy link or Save: a post there '
      'has no link and is saved already', (tester) async {
    await open(tester);
    await menuTo(tester, 'second', 'Select');
    expect(find.text('Copy text'), findsOneWidget);
    expect(find.text('Share'), findsNothing);
    expect(find.text('Copy link'), findsNothing);
    expect(find.text('Save to Saved Messages'), findsNothing);
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Copy text'), findsOneWidget);
    expect(find.byTooltip('Share'), findsNothing);
    expect(find.byTooltip('Save to Saved Messages'), findsNothing);
    expect(find.byTooltip('Delete'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a post saved meanwhile appears without reopening the screen', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('fourth'), findsNothing);
    gw.arrive(
      const Post(chatId: saved, messageId: 4, date: 400, text: 'fourth'),
    );
    await settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('fourth'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a channel offers no Delete', (tester) async {
    await open(tester, savedMessages: false);
    await menuTo(tester, 'second', 'Select');
    expect(find.text('Delete'), findsNothing);
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Delete'), findsNothing);
    await unmount(tester);
  });
}
