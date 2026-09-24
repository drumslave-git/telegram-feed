import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/media/media_viewer.dart' show MediaViewerScreen;
import 'package:telegram_feed/service/reading_now.dart';
import 'package:telegram_feed/widgets/status_banner.dart';

/// The banner under the header while a post is read aloud.
void main() {
  late ValueNotifier<ReadingNow?> reading;
  late List<bool> stops;

  setUp(() {
    reading = ValueNotifier(null);
    stops = [];
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => StatusBannerHost(
          reading: reading,
          onStop: ({required clear}) => stops.add(clear),
          child: child!,
        ),
        home: Scaffold(
          appBar: AppBar(title: const Text('Header')),
          body: const Center(child: Text('Posts')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  const news = ReadingNow(
    chatId: -1001,
    messageId: 7,
    channelTitle: 'News',
    waiting: 2,
  );

  testWidgets('a post read aloud: under the header, with both stops', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.byType(MaterialBanner), findsNothing);

    reading.value = news;
    await tester.pumpAndSettle();
    expect(
      find.text('Reading aloud: News. 2 more posts wait.'),
      findsOneWidget,
    );
    // Below the header, not over it.
    expect(
      tester.getTopLeft(find.byType(MaterialBanner)).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(find.byType(AppBar)).dy),
    );

    await tester.tap(find.text('Stop'));
    await tester.tap(find.text('Stop and clear queue'));
    expect(stops, [false, true]);

    // The words follow the queue without the banner coming again.
    reading.value = const ReadingNow(
      chatId: -1001,
      messageId: 8,
      channelTitle: 'News',
      waiting: 0,
    );
    await tester.pump();
    expect(find.text('Reading aloud: News'), findsOneWidget);

    reading.value = null;
    await tester.pumpAndSettle();
    expect(find.byType(MaterialBanner), findsNothing);
  });

  testWidgets('the full-screen viewer has the whole screen', (tester) async {
    await pumpApp(tester);
    reading.value = news;
    await tester.pumpAndSettle();
    MediaViewerScreen.showing.value = 1;
    await tester.pumpAndSettle();
    expect(find.byType(MaterialBanner), findsNothing);
    MediaViewerScreen.showing.value = 0;
    await tester.pumpAndSettle();
    expect(find.byType(MaterialBanner), findsOneWidget);
  });

  test('the words for the queue', () {
    expect(readingLine(null), '');
    expect(
      readingLine(
        const ReadingNow(chatId: 1, messageId: 1, channelTitle: '', waiting: 1),
      ),
      'Reading aloud. 1 more post waits.',
    );
    expect(ReadingNow.decode(news.encode()), news);
    expect(ReadingNow.decode(null), isNull);
  });
}
