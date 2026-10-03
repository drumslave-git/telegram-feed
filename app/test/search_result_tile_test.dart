import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/timeline_search.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fixtures.dart';

void main() {
  Future<void> show(WidgetTester tester, Post post, String query) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchResultTile(
              post: post,
              channelTitle: 'One',
              channelPhoto: null,
              gateway: ChannelsGateway(const []),
              query: query,
              onTap: () {},
            ),
          ),
        ),
      );

  /// The pieces of the row's text that are marked, in order.
  List<String?> marked(WidgetTester tester) {
    final scheme = Theme.of(tester.element(find.byType(SearchResultTile)))
        .colorScheme;
    final text = tester.widget<Text>(
      find.byWidgetPredicate(
        (w) => w is Text && w.textSpan != null && w.maxLines == 2,
      ),
    );
    return [
      for (final span in (text.textSpan! as TextSpan).children!)
        if ((span as TextSpan).style?.color == scheme.primary) span.text,
    ];
  }

  testWidgets('a row marks every word of the search, whatever its case', (
    tester,
  ) async {
    final today = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await show(
      tester,
      Post(
        chatId: -1,
        messageId: 1,
        date: today,
        text: 'Heavy rain in Berlin, and more rain tomorrow',
      ),
      'RAIN berlin',
    );
    expect(marked(tester), ['rain', 'Berlin', 'rain']);
  });

  testWidgets('words that share letters are not marked twice', (tester) async {
    await show(
      tester,
      const Post(chatId: -1, messageId: 1, date: 100, text: 'the rainbow'),
      'rain rainbow',
    );
    expect(marked(tester), ['rainbow']);
  });

  testWidgets('a row from long ago shows its date in digits', (tester) async {
    await show(
      tester,
      Post(
        chatId: -1,
        messageId: 1,
        date: DateTime(2019, 1, 5, 12).millisecondsSinceEpoch ~/ 1000,
        text: 'rain',
      ),
      'rain',
    );
    expect(find.text('05.01.19'), findsOneWidget);
  });
}
