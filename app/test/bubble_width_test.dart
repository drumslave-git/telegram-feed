import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/post_card.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fixtures.dart';

/// Every bubble takes the whole row, so posts of any length line up.
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

  testWidgets('a few words take the whole row', (tester) async {
    // 360 logical px wide screen, 8 px of padding on each side.
    expect(await bubbleWidth(tester, 'short'), 344);
  });

  testWidgets('a long post takes the whole row', (tester) async {
    expect(await bubbleWidth(tester, 'word ' * 60), 344);
  });
}
