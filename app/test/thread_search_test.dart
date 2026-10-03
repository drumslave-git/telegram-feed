import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/thread_screen.dart';
import 'package:telegram_feed/feeds/timeline_search.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fixtures.dart';

/// A discussion of 200 comments with the ids 901 to 1100. Every fourth one is about an
/// apple, and comment 905 alone about a pear.
class LongTalk extends ChannelsGateway {
  LongTalk() : super(const []);

  /// Where each page of the search was asked from, and the comments the thread was asked
  /// to load around, as `id+newer-older`.
  final searchPages = <int>[];
  final around = <String>[];
  final replies = <String>[];

  static String wordsOf(int id) => id == 905
      ? 'comment $id pear'
      : id % 4 == 0
      ? 'comment $id apple'
      : 'comment $id';

  static final all = [
    for (var id = 1100; id > 900; id--)
      Comment(
        chatId: -2,
        messageId: id,
        threadId: 900,
        date: id,
        text: wordsOf(id),
        author: 'Ann',
      ),
  ];

  @override
  Future<Thread?> discussion(int chatId, int messageId) async => const Thread(
    chatId: -2,
    threadId: 900,
    postChatId: -1,
    postMessageId: 5,
    replyCount: 200,
    lastReadId: 1100,
  );

  @override
  Future<List<Comment>> threadHistory(
    Thread t, {
    int fromMessageId = 0,
    int limit = 30,
  }) async => [
    for (final c in all)
      if (fromMessageId == 0 || c.messageId < fromMessageId) c,
  ].take(limit).toList();

  @override
  Future<List<Comment>> threadAround(
    Thread thread,
    int messageId, {
    int newer = 15,
    int older = 15,
  }) {
    around.add('$messageId+$newer-$older');
    return super.threadAround(thread, messageId, newer: newer, older: older);
  }

  @override
  Future<CommentPage> searchThread(
    Thread t, {
    required String query,
    int fromMessageId = 0,
    int limit = 30,
  }) async {
    searchPages.add(fromMessageId);
    final found = [
      for (final c in all)
        if (c.text.contains(query)) c,
    ];
    final page = [
      for (final c in found)
        if (fromMessageId == 0 || c.messageId < fromMessageId) c,
    ].take(limit).toList();
    return CommentPage(
      comments: page,
      totalCount: found.length,
      nextFromMessageId: page.isEmpty || page.last == found.last
          ? 0
          : page.last.messageId,
    );
  }

  @override
  Future<void> reply(Thread t, String text, {int replyToId = 0}) async =>
      replies.add(text);
}

