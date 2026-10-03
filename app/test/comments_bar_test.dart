import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/post_card.dart';
import 'package:telegram_feed/home/channel_list.dart' show ChannelAvatar;
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fixtures.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required int count,
    List<Commenter> commenters = const [],
    bool unread = false,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: CommentsBar(
            count: count,
            commenters: commenters,
            unread: unread,
            gateway: TimelineGateway({}),
            onTap: () {},
          ),
        ),
      ),
    ),
  );

  const people = [
    Commenter(id: 11, name: 'Mara'),
    Commenter(id: 12, name: 'Tomas'),
    Commenter(id: 13, name: 'Ines'),
    Commenter(id: 14, name: 'Oleh'),
  ];

  testWidgets('the photos of up to three commenters, the exact count and the '
      'dot of unread comments', (tester) async {
    await pump(tester, count: 1234, commenters: people, unread: true);
    expect(find.byType(ChannelAvatar), findsNWidgets(3));
    expect(find.byIcon(Icons.forum_outlined), findsNothing);
    // Not "1.2K": the number as it is.
    expect(find.text('1234 comments'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('New comments')), findsOneWidget);
    // Each photo lies over the next, the newest commenter on top and leftmost.
    final discs = tester
        .widgetList<ChannelAvatar>(find.byType(ChannelAvatar))
        .toList();
    expect(discs.last.title, 'Mara');
    final mara = tester.getRect(find.byWidget(discs.last));
    final tomas = tester.getRect(find.byWidget(discs[1]));
    expect(mara.left, lessThan(tomas.left));
    expect(tomas.left, lessThan(mara.right));
  });

  testWidgets('no commenters known: the icon; nothing unread: no dot', (
    tester,
  ) async {
    await pump(tester, count: 1);
    expect(find.byIcon(Icons.forum_outlined), findsOneWidget);
    expect(find.text('1 comment'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('New comments')), findsNothing);
  });

  testWidgets('a post without comments invites one, and shows no faces', (
    tester,
  ) async {
    await pump(tester, count: 0, commenters: people, unread: true);
    expect(find.text('Leave a comment'), findsOneWidget);
    expect(find.byType(ChannelAvatar), findsNothing);
    expect(find.bySemanticsLabel(RegExp('New comments')), findsNothing);
  });
}
