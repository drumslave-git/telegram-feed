import 'package:app_db/app_db.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/timeline_screen.dart';
import 'package:telegram_feed/home/home_screen.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'timeline_screen_test.dart' show TimelineGateway;

void main() {
  late AppDatabase db;
  late TimelineGateway gw;

  Post post(int chat, int id, String text) =>
      Post(chatId: chat, messageId: id, date: id, text: text);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    gw = TimelineGateway(
      {
        -1: [post(-1, 100, 'the needle is here')],
        -2: [post(-2, 200, 'nothing of note')],
      },
      channels: const [
        Channel(chatId: -1, title: 'One', lastMessageId: 100),
        Channel(chatId: -2, title: 'Two', lastMessageId: 200),
      ],
    );
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
    await tester.pump(const Duration(seconds: 4));
  }

  testWidgets('the home screen searches every channel and opens a result', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(db: db, gateway: gw),
      ),
    );
    await settle(tester);

    await tester.tap(find.byTooltip('Search posts'));
    await tester.pumpAndSettle();
    expect(find.text('Type to search the posts.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'needle');
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    expect(gw.globalQueries.first.startsWith('needle|'), isTrue);
    expect(find.textContaining('the needle is here'), findsOneWidget);
    // The row names the channel the post came from.
    expect(find.text('One'), findsWidgets);

    await tester.tap(find.textContaining('the needle is here'));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(find.byType(TimelineScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await unmount(tester);
  });

  testWidgets('a query with nothing in it says so', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(db: db, gateway: gw),
      ),
    );
    await settle(tester);
    await tester.tap(find.byTooltip('Search posts'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    expect(find.textContaining('Nothing found'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a chip narrows the search to a kind of post', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(db: db, gateway: gw),
      ),
    );
    await settle(tester);
    await tester.tap(find.byTooltip('Search posts'));
    await tester.pumpAndSettle();
    expect(find.text('Everything'), findsOneWidget);
    expect(find.text('Links'), findsOneWidget);

    // A kind alone is a search: no words needed.
    await tester.tap(find.text('Files'));
    await settle(tester);
    expect(gw.globalQueries.last, startsWith('|HistoryFilter.document'));

    // With words, the kind travels with them.
    await tester.enterText(find.byType(TextField), 'needle');
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    expect(gw.globalQueries.last, startsWith('needle|HistoryFilter.document'));
    await unmount(tester);
  });
}
