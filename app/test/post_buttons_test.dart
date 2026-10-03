import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/post_card.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fixtures.dart';

void main() {
  const post = Post(
    chatId: -1,
    messageId: 2,
    date: 300,
    text: 'the new issue',
    buttons: [
      [UrlButton(text: 'Read the issue', url: 'https://example.org/issue')],
      [
        UrlButton(text: 'Subscribe', url: 'https://example.org/subscribe'),
        UrlButton(text: 'Our channel', url: 'https://t.me/ourchannel'),
      ],
    ],
  );

  Future<List<String>> pump(WidgetTester tester, Post post) async {
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PostCard(
              item: TimelineItem(post),
              channelTitle: 'One',
              gateway: TimelineGateway({}),
              onOpenLink: opened.add,
            ),
          ),
        ),
      ),
    );
    return opened;
  }

  testWidgets('the link buttons stand under the bubble, row by row', (
    tester,
  ) async {
    await pump(tester, post);
    expect(find.byType(PostButtons), findsOneWidget);
    final words = tester.getRect(find.text('the new issue'));
    final read = tester.getRect(find.text('Read the issue'));
    final subscribe = tester.getRect(find.text('Subscribe'));
    final channel = tester.getRect(find.text('Our channel'));
    expect(read.top, greaterThan(words.bottom));
    expect(subscribe.top, greaterThan(read.bottom));
    // The second row holds two buttons side by side.
    expect(channel.center.dy, closeTo(subscribe.center.dy, 0.5));
    expect(channel.left, greaterThan(subscribe.right));
  });

  testWidgets('a button asks before it opens a link, and opens a link into '
      'Telegram at once', (tester) async {
    final opened = await pump(tester, post);
    await tester.tap(find.text('Read the issue'));
    await tester.pumpAndSettle();
    expect(
      find.text('Do you want to open https://example.org/issue?'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(opened, isEmpty);

    await tester.tap(find.text('Read the issue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(opened, ['https://example.org/issue']);

    await tester.tap(find.text('Our channel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(opened.last, 'https://t.me/ourchannel');
  });

  testWidgets('a post without buttons has none', (tester) async {
    await pump(
      tester,
      const Post(chatId: -1, messageId: 3, date: 300, text: 'plain'),
    );
    expect(find.byType(PostButtons), findsNothing);
  });
}
