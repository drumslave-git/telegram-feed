import 'package:app_db/app_db.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/recent_searches.dart';
import 'package:telegram_feed/home/home_screen.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'timeline_screen_test.dart' show TimelineGateway;

void main() {
  late AppDatabase db;
  late TimelineGateway gw;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    gw = TimelineGateway(
      {
        -1: [const Post(chatId: -1, messageId: 1, date: 1, text: 'the needle')],
      },
      channels: const [Channel(chatId: -1, title: 'One')],
    );
  });

  test(
    'the newest words come first, without repeats, up to the limit',
    () async {
      final recent = RecentSearches(db, limit: 3);
      expect(await recent.load(), isEmpty);
      await recent.remember('one');
      await recent.remember('two');
      expect(await recent.remember('one'), ['one', 'two']);
      await recent.remember('three');
      expect(await recent.remember('four'), ['four', 'three', 'one']);
      // Blank words are not kept.
      expect(await recent.remember('   '), ['four', 'three', 'one']);
      await recent.clear();
      expect(await recent.load(), isEmpty);
    },
  );

  test('broken json is simply no history', () {
    expect(RecentSearches.decode(null), isEmpty);
    expect(RecentSearches.decode('not json'), isEmpty);
    expect(RecentSearches.decode('{}'), isEmpty);
    expect(RecentSearches.decode('["a", 1, "", "b"]'), ['a', 'b']);
  });

  testWidgets('the search bar offers the last words, and runs one again', (
    tester,
  ) async {
    Future<void> settle() => tester.runAsync(() async {
      for (var i = 0; i < 3; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 60));
        await tester.pump();
      }
    });

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(db: db, gateway: gw),
      ),
    );
    await settle();
    await tester.tap(find.byTooltip('Search posts'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'needle');
    await tester.pump(const Duration(milliseconds: 400));
    await settle();

    // Closing and opening again offers what was searched for.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Search posts'));
    await tester.pumpAndSettle();
    await settle();
    expect(find.text('Recent searches'), findsOneWidget);
    expect(find.text('needle'), findsOneWidget);

    // A tap runs it again.
    await tester.tap(find.text('needle'));
    await settle();
    expect(gw.globalQueries.last.startsWith('needle|'), isTrue);

    // Clearing empties the list.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Search posts'));
    await tester.pumpAndSettle();
    await settle();
    await tester.tap(find.text('Clear'));
    await settle();
    expect(find.text('Recent searches'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
  });
}