void main() {
  const post = Post(chatId: -1, messageId: 5, date: 1, text: 'the post');

  Future<LongTalk> open(WidgetTester tester) async {
    final gw = LongTalk();
    await tester.pumpWidget(
      MaterialApp(
        home: ThreadScreen(gateway: gw, post: post, channelTitle: 'News'),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    return gw;
  }

  Finder field() => find.descendant(
    of: find.byType(AppBar),
    matching: find.byType(TextField),
  );

  /// A step of the thread towards a comment: the loading, the rebuild and the jump.
  Future<void> land(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> search(WidgetTester tester, String words) async {
    await tester.tap(find.byTooltip('Search comments'));
    await tester.pumpAndSettle();
    await tester.enterText(field(), words);
    // The words are sent with the keyboard's search key; the thread then goes to the
    // newest comment that has them.
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await land(tester);
  }

  testWidgets('typing searches nothing; sent words take the thread to the '
      'newest match, with the arrows and the counter under it', (tester) async {
    final gw = await open(tester);
    await tester.tap(find.byTooltip('Search comments'));
    await tester.pumpAndSettle();
    // The field for a comment makes way for the search.
    expect(find.byTooltip('Send'), findsNothing);
    await tester.enterText(field(), 'apple');
    await tester.pump(const Duration(milliseconds: 400));
    expect(gw.searchPages, isEmpty);
    expect(find.byType(SearchStepper), findsNothing);

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await land(tester);
    expect(gw.searchPages, [0]);
    expect(find.text('1 of 50'), findsOneWidget);
    // The found word is marked in the comment, and in no other.
    final found = tester.widget<Text>(find.text('comment 1100 apple'));
    final marked = (found.textSpan! as TextSpan).children!
        .whereType<TextSpan>()
        .where((span) => span.style?.backgroundColor != null);
    expect(marked.map((span) => span.text), ['apple']);
    expect(tester.widget<Text>(find.text('comment 1099')).textSpan, isNull);

    // The older match, and back to the newer one.
    await tester.tap(find.byTooltip('Older match'));
    await land(tester);
    expect(find.text('2 of 50'), findsOneWidget);
    expect(find.text('comment 1096 apple'), findsOneWidget);
    await tester.tap(find.byTooltip('Newer match'));
    await land(tester);
    expect(find.text('1 of 50'), findsOneWidget);
  });

  testWidgets('Show as list lists what was found; a tap opens the thread at '
      'that comment, and Back leaves the list before the search', (
    tester,
  ) async {
    await open(tester);
    await search(tester, 'apple');
    await tester.tap(find.text('Show as list'));
    await tester.pump();
    expect(find.text('50 comments found'), findsOneWidget);
    expect(find.text('Show as chat'), findsOneWidget);
    // The thread under the list is not shown.
    expect(find.text('comment 1099'), findsNothing);

    // The row is the target, not the words in it.
    await tester.tap(find.text('comment 1092 apple'), warnIfMissed: false);
    await land(tester);
    expect(find.text('50 comments found'), findsNothing);
    expect(find.text('comment 1092 apple'), findsOneWidget);
    expect(find.text('comment 1093'), findsOneWidget);
    expect(find.text('3 of 50'), findsOneWidget);

    // Back: out of the list first.
    await tester.tap(find.text('Show as list'));
    await tester.pump();
    expect(find.text('50 comments found'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pump();
    expect(find.text('50 comments found'), findsNothing);
    expect(find.text('3 of 50'), findsOneWidget);
    // Then out of the search: the field for a comment is there again.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(SearchStepper), findsNothing);
    expect(find.byTooltip('Send'), findsOneWidget);
  });

  testWidgets('words nobody wrote find nothing, and the bar says so', (
    tester,
  ) async {
    await open(tester);
    await search(tester, 'quince');
    expect(find.text('No matches'), findsOneWidget);
    expect(find.text('Show as list'), findsNothing);
  });

  testWidgets('the arrows page through the results beyond the first page', (
    tester,
  ) async {
    final gw = await open(tester);
    await search(tester, 'apple');
    expect(find.text('1 of 50'), findsOneWidget);
    // The newest match has no newer one.
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.keyboard_arrow_down),
          )
          .onPressed,
      isNull,
    );

    for (var i = 0; i < 30; i++) {
      await tester.tap(find.byTooltip('Older match'));
      await land(tester);
    }
    // The 31st match is on the second page, which was fetched for it.
    expect(find.text('31 of 50'), findsOneWidget);
    expect(find.text('comment 980 apple'), findsOneWidget);
    expect(gw.searchPages, [0, 984]);

    for (var i = 0; i < 19; i++) {
      await tester.tap(find.byTooltip('Older match'));
      await land(tester);
    }
    expect(find.text('50 of 50'), findsOneWidget);
    expect(find.text('comment 904 apple'), findsOneWidget);
    // The oldest match has no older one.
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.keyboard_arrow_up),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('the list of results loads its next page at its end', (
    tester,
  ) async {
    final gw = await open(tester);
    await search(tester, 'apple');
    await tester.tap(find.text('Show as list'));
    await tester.pump();
    expect(gw.searchPages, [0]);
    for (var i = 0; i < 12 && gw.searchPages.length < 2; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(gw.searchPages, [0, 984]);
    for (var i = 0; i < 12; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }
    // The oldest match is in the list now, and no third page was asked for.
    expect(find.text('comment 904 apple'), findsOneWidget);
    expect(gw.searchPages, [0, 984]);
  });

  testWidgets('a comment far from what is loaded is landed on, and the thread '
      'pages on from there in both directions', (tester) async {
    final gw = await open(tester);
    // The thread holds its newest thirty comments.
    expect(find.text('comment 1099'), findsOneWidget);
    await search(tester, 'pear');
    // The comments around it were fetched, not the 165 in between.
    expect(gw.around.first, '905+15-15');
    expect(find.text('comment 905 pear'), findsOneWidget);
    expect(find.text('1 of 1'), findsOneWidget);
    expect(find.text('comment 906'), findsOneWidget);
    expect(find.text('comment 1099'), findsNothing);

    // Down, towards the newer comments: the next ones join at the lower end.
    final list = find.byType(ThreadScreen);
    for (var i = 0; i < 20 && gw.around.length < 2; i++) {
      await tester.drag(list, const Offset(0, -400), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(gw.around[1], '920+30-0');
    await tester.pump();
    for (var i = 0; i < 6 && find.text('comment 925').evaluate().isEmpty; i++) {
      await tester.drag(list, const Offset(0, -400), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('comment 925'), findsOneWidget);

    // Up, towards the older ones: down to the post, as always.
    for (var i = 0; i < 30 && find.text('the post').evaluate().isEmpty; i++) {
      await tester.drag(list, const Offset(0, 500), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('comment 901'), findsOneWidget);
    expect(find.text('the post'), findsOneWidget);
  });

  testWidgets('a comment sent from the middle of the discussion takes the '
      'reader to its end', (tester) async {
    final gw = await open(tester);
    await search(tester, 'pear');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('comment 905 pear'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'me too');
    await tester.tap(find.byTooltip('Send'));
    await land(tester);
    expect(gw.replies, ['me too']);
    expect(find.text('comment 1100 apple'), findsOneWidget);
    expect(find.text('comment 905 pear'), findsNothing);
  });
}
