import 'dart:async';

import 'package:app_db/app_db.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/pinned_posts.dart';
import 'package:telegram_feed/feeds/timeline_screen.dart';
import 'package:telegram_feed/l10n/l10n.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fixtures.dart';

void main() {
  late AppDatabase db;
  const channel = Channel(chatId: -1, title: 'One', lastMessageId: 3);

  Post post(int id, String text) =>
      Post(chatId: -1, messageId: id, date: id * 100, text: text);

  setUp(() => db = AppDatabase(NativeDatabase.memory()));

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

  Future<void> open(WidgetTester tester, TimelineGateway gw) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(db: db, gateway: gw, channel: channel),
      ),
    );
    await settle(tester);
    await tester.pumpAndSettle();
  }

  Finder inBar(String text) =>
      find.descendant(of: find.byType(PinnedBar), matching: find.text(text));

  testWidgets('a channel with a pinned post shows the bar, and hiding it is '
      'remembered until a newer post is pinned', (tester) async {
    final gw = TimelineGateway(
      {
        -1: [post(3, 'newest'), post(1, 'the pinned one')],
      },
      channels: const [channel],
    )..pins[-1] = [post(1, 'the pinned one')];
    await open(tester, gw);

    expect(gw.pinnedAsked, [-1]);
    expect(find.byType(PinnedBar), findsOneWidget);
    expect(inBar('Pinned post'), findsOneWidget);
    expect(inBar('the pinned one'), findsOneWidget);
    // One pinned post: nothing to list, so the button is the cross.
    expect(find.byTooltip('Pinned posts'), findsNothing);

    await tester.tap(find.byTooltip('Hide'));
    await tester.pumpAndSettle();
    expect(find.byType(PinnedBar), findsNothing);
    expect(find.textContaining('Pinned posts hidden'), findsOneWidget);
    await unmount(tester);

    // The next visit: the bar stays away.
    await open(tester, gw);
    expect(find.byType(PinnedBar), findsNothing);
    await unmount(tester);

    // A newer pinned post brings it back.
    gw.pins[-1] = [post(3, 'newest'), post(1, 'the pinned one')];
    await open(tester, gw);
    expect(find.byType(PinnedBar), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('hiding the bar can be undone', (tester) async {
    final gw = TimelineGateway(
      {
        -1: [post(3, 'newest'), post(1, 'the pinned one')],
      },
      channels: const [channel],
    )..pins[-1] = [post(1, 'the pinned one')];
    await open(tester, gw);
    await tester.tap(find.byTooltip('Hide'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.byType(PinnedBar), findsOneWidget);
    await unmount(tester);

    await open(tester, gw);
    expect(find.byType(PinnedBar), findsOneWidget);
    await unmount(tester);
  });

  group('several pinned posts', () {
    late TimelineGateway gw;

    setUp(() {
      final history = fixtureHistory(-1, to: 60);
      gw = TimelineGateway({-1: history}, channels: const [channel])
        ..readPositions[-1] = 60
        ..pins[-1] = [
          for (final p in history)
            if (const [58, 30, 5].contains(p.messageId)) p,
        ];
    });

    testWidgets('a tap goes to the post on show and the bar moves on to the '
        'next older one, and from the oldest back to the newest', (
      tester,
    ) async {
      await open(tester, gw);
      // At the newest posts the newest pinned post is the one on show.
      expect(inBar('Pinned post'), findsOneWidget);
      expect(inBar('post-58'), findsOneWidget);

      await tester.tap(find.byType(PinnedBar));
      await settleJump(tester);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(PostCard),
          matching: find.text('post-58'),
        ),
        findsOneWidget,
      );
      // Numbered from the oldest: of three, the middle one is #2.
      expect(inBar('Pinned post #2'), findsOneWidget);
      expect(inBar('post-30'), findsOneWidget);

      await tester.tap(find.byType(PinnedBar));
      await settle(tester);
      await settleJump(tester);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(PostCard),
          matching: find.text('post-30'),
        ),
        findsOneWidget,
      );
      expect(inBar('Pinned post #1'), findsOneWidget);
      expect(inBar('post-5'), findsOneWidget);

      await tester.tap(find.byType(PinnedBar));
      await settle(tester);
      await settleJump(tester);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(PostCard),
          matching: find.text('post-5'),
        ),
        findsOneWidget,
      );
      expect(inBar('Pinned post'), findsOneWidget);
      expect(inBar('post-58'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('the bar follows the scroll: it shows the pinned post the list '
        'stands at', (tester) async {
      await open(tester, gw);
      final state = tester.state<TimelineViewState>(find.byType(TimelineView));
      // post-40 is between the pinned posts 58 and 30.
      unawaited(state.jumpToPost(chatId: -1, messageId: 40, date: 4000));
      await settle(tester);
      await settleJump(tester);
      await tester.pumpAndSettle();
      expect(inBar('post-30'), findsOneWidget);
      expect(inBar('Pinned post #2'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('the button opens the list of pinned posts; a post there is '
        'jumped to', (tester) async {
      await open(tester, gw);
      expect(find.byTooltip('Hide'), findsNothing);
      await tester.tap(find.byTooltip('Pinned posts'));
      await tester.pumpAndSettle();
      expect(find.text('3 pinned posts'), findsOneWidget);
      final list = find.byType(PinnedPostsScreen);
      for (final text in const ['post-58', 'post-30', 'post-5']) {
        expect(
          find.descendant(of: list, matching: find.text(text)),
          findsOneWidget,
        );
      }
      // Oldest on top, like the timeline.
      expect(
        tester
            .getTopLeft(
              find.descendant(of: list, matching: find.text('post-5')),
            )
            .dy,
        lessThan(
          tester
              .getTopLeft(
                find.descendant(of: list, matching: find.text('post-58')),
              )
              .dy,
        ),
      );

      await tester.tap(
        find.descendant(of: list, matching: find.text('post-30')),
      );
      await settle(tester);
      await settleJump(tester);
      await tester.pumpAndSettle();
      expect(find.byType(PinnedPostsScreen), findsNothing);
      expect(
        find.descendant(
          of: find.byType(PostCard),
          matching: find.text('post-30'),
        ),
        findsOneWidget,
      );
      await unmount(tester);
    });

    testWidgets('a channel that opens at unread posts shows their divider '
        'below the bar', (tester) async {
      gw.readPositions[-1] = 30;
      await open(tester, gw);
      expect(find.byType(PinnedBar), findsOneWidget);
      final divider = tester.getRect(find.text('Unread posts'));
      final bar = tester.getRect(find.byType(PinnedBar));
      expect(divider.top, greaterThanOrEqualTo(bar.bottom));
      expect(divider.top, lessThan(bar.bottom + 60));
      await unmount(tester);
    });

    testWidgets('the list hides the bar', (tester) async {
      await open(tester, gw);
      await tester.tap(find.byTooltip('Pinned posts'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hide pinned posts'));
      await tester.pumpAndSettle();
      expect(find.byType(PinnedPostsScreen), findsNothing);
      expect(find.byType(PinnedBar), findsNothing);
      expect(find.textContaining('Pinned posts hidden'), findsOneWidget);
      await unmount(tester);

      await open(tester, gw);
      expect(find.byType(PinnedBar), findsNothing);
      await unmount(tester);
    });
  });

  test('the older of two pinned posts is the previous one', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(PinnedBar.titleOf(l10n, 0, 2), 'Pinned post');
    expect(PinnedBar.titleOf(l10n, 1, 2), 'Previous post');
    expect(PinnedBar.titleOf(l10n, 0, 1), 'Pinned post');
    expect(PinnedBar.titleOf(l10n, 3, 4), 'Pinned post #1');
    expect(PinnedBar.titleOf(l10n, 1, 4), 'Pinned post #3');
  });

  testWidgets('a channel without one shows no bar', (tester) async {
    final gw = TimelineGateway(
      {
        -1: [post(3, 'newest')],
      },
      channels: const [channel],
    );
    await open(tester, gw);
    expect(find.byType(PinnedBar), findsNothing);
    await unmount(tester);
  });

  testWidgets('a feed has no bar: it mixes channels', (tester) async {
    final gw = TimelineGateway(
      {
        -1: [post(3, 'newest')],
      },
      channels: const [channel],
    )..pins[-1] = [post(1, 'the pinned one')];
    late Feed feed;
    await tester.runAsync(() async {
      feed = await db.createFeed('Mix');
      await db.addSource(feed.id, -1, title: 'One');
    });
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(db: db, gateway: gw, feed: feed),
      ),
    );
    await settle(tester);
    await tester.pumpAndSettle();
    expect(gw.pinnedAsked, isEmpty);
    expect(find.byType(PinnedBar), findsNothing);
    await unmount(tester);
  });
}
