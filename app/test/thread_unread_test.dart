import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/post_card.dart';
import 'package:telegram_feed/feeds/thread_screen.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fixtures.dart';

/// A discussion of [count] comments with the ids 901 and up, read up to [lastRead].
class LongThread extends ChannelsGateway {
  LongThread({required this.count, this.lastRead = 0}) : super(const []);
  final int count;
  final int lastRead;
  final live = StreamController<Comment>.broadcast();

  /// Where each page of comments was asked from (0: the newest).
  final pages = <int>[];

  @override
  Future<Thread?> discussion(int chatId, int messageId) async => Thread(
    chatId: -2,
    threadId: 900,
    postChatId: -1,
    postMessageId: 5,
    replyCount: count,
    lastReadId: lastRead,
    unreadCount: lastRead == 0 ? count : 900 + count - lastRead,
  );

  @override
  Future<List<Comment>> threadHistory(
    Thread t, {
    int fromMessageId = 0,
    int limit = 30,
  }) async {
    pages.add(fromMessageId);
    return [
      for (var id = 900 + count; id > 900; id--)
        if (fromMessageId == 0 || id < fromMessageId)
          Comment(
            chatId: -2,
            messageId: id,
            threadId: 900,
            date: id,
            text: 'comment $id',
            author: 'Ann',
          ),
    ].take(limit).toList();
  }

  @override
  Stream<Comment> get comments => live.stream;
}

void main() {
  const post = Post(chatId: -1, messageId: 5, date: 1, text: 'the post');

  Future<void> open(WidgetTester tester, LongThread gw) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ThreadScreen(gateway: gw, post: post, channelTitle: 'News'),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  double top(WidgetTester tester, String text) =>
      tester.getTopLeft(find.text(text)).dy;

  testWidgets('a thread with unread comments opens at the first of them, under '
      'a divider, and is titled with their number', (tester) async {
    final gw = LongThread(count: 60, lastRead: 930);
    await open(tester, gw);

    expect(find.text('60 comments'), findsOneWidget);
    expect(find.text('Unread comments'), findsOneWidget);
    // The divider stands over the first comment that came after the read one, near the
    // top; the newest comments are far below.
    expect(
      top(tester, 'Unread comments'),
      lessThan(top(tester, 'comment 931')),
    );
    expect(top(tester, 'Unread comments'), lessThan(220));
    expect(find.text('comment 960'), findsNothing);
    // The pages down to the read comment were loaded for that: two of thirty.
    expect(gw.pages, [0, 931]);

    // What is on the screen is told to Telegram as read, a moment later.
    await tester.pump(const Duration(milliseconds: 400));
    expect(gw.commentsViewed, isNotEmpty);
    final seen = gw.commentsViewed.last
        .split(':')
        .last
        .split(',')
        .map(int.parse);
    expect(seen.first, 931);
    expect(seen.every((id) => id > 930 && id < 960), isTrue);
  });

  testWidgets('a few unread comments leave the newest one at the bottom', (
    tester,
  ) async {
    final gw = LongThread(count: 60, lastRead: 958);
    await open(tester, gw);
    await tester.pump();
    expect(find.text('Unread comments'), findsOneWidget);
    expect(
      top(tester, 'Unread comments'),
      lessThan(top(tester, 'comment 959')),
    );
    expect(find.text('comment 960'), findsOneWidget);
    expect(tester.getBottomLeft(find.text('comment 960')).dy, greaterThan(400));
  });

  testWidgets('a thread that was never opened, or has nothing new, opens at '
      'its newest comment without a divider', (tester) async {
    final never = LongThread(count: 60);
    await open(tester, never);
    expect(find.text('Unread comments'), findsNothing);
    expect(find.text('comment 960'), findsOneWidget);
    expect(never.pages, [0]);

    await tester.pumpWidget(const SizedBox());
    final read = LongThread(count: 60, lastRead: 960);
    await open(tester, read);
    expect(find.text('Unread comments'), findsNothing);
    expect(find.text('comment 960'), findsOneWidget);
  });

  testWidgets('older comments load as the reader scrolls up to them, down to '
      'the post', (tester) async {
    final gw = LongThread(count: 60, lastRead: 960);
    await open(tester, gw);
    expect(gw.pages, [0]);
    expect(find.byType(PostCard), findsNothing);

    // Up, towards the older comments: in a turned list that is a drag downwards.
    for (var i = 0; i < 12 && gw.pages.length < 3; i++) {
      await tester.drag(
        find.byType(ThreadScreen),
        const Offset(0, 500),
        warnIfMissed: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
    }
    // The second page, and the empty one that says there is no more.
    expect(gw.pages.take(2), [0, 931]);
    for (var i = 0; i < 12 && find.byType(PostCard).evaluate().isEmpty; i++) {
      await tester.drag(
        find.byType(ThreadScreen),
        const Offset(0, 500),
        warnIfMissed: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('comment 901'), findsOneWidget);
    expect(find.byType(PostCard), findsOneWidget);
    expect(find.text('Discussion started'), findsOneWidget);
  });

  testWidgets('a comment that arrives counts into the title', (tester) async {
    final gw = LongThread(count: 2, lastRead: 902);
    await open(tester, gw);
    expect(find.text('2 comments'), findsOneWidget);
    gw.live.add(
      const Comment(
        chatId: -2,
        messageId: 903,
        threadId: 900,
        date: 903,
        text: 'a new one',
        author: 'Cy',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('3 comments'), findsOneWidget);
    expect(find.text('a new one'), findsOneWidget);
  });
}
