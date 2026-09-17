import 'package:app_db/app_db.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/feed_editor_screen.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'feeds_screen_test.dart' show ChannelsGateway;

void main() {
  late AppDatabase db;
  late ChannelsGateway gw;
  late int feedId;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    gw = ChannelsGateway(const [
      Channel(
        chatId: -1,
        title: 'Alpha News',
        username: 'alpha',
        memberCount: 10,
      ),
      Channel(
        chatId: -2,
        title: 'Beta Daily',
        username: 'beta',
        memberCount: 20,
      ),
      Channel(chatId: -3, title: 'Gone', isMember: false),
    ]);
  });

  Widget app() => MaterialApp(
    home: FeedEditorScreen(db: db, gateway: gw, feedId: feedId),
  );

  Future<void> settle(WidgetTester tester) => tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await tester.pump();
  });

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('add from the searchable picker, then remove', (tester) async {
    await tester.runAsync(
      () async => feedId = (await db.createFeed('Tech')).id,
    );
    await tester.pumpWidget(app());
    await settle(tester);
    expect(find.textContaining('No channels yet'), findsOneWidget);

    await tester.tap(find.text('Add channel'));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('Alpha News'), findsOneWidget);
    expect(find.text('Beta Daily'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'bet');
    await tester.pump();
    expect(find.text('Alpha News'), findsNothing);
    await tester.tap(find.text('Beta Daily'));
    await tester.pumpAndSettle();
    await settle(tester);
    expect(find.text('Beta Daily'), findsOneWidget);
    expect(find.text('@beta'), findsOneWidget);

    // Already-added channels are not offered again.
    await tester.tap(find.text('Add channel'));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(
      find.text('Beta Daily'),
      findsOneWidget,
    ); // only the list entry behind the sheet
    expect(find.text('Alpha News'), findsOneWidget);
    await tester.tap(find.text('Alpha News'));
    await tester.pumpAndSettle();
    await settle(tester);

    await tester.tap(find.byIcon(Icons.remove_circle_outline).first);
    await settle(tester);
    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((t) => (t.title as Text).data)
        .toList();
    expect(titles, ['Alpha News']);
    await unmount(tester);
  });

  testWidgets('channels the account left are flagged', (tester) async {
    await tester.runAsync(() async {
      feedId = (await db.createFeed('Tech')).id;
      await db.addSource(feedId, -3, title: 'Gone');
    });
    await tester.pumpWidget(app());
    await settle(tester);
    expect(find.textContaining('Left in Telegram'), findsOneWidget);
    await unmount(tester);
  });
}
