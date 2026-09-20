import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/post_card.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'media_view_test.dart' show DownloadGateway;

void main() {
  late DownloadGateway gw;
  setUp(() => gw = DownloadGateway('/nonexistent.png'));

  Widget card(ForwardOrigin? origin, {VoidCallback? onOpenForward}) =>
      MaterialApp(
        home: Scaffold(
          body: PostCard(
            item: TimelineItem(
              Post(
                chatId: -1001,
                messageId: 5,
                date: 1700000000,
                text: 'the post itself',
                forwardedFrom: origin,
              ),
            ),
            channelTitle: 'Alpha News',
            gateway: gw,
            onOpenForward: onOpenForward,
          ),
        ),
      );

  testWidgets('a forwarded post says where it came from, above its text', (
    tester,
  ) async {
    await tester.pumpWidget(
      card(const ForwardOrigin(title: 'Origin Channel', chatId: -1002)),
    );
    final line = find.byType(ForwardedFrom);
    expect(line, findsOneWidget);
    expect(
      find.descendant(
        of: line,
        matching: find.textContaining('Origin Channel'),
      ),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(line).dy,
      lessThan(tester.getTopLeft(find.text('the post itself')).dy),
    );
  });

  testWidgets('the original author signature follows the name', (tester) async {
    await tester.pumpWidget(
      card(const ForwardOrigin(title: 'Origin Channel', signature: 'Ed')),
    );
    expect(find.textContaining('(Ed)'), findsOneWidget);
  });

  testWidgets('a hidden sender is named as one', (tester) async {
    await tester.pumpWidget(card(const ForwardOrigin(hidden: true)));
    expect(find.textContaining('a hidden account'), findsOneWidget);
  });

  testWidgets('a tap on the line opens the original where it can', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      card(
        const ForwardOrigin(
          title: 'Origin Channel',
          chatId: -1002,
          messageId: 8,
        ),
        onOpenForward: () => taps++,
      ),
    );
    await tester.tap(find.textContaining('Origin Channel'));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('a post of the channel itself has no such line', (tester) async {
    await tester.pumpWidget(card(null));
    expect(find.byType(ForwardedFrom), findsNothing);
  });
}
