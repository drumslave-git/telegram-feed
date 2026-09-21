import 'package:app_db/app_db.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/feed_editor_screen.dart';
import 'package:telegram_feed/home/channel_list.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fixtures.dart';

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
        lastReadMessageId: 500,
      ),
      Channel(
        chatId: -2,
        title: 'Beta Daily',
        username: 'beta',
        memberCount: 20,
        lastReadMessageId: 700,
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
    // Every channel comes with its avatar, in the picker and in the list of sources.
    final picker = find.byType(ChannelPicker);
    expect(
      find.descendant(of: picker, matching: find.byType(ChannelAvatar)),
      findsNWidgets(
        find
            .descendant(of: picker, matching: find.byType(ListTile))
            .evaluate()
            .length,
      ),
    );

    await tester.enterText(find.byType(TextField), 'bet');
    await tester.pump();
    expect(find.text('Alpha News'), findsNothing);
    // Ticked off, then added: the picker takes several at once (H-37).
    await tester.tap(find.text('Beta Daily'));
    await tester.pump();
    expect(find.text('1 channel ticked'), findsOneWidget);
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await settle(tester);
    expect(find.text('Beta Daily'), findsOneWidget);
    expect(find.text('@beta'), findsOneWidget);
    expect(find.byType(ChannelAvatar), findsOneWidget);
    // Adding a channel leaves its read position, which is Telegram's, alone.
    expect(gw.markedViewed, isEmpty);

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
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await settle(tester);

    await tester.tap(find.byIcon(Icons.remove_circle_outline).first);
    await settle(tester);
    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((t) => (t.title as Text).data)
        .toList();
    expect(titles, ['Show', 'Alpha News']); // the filter row, then the channels
    await unmount(tester);
  });

  testWidgets('the picker tags a channel with its other feeds', (tester) async {
    await tester.runAsync(() async {
      feedId = (await db.createFeed('Tech')).id;
      final other = await db.createFeed('Morning');
      await db.addSource(other.id, -1, title: 'Alpha News');
    });
    await tester.pumpWidget(app());
    await settle(tester);
    await tester.tap(find.text('Add channel'));
    await settle(tester);
    await tester.pumpAndSettle();

    final alpha = find.widgetWithText(ListTile, 'Alpha News');
    expect(
      tester
          .widget<FeedTags>(
            find.descendant(of: alpha, matching: find.byType(FeedTags)),
          )
          .names,
      ['Morning'],
    );
    // Beta Daily is in no feed at all.
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Beta Daily'),
        matching: find.byType(FeedTags),
      ),
      findsNothing,
    );
    await unmount(tester);
  });

  testWidgets('the picker ends above the keyboard', (tester) async {
    final many = [
      for (var i = 1; i <= 40; i++) Channel(chatId: -i, title: 'Channel $i'),
    ];
    // A keyboard of 300 px on an 800x600 window.
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ChannelPicker(channels: many)),
      ),
    );
    await tester.pump();
    await tester.dragUntilVisible(
      find.text('Channel 40'),
      find.byType(ListView),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    final keyboardTop = 600 - 300 / tester.view.devicePixelRatio;
    expect(
      tester.getBottomLeft(find.text('Channel 40')).dy,
      lessThanOrEqualTo(keyboardTop),
    );
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

  testWidgets('the picker adds several channels in one go', (tester) async {
    await tester.runAsync(() async {
      feedId = (await db.createFeed('Tech')).id;
    });
    await tester.pumpWidget(app());
    await settle(tester);

    await tester.tap(find.text('Add channel'));
    await settle(tester);
    await tester.pumpAndSettle();
    // Nothing ticked: the button waits.
    expect(find.text('Tick the channels to add'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Add'))
          .enabled,
      isFalse,
    );

    await tester.tap(find.text('Alpha News'));
    await tester.tap(find.text('Beta Daily'));
    await tester.pump();
    expect(find.text('2 channels ticked'), findsOneWidget);

    // A second tap takes one off again.
    await tester.tap(find.text('Beta Daily'));
    await tester.pump();
    expect(find.text('1 channel ticked'), findsOneWidget);
    await tester.tap(find.text('Beta Daily'));
    await tester.pump();

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await settle(tester);

    final sources = (await tester.runAsync(
      () => db.watchSourceChannels(feedId).first,
    ))!;
    expect(sources.map((s) => s.title), ['Alpha News', 'Beta Daily']);
    expect(gw.markedViewed, isEmpty);
    await unmount(tester);
  });

  testWidgets('the picker can hide the channels already in a feed', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final other = await db.createFeed('News');
      await db.addSource(other.id, -1, title: 'Alpha News');
      feedId = (await db.createFeed('Tech')).id;
    });
    await tester.pumpWidget(app());
    await settle(tester);

    await tester.tap(find.text('Add channel'));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('Alpha News'), findsOneWidget); // tagged with News
    expect(find.text('Beta Daily'), findsOneWidget);
    await tester.tap(find.text('Alpha News'));
    await tester.pump();
    expect(find.text('1 channel ticked'), findsOneWidget);

    // Hidden, the channel in News goes, and it is not added unseen.
    await tester.tap(find.text('Hide channels already in a feed'));
    await tester.pump();
    expect(find.text('Alpha News'), findsNothing);
    expect(find.text('Beta Daily'), findsOneWidget);
    expect(find.text('Tick the channels to add'), findsOneWidget);
    await settle(tester);
    expect(
      await tester.runAsync(
        () => db.setting(SettingKeys.pickerHidesChannelsInFeeds),
      ),
      'true',
    );

    // The choice stays for the next time the picker opens.
    await tester.tapAt(const Offset(400, 20));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add channel'));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('Alpha News'), findsNothing);
    expect(find.text('Beta Daily'), findsOneWidget);
    await unmount(tester);
  });
}
