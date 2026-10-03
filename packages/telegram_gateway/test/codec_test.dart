import 'package:telegram_gateway/telegram_gateway.dart';
import 'package:test/test.dart';

void main() {
  test('a deleted event carries its ids in a list of its own', () {
    // What a core hands on after decoding a request: a view, not a list.
    final ids = <Object?>[9, 8].cast<int>();
    final encoded = encodePostEvent(PostsDeleted(chatId: 42, messageIds: ids));
    expect(encoded['messageIds'], [9, 8]);
    expect(identical(encoded['messageIds'], ids), isFalse);
    final decoded = decodePostEvent(encoded) as PostsDeleted;
    expect(decoded.chatId, 42);
    expect(decoded.messageIds, [9, 8]);
  });

  test(
    'a comment keeps what it answers, its reactions and how it was sent',
    () {
      const c = Comment(
        chatId: -2,
        messageId: 7,
        threadId: 5,
        date: 100,
        text: 'yes',
        author: 'Ann',
        isOutgoing: true,
        edited: true,
        sendState: CommentSend.failed,
        replyTo: CommentReply(messageId: 6, author: 'Ben', text: 'is it?'),
        reactions: [Reaction(emoji: '👍', count: 2, chosen: true)],
      );
      final back = decodeComment(encodeComment(c));
      expect(back.edited, isTrue);
      expect(back.sendState, CommentSend.failed);
      expect(back.replyTo!.messageId, 6);
      expect(back.replyTo!.author, 'Ben');
      expect(back.replyTo!.text, 'is it?');
      expect(back.reactions.single.emoji, '👍');
      expect(back.reactions.single.count, 2);
      expect(back.reactions.single.chosen, isTrue);

      // A plain comment answers the post, has no reactions and was sent.
      final plain = decodeComment(
        encodeComment(
          const Comment(
            chatId: -2,
            messageId: 8,
            threadId: 5,
            date: 100,
            text: 'no',
            author: 'Cy',
          ),
        ),
      );
      expect(plain.replyTo, isNull);
      expect(plain.reactions, isEmpty);
      expect(plain.sendState, CommentSend.sent);
      expect(plain.edited, isFalse);
    },
  );

  test('a thread says whether the account may write in it', () {
    const t = Thread(
      chatId: -2,
      threadId: 5,
      postChatId: -1,
      postMessageId: 4,
      replyCount: 3,
      write: ThreadWrite.joinNeeded,
      slowModeWait: 12,
      slowModeDelay: 30,
    );
    final back = decodeThread(encodeThread(t));
    expect(back.write, ThreadWrite.joinNeeded);
    expect(back.slowModeWait, 12);
    expect(back.slowModeDelay, 30);
  });

  test(
    'a page of found comments keeps its count and where the next begins',
    () {
      final back = decodeCommentPage(
        encodeCommentPage(
          const CommentPage(
            comments: [
              Comment(
                chatId: -2,
                messageId: 7,
                threadId: 5,
                date: 100,
                text: 'yes',
                author: 'Ann',
              ),
            ],
            totalCount: 41,
            nextFromMessageId: 7,
          ),
        ),
      );
      expect(back.comments.single.text, 'yes');
      expect(back.totalCount, 41);
      expect(back.nextFromMessageId, 7);
      expect(back.isLast, isFalse);
    },
  );

  test('comments that are gone cross the core boundary', () {
    // What a core hands on after decoding a request: a view, not a list.
    final ids = <Object?>[7, 8].cast<int>();
    final encoded = encodeCommentsGone(
      CommentsGone(chatId: -2, messageIds: ids),
    );
    expect(identical(encoded['messageIds'], ids), isFalse);
    expect(encoded['messageIds'].runtimeType, <int>[].runtimeType);
    final back = decodeCommentsGone(encoded);
    expect(back.chatId, -2);
    expect(back.messageIds, [7, 8]);
  });
}
