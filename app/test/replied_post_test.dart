import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/post_card.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'media_view_test.dart' show DownloadGateway;

void main() {
  late DownloadGateway gw;
  setUp(() => gw = DownloadGateway('/nonexistent.png'));

  Widget card(ReplyTarget? reply, {VoidCallback? onOpenReply}) => MaterialApp(
    home: Scaffold(
      body: PostCard(
        item: TimelineItem(
          Post(
            chatId: -1001,
            messageId: 5,
            date: 1700000000,
            text: 'the answer',
            replyTo: reply,
          ),
        ),
        channelTitle: 'Alpha News',
        gateway: gw,
        onOpenReply: onOpenReply,
      ),
    ),
  );

  testWidgets('the block shows whose post it answers, above the text', (
    tester,
  ) async {
    await tester.pumpWidget(
      card(
        const ReplyTarget(
          chatId: -1002,
          messageId: 20,
          title: 'Beta Daily',
          text: 'what they said',
        ),
      ),
    );
    final block = find.byType(RepliedPost);
    expect(block, findsOneWidget);
    expect(find.text('Beta Daily'), findsOneWidget);
    expect(find.text('what they said'), findsOneWidget);
    expect(
      tester.getTopLeft(block).dy,
      lessThan(tester.getTopLeft(find.text('the answer')).dy),
    );
  });

  testWidgets('a reply inside the channel is named after the channel', (
    tester,
  ) async {
    await tester.pumpWidget(
      card(
        const ReplyTarget(chatId: -1001, messageId: 20, text: 'the older post'),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(RepliedPost),
        matching: find.text('Alpha News'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a post with nothing to say is still named', (tester) async {
    await tester.pumpWidget(
      card(const ReplyTarget(chatId: -1001, messageId: 20)),
    );
    expect(find.text('Post'), findsOneWidget);
  });

  testWidgets('a tap on the block jumps to the post it answers', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      card(
        const ReplyTarget(chatId: -1001, messageId: 20, text: 'older'),
        onOpenReply: () => taps++,
      ),
    );
    await tester.tap(find.text('older'));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('a post that answers nothing has no block', (tester) async {
    await tester.pumpWidget(card(null));
    expect(find.byType(RepliedPost), findsNothing);
  });
}
