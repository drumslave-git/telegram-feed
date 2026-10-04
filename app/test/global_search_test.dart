import 'package:app_db/app_db.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/recent_searches.dart';
import 'package:telegram_feed/feeds/shared_media.dart';
import 'package:telegram_feed/feeds/timeline_screen.dart';
import 'package:telegram_feed/feeds/timeline_search.dart';
import 'package:telegram_feed/home/home_screen.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fixtures.dart';

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

  testWidgets('a post of an archived channel is found, named and opened', (
    tester,
  ) async {
    gw.histories[-9] = [post(-9, 900, 'the ledger closes')];
    gw.archived = const [Channel(chatId: -9, title: 'Put Away')];
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(db: db, gateway: gw),
      ),
    );
    await settle(tester);
    await tester.tap(find.byTooltip('Search posts'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ledger');
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    expect(find.text('Put Away'), findsOneWidget);

    await tester.tap(find.textContaining('the ledger closes'));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(find.byType(TimelineScreen), findsOneWidget);
    expect(find.text('That channel is not in your list.'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await unmount(tester);
  });

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

  testWidgets('back closes the search and stays on the home screen', (
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
    expect(find.byType(TextField), findsOneWidget);
    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(handled, isTrue);
    expect(find.text('Type to search the posts.'), findsNothing);
    expect(find.byTooltip('Search posts'), findsOneWidget);
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

  testWidgets('a typed date is offered as a span of days and narrows the '
      'search, with words or alone', (tester) async {
    final now = DateTime.now();
    int at(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;
    final yesterday = DateTime(now.year, now.month, now.day - 1, 12);
    Post dated(int chat, int id, int date, String text) =>
        Post(chatId: chat, messageId: id, date: date, text: text);
    gw.histories[-1] = [
      dated(-1, 103, at(DateTime(now.year, now.month, now.day)), 'rain today'),
      dated(-1, 102, at(yesterday), 'rain the day before'),
      dated(
        -1,
        101,
        at(now.subtract(const Duration(days: 9))),
        'rain long ago',
      ),
    ];
    gw.histories[-2] = [
      dated(-2, 201, at(yesterday) + 60, 'sun the day before'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(db: db, gateway: gw),
      ),
    );
    await settle(tester);
    await tester.tap(find.byTooltip('Search posts'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'yest');
    await tester.pump();
    expect(find.widgetWithText(ActionChip, 'Yesterday'), findsOneWidget);
    await tester.tap(find.widgetWithText(ActionChip, 'Yesterday'));
    await settle(tester);

    // The date left the field and stands before the kinds; a day alone lists what
    // every channel posted on it.
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect(find.widgetWithText(InputChip, 'Yesterday'), findsOneWidget);
    expect(find.byType(ActionChip), findsNothing);
    expect(find.textContaining('rain the day before'), findsOneWidget);
    expect(find.textContaining('sun the day before'), findsOneWidget);
    expect(find.textContaining('rain today'), findsNothing);
    expect(find.textContaining('rain long ago'), findsNothing);
    expect(find.text('2 posts found'), findsOneWidget);

    // With words Telegram is asked once, for that span.
    await tester.enterText(find.byType(TextField), 'rain');
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    final day = DateTime(now.year, now.month, now.day - 1);
    expect(
      gw.globalQueries.last,
      'rain|HistoryFilter.any||${at(day)}-${at(day) + 86399}',
    );
    expect(find.textContaining('the day before'), findsOneWidget);
    expect(find.textContaining('today'), findsNothing);

    // Without the date the words find everything again.
    await tester.tap(find.byTooltip('Delete'));
    await settle(tester);
    expect(find.byType(InputChip), findsNothing);
    expect(gw.globalQueries.last, 'rain|HistoryFilter.any|');
    expect(find.text('3 posts found'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a day on which nothing was posted says that nothing was found', (
    tester,
  ) async {
    // Channels that have posted nothing at all.
    gw.histories[-1] = [];
    gw.histories[-2] = [];
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(db: db, gateway: gw),
      ),
    );
    await settle(tester);
    await tester.runAsync(() => RecentSearches(db).remember('needle'));
    await tester.tap(find.byTooltip('Search posts'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'today');
    await tester.pump();
    await tester.tap(find.widgetWithText(ActionChip, 'Today'));
    await settle(tester);
    expect(find.text('Nothing found.'), findsOneWidget);
    expect(find.text('Type to search the posts.'), findsNothing);

    // A kind of post that nobody posted says the same, and not the words searched last.
    await tester.tap(find.byTooltip('Delete'));
    await settle(tester);
    expect(find.text('Recent searches'), findsOneWidget);
    await tester.tap(find.text('Media'));
    await settle(tester);
    expect(find.text('Nothing found.'), findsOneWidget);
    expect(find.text('Recent searches'), findsNothing);
    await unmount(tester);
  });

  testWidgets('a kind of post is listed in its own layout, and a long press '
      'goes to the post', (tester) async {
    const picture = FileRef(
      id: 7,
      remoteId: 'p',
      size: 10,
      width: 40,
      height: 30,
    );
    gw.histories[-1] = [
      const Post(
        chatId: -1,
        messageId: 103,
        date: 103,
        text: 'the quay',
        media: PhotoMedia(sizes: [picture]),
      ),
      const Post(
        chatId: -1,
        messageId: 102,
        date: 102,
        text: 'the timetable',
        media: DocumentMedia(
          file: FileRef(id: 8, remoteId: 'd', size: 2048),
          fileName: 'ferries.pdf',
          mimeType: 'application/pdf',
        ),
      ),
    ];
    gw.histories[-2] = [];
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(db: db, gateway: gw),
      ),
    );
    await settle(tester);
    await tester.tap(find.byTooltip('Search posts'));
    await tester.pumpAndSettle();

    // Pictures and videos: a grid of tiles.
    await tester.enterText(find.byType(TextField), 'quay');
    await tester.tap(find.text('Media'));
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    expect(find.byType(MediaTile), findsOneWidget);
    expect(find.byType(SearchResultTile), findsNothing);
    expect(find.text('1 post found'), findsOneWidget);

    // Files: the rows of the shared media, each under the name of its channel.
    await tester.enterText(find.byType(TextField), 'timetable');
    await tester.tap(find.text('Files'));
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    expect(find.byType(FileRow), findsOneWidget);
    expect(find.text('ferries.pdf'), findsOneWidget);
    expect(find.text('One'), findsWidgets);

    await tester.longPress(find.text('ferries.pdf'));
    await settle(tester);
    // The channel's picture keeps loading: the screen is given time, not waited out.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(TimelineScreen), findsOneWidget);
    await unmount(tester);
  });
}
