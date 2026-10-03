import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/post_card.dart';
import 'package:telegram_feed/feeds/thread_screen.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fixtures.dart';

/// A discussion with Ann's comment, Ben's answer to it and one of the reader's own, which
/// records what the screen asks of it.
class TalkGateway extends ChannelsGateway {
  TalkGateway({
    this.write = ThreadWrite.allowed,
    this.slowModeWait = 0,
    this.slowModeDelay = 0,
    this.ownState = CommentSend.sent,
  }) : super(const []);
  final ThreadWrite write;
  final int slowModeWait;
  final int slowModeDelay;
  final CommentSend ownState;

  final live = StreamController<Comment>.broadcast();
  final gone = StreamController<CommentsGone>.broadcast();
  final calls = <String>[];

  static final _now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  @override
  Future<Thread?> discussion(int chatId, int messageId) async => Thread(
    chatId: -2,
    threadId: 900,
    postChatId: -1,
    postMessageId: 5,
    replyCount: 3,
    lastReadId: 903,
    write: write,
    slowModeWait: slowModeWait,
    slowModeDelay: slowModeDelay,
  );

  @override
  Future<List<Comment>> threadHistory(
    Thread t, {
    int fromMessageId = 0,
    int limit = 30,
  }) async => fromMessageId != 0
      ? const []
      : [
          Comment(
            chatId: -2,
            messageId: 903,
            threadId: 900,
            date: _now - 60,
            text: 'my own words',
            author: 'Me',
            isOutgoing: true,
            sendState: ownState,
          ),
          Comment(
            chatId: -2,
            messageId: 902,
            threadId: 900,
            date: _now - 120,
            text: 'it is, since May',
            author: 'Ben',
            authorId: 8,
            replyTo: const CommentReply(
              messageId: 901,
              author: 'Ann',
              text: 'is the stall back?',
            ),
            reactions: const [
              Reaction(emoji: '👍', count: 2),
              Reaction(emoji: '🔥', count: 1, chosen: true),
            ],
          ),
          Comment(
            chatId: -2,
            messageId: 901,
            threadId: 900,
            date: _now - 180,
            text: 'is the stall back?',
            author: 'Ann',
            authorId: 7,
          ),
        ];

  @override
  Stream<Comment> get comments => live.stream;
  @override
  Stream<CommentsGone> get commentsGone => gone.stream;

  @override
  Future<void> reply(Thread t, String text, {int replyToId = 0}) async =>
      calls.add('reply $text >$replyToId');
  @override
  Future<void> editComment(Thread t, int messageId, String text) async =>
      calls.add('edit $messageId $text');
  @override
  Future<void> deleteComments(Thread t, List<int> messageIds) async =>
      calls.add('delete ${messageIds.join(',')}');
  @override
  Future<void> retryComment(Thread t, int messageId) async =>
      calls.add('retry $messageId');
  @override
  Future<void> react(
    int chatId,
    int messageId,
    String emoji, {
    bool remove = false,
  }) async => calls.add('react $chatId/$messageId ${remove ? '-' : '+'}$emoji');
}

