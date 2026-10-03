import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:telegram_feed/feeds/calendar_screen.dart';
import 'package:telegram_feed/feeds/media_view.dart';
import 'package:telegram_feed/feeds/post_card.dart' show formatChatDay;
import 'package:telegram_feed/l10n/l10n.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fixtures.dart';

void main() {
  final now = DateTime(2026, 10, 3, 12);

  int at(DateTime day) => day.millisecondsSinceEpoch ~/ 1000;

  Post picture(int chatId, int id, DateTime day) => Post(
    chatId: chatId,
    messageId: id,
    date: at(day),
    text: '',
    media: PhotoMedia(
      sizes: [
        FileRef(
          id: 1000 + id,
          remoteId: 'p$id',
          size: 10,
          width: 90,
          height: 90,
        ),
      ],
    ),
  );

  Post words(int chatId, int id, DateTime day) =>
      Post(chatId: chatId, messageId: id, date: at(day), text: 'words');

  Future<DateTime?> open(
    WidgetTester tester,
    TimelineGateway gw, {
    List<int> chatIds = const [-1],
    DateTime? around,
  }) async {
    DateTime? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              picked = await Navigator.of(context).push<DateTime>(
                MaterialPageRoute(
                  builder: (_) => CalendarScreen(
                    gateway: gw,
                    chatIds: chatIds,
                    around: around,
                    now: now,
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 400));
    await settleFixtures(tester);
    await tester.pump(const Duration(milliseconds: 400));
    return picked;
  }

  Finder day(String label) => find.bySemanticsLabel(RegExp('^$label'));

  testWidgets('this month stands at the bottom, days with a photo or a video '
      'show it, and a tap picks the day', (tester) async {
    final gw = TimelineGateway({
      -1: [
        picture(-1, 5, DateTime(2026, 10, 2, 9)),
        words(-1, 4, DateTime(2026, 10, 1, 9)),
        picture(-1, 3, DateTime(2026, 9, 20, 9)),
      ],
    });
    DateTime? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              picked = await Navigator.of(context).push<DateTime>(
                MaterialPageRoute(
                  builder: (_) => CalendarScreen(
                    gateway: gw,
                    chatIds: const [-1],
                    now: now,
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 400));
    await settleFixtures(tester);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.text('September 2026'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('September 2026')).dy,
      lessThan(tester.getTopLeft(find.text('October 2026')).dy),
    );
    // Two days carry a picture; a day with words alone does not.
    expect(find.byType(PhotoView), findsNWidgets(2));
    expect(day('October 2, 2026, with a picture'), findsOneWidget);
    expect(day('September 20, 2026, with a picture'), findsOneWidget);
    expect(day('October 1, 2026, with a picture'), findsNothing);

    // A day to come cannot be picked.
    await tester.tap(day('October 4, 2026'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CalendarScreen), findsOneWidget);

    await tester.tap(day('October 2, 2026'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CalendarScreen), findsNothing);
    expect(picked, DateTime(2026, 10, 2));
  });

  testWidgets('a feed shows the newest picture of a day among its channels, and '
      'older pages are read as the months come up', (tester) async {
    final gw = TimelineGateway({
      -1: [
        picture(-1, 9, DateTime(2026, 10, 2, 9)),
        picture(-1, 8, DateTime(2026, 9, 2, 9)),
        picture(-1, 7, DateTime(2026, 3, 2, 9)),
        picture(-1, 6, DateTime(2025, 12, 2, 9)),
      ],
      -2: [picture(-2, 4, DateTime(2026, 10, 2, 18))],
    })..calendarPage = 2;
    await open(tester, gw, chatIds: const [-1, -2]);

    // One picture for October 2, the later one, which is the other channel's.
    expect(find.byType(PhotoView), findsNWidgets(2));
    final shown = tester
        .widgetList<PhotoView>(find.byType(PhotoView))
        .map((v) => v.file.remoteId);
    expect(shown, containsAll(<String>['p4', 'p8']));
    // Every channel is asked from its newest post, and on from where a page ended while
    // months older than that page are on the list.
    expect(gw.calendarAsked, containsAll(<String>['-1|0', '-2|0', '-1|8']));
    expect(gw.calendarAsked, isNot(contains('-1|6')));

    // Up into last winter: the page after that is read, and it is the last one.
    await tester.drag(find.byType(Scrollable).last, const Offset(0, 3000));
    await tester.pump(const Duration(milliseconds: 400));
    await settleFixtures(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(gw.calendarAsked, contains('-1|6'));
    expect(gw.calendarAsked.where((a) => a.startsWith('-1|')), hasLength(3));
  });

  testWidgets('the calendar opens at the month it was asked for', (
    tester,
  ) async {
    final gw = TimelineGateway({-1: const []});
    await open(tester, gw, around: DateTime(2025, 2, 10));
    expect(find.text('February 2025'), findsOneWidget);
    expect(find.text('October 2026'), findsNothing);
  });

  test('the day on a separator is a date, never "Today"', () async {
    await initializeDateFormatting('uk');
    final en = lookupAppLocalizations(const Locale('en'));
    final uk = lookupAppLocalizations(const Locale('uk'));
    expect(
      formatChatDay(DateTime(2026, 10, 3), now: now, l10n: en),
      'October 3',
    );
    expect(
      formatChatDay(DateTime(2026, 10, 2), now: now, l10n: en),
      'October 2',
    );
    expect(
      formatChatDay(DateTime(2025, 12, 31), now: now, l10n: en),
      'December 31',
    );
    // A year away or more: with the year.
    expect(
      formatChatDay(DateTime(2025, 10, 1), now: now, l10n: en),
      'October 1, 2025',
    );
    expect(
      formatChatDay(DateTime(2026, 10, 3), now: now, l10n: uk),
      '3 жовтня',
    );
  });
}
