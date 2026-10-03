import 'package:app_db/app_db.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/post_card.dart';
import 'package:telegram_feed/feeds/timeline_screen.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fixtures.dart';

void main() {
  late AppDatabase db;
  late TimelineGateway gw;
  late Feed feed;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    gw = TimelineGateway({
      -1: [
        const Post(
          chatId: -1,
          messageId: 3,
          date: 300,
          text: 'react to me',
          reactions: [Reaction(emoji: 'X', count: 2)],
        ),
      ],
    });
  });

  Future<void> settle(WidgetTester tester) => tester.runAsync(() async {
    for (var i = 0; i < 3; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await tester.pump();
    }
  });

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// Two taps close enough together for the double tap recognizer.
  Future<void> doubleTap(WidgetTester tester, Finder target) async {
    await tester.tap(target);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    await tester.runAsync(() async {
      feed = await db.createFeed('Quick');
      await db.addSource(feed.id, -1, title: 'One');
    });
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(db: db, gateway: gw, feed: feed),
      ),
    );
    await settle(tester);
    await tester.pumpAndSettle();
  }

  testWidgets('an album shows and takes the reactions of its first message, '
      'and its comments', (tester) async {
    gw.histories[-1] = [
      // Newest first. The caption, the reactions and the discussion sit on the first
      // message of the album, as Telegram keeps them.
      const Post(chatId: -1, messageId: 12, date: 300, text: '', albumId: 7),
      const Post(chatId: -1, messageId: 11, date: 300, text: '', albumId: 7),
      const Post(
        chatId: -1,
        messageId: 10,
        date: 300,
        text: 'three views',
        albumId: 7,
        reactions: [Reaction(emoji: 'X', count: 2)],
        canComment: true,
        replyCount: 4,
      ),
    ];
    await open(tester);
    expect(find.byType(PostCard), findsOneWidget);
    expect(find.text('X 2'), findsOneWidget);
    expect(find.text('4 comments'), findsOneWidget);

    await tester.tap(find.text('X 2'));
    await settle(tester);
    expect(gw.reactions, ['-1/10 +X']);
    await unmount(tester);
  });

  testWidgets('a double tap sends the thumbs up, and takes it back', (
    tester,
  ) async {
    final felt = recordHaptics(tester);
    await open(tester);
    final post = find.text('react to me');
    await doubleTap(tester, post);
    expect(gw.reactions, ['-1/3 +$defaultQuickReaction']);
    // A reaction is felt, as a key of the keyboard is.
    expect(felt, ['mediumImpact']);

    // Telegram reports it as chosen; the next double tap removes it.
    gw.histories[-1] = [
      Post(
        chatId: -1,
        messageId: 3,
        date: 300,
        text: 'react to me',
        reactions: [
          Reaction(emoji: defaultQuickReaction, count: 1, chosen: true),
        ],
      ),
    ];
    gw.posts.add(PostEdited(gw.histories[-1]!.single));
    await settle(tester);
    await tester.pumpAndSettle();
    await doubleTap(tester, post);
    expect(gw.reactions.last, '-1/3 -$defaultQuickReaction');
    await unmount(tester);
  });

  testWidgets('the reaction shows at once, before Telegram answers', (
    tester,
  ) async {
    await open(tester);
    // Only the post's own "X 2" so far.
    expect(find.textContaining(defaultQuickReaction), findsNothing);
    await doubleTap(tester, find.text('react to me'));
    await tester.pump();
    // No update from Telegram came, yet the reader's reaction is there.
    expect(find.textContaining(defaultQuickReaction), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('reacting from the menu leaves the quick reaction as it was '
      'chosen', (tester) async {
    await open(tester);
    await tester.tap(find.text('react to me'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    // The scripted channel allows a thumbs up and a flame; the flame is the other one.
    await tester.tap(
      find
          .byWidgetPredicate(
            (w) =>
                w is Text &&
                w.data != null &&
                w.data != defaultQuickReaction &&
                w.data!.isNotEmpty &&
                w.data!.length <= 2,
          )
          .last,
    );
    await tester.pumpAndSettle();
    expect(gw.reactions.length, 1);
    expect(gw.reactions.single, isNot(contains(defaultQuickReaction)));
    expect(
      await tester.runAsync(() => db.setting(SettingKeys.quickReaction)),
      isNull,
    );

    // A double tap still sends the thumbs up.
    await doubleTap(tester, find.text('react to me'));
    expect(gw.reactions.last, '-1/3 +$defaultQuickReaction');
    await unmount(tester);
  });

  testWidgets('the quick reaction is the one chosen in Chat settings', (
    tester,
  ) async {
    await tester.runAsync(() => db.setSetting(SettingKeys.quickReaction, '🔥'));
    await open(tester);
    await doubleTap(tester, find.text('react to me'));
    expect(gw.reactions, ['-1/3 +🔥']);
    await unmount(tester);
  });

  testWidgets('a double tap does nothing where the channel does not allow the '
      'reaction', (tester) async {
    gw.allowedReactions = const ['🔥'];
    await open(tester);
    await doubleTap(tester, find.text('react to me'));
    await settle(tester);
    expect(gw.reactions, isEmpty);
    expect(find.textContaining(defaultQuickReaction), findsNothing);
    await unmount(tester);
  });

  testWidgets('the menu shows the first reactions and an arrow that opens '
      'them all', (tester) async {
    gw.allowedReactions = const [
      '👍', '🔥', '❤', '👏', '😁', '🤔', '🎉', '😢', //
    ];
    await open(tester);
    await tester.tap(find.text('react to me'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    // Five and the arrow: the rest waits behind it.
    expect(find.text('😁'), findsOneWidget);
    expect(find.text('🤔'), findsNothing);
    expect(find.byIcon(Icons.expand_more), findsOneWidget);

    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();
    expect(find.text('🤔'), findsOneWidget);
    expect(find.text('😢'), findsOneWidget);
    expect(find.byIcon(Icons.expand_more), findsNothing);

    await tester.tap(find.text('😢'));
    await tester.pumpAndSettle();
    expect(gw.reactions, ['-1/3 +😢']);
    await unmount(tester);
  });

  testWidgets('the pill of a reaction that was just set pops', (tester) async {
    await open(tester);
    await doubleTap(tester, find.text('react to me'));
    // doubleTap settles: the pop has run its course, and is gone a moment later.
    expect(find.textContaining(defaultQuickReaction), findsOneWidget);
    await tester.tap(find.text('X 2'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(ReactionPop), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    expect(find.byType(ReactionPop), findsNothing);
    await unmount(tester);
  });
}
