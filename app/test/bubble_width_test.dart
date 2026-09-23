import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/post_card.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fixtures.dart';

/// A bubble of words alone is as wide as its longest line. Words that cannot fit on one
/// line take the whole row, and the app skips measuring them to find that out; these
/// tests hold both halves of that, since a wrong skip would widen a short post.
void main() {
  final gw = ChannelsGateway(const []);

  Future<double> bubbleWidth(WidgetTester tester, String text) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostCard(
            item: TimelineItem(
              Post(chatId: -1001, messageId: 5, date: 1700000000, text: text),
            ),
            channelTitle: 'A',
            gateway: gw,
          ),
        ),
      ),
    );
    return tester.getSize(find.byType(Material).last).width;
  }

  testWidgets('a few words keep the bubble narrow', (tester) async {
    // 360 logical px wide screen, 8 px of padding on each side: a short post is sized
    // by measuring it, so it stays as narrow as its words and its footer need.
    expect(await bubbleWidth(tester, 'short'), lessThan(300));
  });

  testWidgets('a post that cannot fit takes the whole row', (tester) async {
    final text = 'word ' * 60;
    expect(await bubbleWidth(tester, text), 344);
  });

  test('the estimate never calls a line that fits certain to wrap', () {
    // The narrowest characters of the font, at the size the bubble draws them: a string
    // of them as long as the threshold must still be wider than the row.
    const row = 360.0;
    const fontSize = 16.0;
    final threshold = (row / (0.19 * fontSize)).ceil();
    final painter = TextPainter(
      text: TextSpan(
        text: 'i' * threshold,
        style: const TextStyle(fontSize: fontSize),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    expect(painter.maxIntrinsicWidth, greaterThan(row));
  });
}