void main() {
  const post = Post(chatId: -1, messageId: 5, date: 1, text: 'the post');

  Future<void> open(WidgetTester tester, TalkGateway gw) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ThreadScreen(gateway: gw, post: post, channelTitle: 'News'),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// A tap on a comment's words opens its menu.
  Future<void> menu(WidgetTester tester, String words) async {
    await tester.tap(find.text(words));
    await tester.pumpAndSettle();
  }

  testWidgets('a comment shows the one it answers and its reactions; a pill '
      'sets and takes back a reaction', (tester) async {
    recordHaptics(tester);
    final gw = TalkGateway();
    await open(tester, gw);

    // Ben's answer quotes Ann: her name and her words, twice on the screen now.
    expect(find.text('Ann'), findsNWidgets(2));
    expect(find.text('is the stall back?'), findsNWidgets(2));
    expect(find.byType(ReactionPill), findsNWidgets(2));
    expect(find.text('👍 2'), findsOneWidget);

    await tester.tap(find.text('👍 2'));
    await tester.pump();
    expect(gw.calls, ['react -2/902 +👍']);
    expect(find.text('👍 3'), findsOneWidget);

    // The own one is taken back, and its pill goes with the last count.
    await tester.tap(find.text('🔥 1'));
    await tester.pump();
    expect(gw.calls.last, 'react -2/902 -🔥');
    expect(find.text('🔥 1'), findsNothing);
  });

  testWidgets('Reply puts the comment over the field and sends the answer to '
      'it', (tester) async {
    final gw = TalkGateway();
    await open(tester, gw);
    await menu(tester, 'it is, since May');
    // Someone else's comment: nothing to edit or delete.
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Delete'), findsNothing);
    expect(find.text('Copy'), findsOneWidget);

    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();
    expect(find.text('Reply to Ben'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'good news');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(gw.calls, ['reply good news >902']);
    expect(find.text('Reply to Ben'), findsNothing);

    // The cross lets go of a reply without sending anything.
    await menu(tester, 'it is, since May');
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Reply to Ben'), findsNothing);
    await tester.enterText(find.byType(TextField), 'to the post');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(gw.calls.last, 'reply to the post >0');
  });

  testWidgets('Copy puts the words on the clipboard', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final gw = TalkGateway();
    await open(tester, gw);
    await menu(tester, 'it is, since May');
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(copied, 'it is, since May');
    expect(find.text('Text copied'), findsOneWidget);
  });

  testWidgets('an own comment is edited in the field and deleted after a '
      'question', (tester) async {
    final gw = TalkGateway();
    await open(tester, gw);
    await menu(tester, 'my own words');
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Message'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'my own words',
    );

    await tester.enterText(find.byType(TextField), 'my better words');
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();
    expect(gw.calls, ['edit 903 my better words']);
    expect(find.text('Edit Message'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );

    // Telegram says what the comment says now: the same bubble, not one more.
    gw.live.add(
      Comment(
        chatId: -2,
        messageId: 903,
        threadId: 900,
        date: TalkGateway._now - 60,
        text: 'my better words',
        author: 'Me',
        isOutgoing: true,
        edited: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('my own words'), findsNothing);
    expect(find.text('my better words'), findsOneWidget);
    expect(find.textContaining('edited'), findsOneWidget);
    expect(find.text('3 comments'), findsOneWidget);

    await menu(tester, 'my better words');
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete message'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(gw.calls.length, 1);

    await menu(tester, 'my better words');
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(gw.calls.last, 'delete 903');

    // It leaves the list when Telegram says it is gone, and the title counts one less.
    gw.gone.add(const CommentsGone(chatId: -2, messageIds: [903]));
    await tester.pumpAndSettle();
    expect(find.text('my better words'), findsNothing);
    expect(find.text('2 comments'), findsOneWidget);
  });

  testWidgets('a comment that was not sent says so and offers Retry and '
      'Delete', (tester) async {
    final gw = TalkGateway(ownState: CommentSend.failed);
    await open(tester, gw);
    expect(find.byIcon(Icons.error), findsOneWidget);

    await menu(tester, 'my own words');
    expect(find.text('Reply'), findsNothing);
    expect(find.text('Edit'), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(gw.calls, ['retry 903']);

    // It goes out now: a clock while it is on its way, nothing once it is there.
    gw.live.add(
      Comment(
        chatId: -2,
        messageId: 903,
        threadId: 900,
        date: TalkGateway._now,
        text: 'my own words',
        author: 'Me',
        isOutgoing: true,
        sendState: CommentSend.sending,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.error), findsNothing);
    expect(find.byIcon(Icons.schedule), findsOneWidget);
    // Telegram gives it its own id: the temporary one goes, the sent one comes.
    gw.gone.add(const CommentsGone(chatId: -2, messageIds: [903]));
    gw.live.add(
      Comment(
        chatId: -2,
        messageId: 910,
        threadId: 900,
        date: TalkGateway._now,
        text: 'my own words',
        author: 'Me',
        isOutgoing: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('my own words'), findsOneWidget);
    expect(find.byIcon(Icons.schedule), findsNothing);
    expect(find.text('3 comments'), findsOneWidget);
  });

  testWidgets('a comment that was not sent is dropped without a question', (
    tester,
  ) async {
    final gw = TalkGateway(ownState: CommentSend.failed);
    await open(tester, gw);
    await menu(tester, 'my own words');
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete message'), findsNothing);
    expect(gw.calls, ['delete 903']);
  });

  testWidgets('a discussion only members write in says so in place of the '
      'field, and offers no Reply', (tester) async {
    final gw = TalkGateway(write: ThreadWrite.joinNeeded);
    await open(tester, gw);
    expect(find.byType(TextField), findsNothing);
    expect(
      find.textContaining('Only members of the discussion group'),
      findsOneWidget,
    );
    await menu(tester, 'it is, since May');
    expect(find.text('Reply'), findsNothing);
    expect(find.text('Copy'), findsOneWidget);
  });

  testWidgets('a discussion the account is restricted in says so', (
    tester,
  ) async {
    final gw = TalkGateway(write: ThreadWrite.restricted);
    await open(tester, gw);
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('have restricted your ability'), findsOneWidget);
  });

  testWidgets('slow mode counts down in place of the field, and starts again '
      'after a comment', (tester) async {
    final gw = TalkGateway(slowModeWait: 3, slowModeDelay: 65);
    await open(tester, gw);
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('next message in 0:03'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('next message in 0:02'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'one more');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.pump();
    expect(gw.calls, ['reply one more >0']);
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('next message in 1:05'), findsOneWidget);

    // Leaving stops the count.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
