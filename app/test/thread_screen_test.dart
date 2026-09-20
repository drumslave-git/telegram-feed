import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/post_card.dart';
import 'package:telegram_feed/feeds/thread_screen.dart';
import 'package:telegram_feed/home/channel_list.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'feeds_screen_test.dart' show ChannelsGateway;

class ThreadGateway extends ChannelsGateway {
  ThreadGateway({this.hasThread = true}) : super(const []);
  final bool hasThread;
  final live = StreamController<Comment>.broadcast();
  final replies = <String>[];
  final closed = <Thread>[];
  static const thread = Thread(
    chatId: -2,
    threadId: 900,
    postChatId: -1,
    postMessageId: 5,
    replyCount: 2,
  );

  @override
  Future<Thread?> discussion(int chatId, int messageId) async =>
      hasThread ? thread : null;

  @override
  Future<List<Comment>> threadHistory(
    Thread t, {
    int fromMessageId = 0,
    int limit = 30,
  }) async {
    if (fromMessageId != 0) return const [];
    return const [
      Comment(
        chatId: -2,
        messageId: 902,
        threadId: 900,
        date: 2,
        text: 'second',
        author: 'Bob',
      ),
      Comment(
        chatId: -2,
        messageId: 901,
        threadId: 900,
        date: 1,
        text: 'first',
        author: 'Ann',
      ),
    ];
  }

  /// Words the thread was searched for.
  final searched = <String>[];

  @override
  Future<List<Comment>> searchThread(
    Thread t, {
    required String query,
    int fromMessageId = 0,
    int limit = 30,
  }) async {
    searched.add(query);
    final all = await threadHistory(t);
    return [
      for (final c in all)
        if (c.text.toLowerCase().contains(query.toLowerCase())) c,
    ];
  }

  @override
  Future<void> reply(Thread t, String text) async => replies.add(text);
  @override
  Stream<Comment> get comments => live.stream;
  @override
  Future<void> closeThread(Thread t) async => closed.add(t);
}

void main() {
  final post = Post(
    chatId: -1,
    messageId: 5,
    date: 1,
    text: 'the post',
    replyCount: 2,
  );

  testWidgets(
    'loads comments oldest first, appends live ones, sends a reply, closes',
    (tester) async {
      final gw = ThreadGateway();
      await tester.pumpWidget(
        MaterialApp(
          home: ThreadScreen(gateway: gw, post: post, channelTitle: 'News'),
        ),
      );
      await tester.pump();
      await tester.pump();
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>()
          .toList();
      expect(texts.indexOf('first'), lessThan(texts.indexOf('second')));
      expect(find.text('Ann'), findsOneWidget);
      // The post on top with the channel's avatar, and one avatar per comment author.
      expect(find.byType(PostCard), findsOneWidget);
      expect(find.text('the post'), findsOneWidget);
      expect(find.byType(CommentBubble), findsNWidgets(2));
      expect(find.byType(ChannelAvatar), findsNWidgets(3));

      gw.live.add(
        const Comment(
          chatId: -2,
          messageId: 903,
          threadId: 900,
          date: 3,
          text: 'third',
          author: 'Cy',
        ),
      );
      gw.live.add(
        const Comment(
          chatId: -2,
          messageId: 1,
          threadId: 77,
          date: 3,
          text: 'elsewhere',
          author: 'X',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('third'), findsOneWidget);
      expect(find.text('elsewhere'), findsNothing);

      // An own comment sits on the right and has no avatar.
      gw.live.add(
        const Comment(
          chatId: -2,
          messageId: 904,
          threadId: 900,
          date: 4,
          text: 'mine',
          author: 'Me',
          isOutgoing: true,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ChannelAvatar), findsNWidgets(4));
      expect(find.text('Me'), findsNothing);
      expect(
        tester.getCenter(find.text('mine')).dx,
        greaterThan(tester.getCenter(find.text('third')).dx),
      );

      await tester.enterText(find.byType(TextField), 'my reply');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();
      expect(gw.replies, ['my reply']);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '',
      );

      await tester.pumpWidget(const SizedBox());
      expect(gw.closed, [ThreadGateway.thread]);
    },
  );

  testWidgets('channel without discussion group', (tester) async {
    final gw = ThreadGateway(hasThread: false);
    await tester.pumpWidget(
      MaterialApp(
        home: ThreadScreen(gateway: gw, post: post, channelTitle: 'News'),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('no discussion group'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('the comments can be searched', (tester) async {
    final gw = ThreadGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: ThreadScreen(gateway: gw, post: post, channelTitle: 'News'),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byTooltip('Search comments'));
    await tester.pumpAndSettle();
    final searchField = find.descendant(
      of: find.byType(AppBar),
      matching: find.byType(TextField),
    );
    await tester.enterText(searchField, 'second');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(gw.searched, ['second']);
    // The words are in the field as well as in the comment that was found.
    expect(
      find.descendant(
        of: find.byType(CommentBubble),
        matching: find.text('second'),
      ),
      findsOneWidget,
    );
    expect(find.text('first'), findsNothing);

    // Nothing for these words.
    await tester.enterText(searchField, 'zzz');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.textContaining('Nothing found'), findsOneWidget);

    // Back to the thread itself.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('first'), findsOneWidget);
  });
}
