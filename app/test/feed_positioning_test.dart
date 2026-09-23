import 'dart:io';

import 'package:app_db/app_db.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/saved_position.dart';
import 'package:telegram_feed/feeds/timeline_screen.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fixtures.dart';

/// Where a feed opens, what moves the reader and what must not: the read marks of its
/// channels, the app resting in the background and coming back, the app being started
/// again, posts arriving while the reader reads, and the marks that follow (H-38).
///
/// Everything here is fixture data from `fixtures.dart`: no real account, no real channels,
/// no real posts. The database is a file, so a test can close it and open it again — that
/// is what "the app was started again" means, and it is the only way the positions
/// remembered for one session are truly gone.
/// The middle of the 800x600 test window: a drag starts there, so it always lands on the
/// list itself whatever the rows happen to be.
const _middle = Offset(400, 300);

void main() {
  late Directory dir;
  late AppDatabase db;
  late TimelineGateway gw;

  /// Two channels whose posts interleave: Alpha every two hundred seconds, Beta a hundred
  /// after each of them, so the feed reads a-1, b-1, a-2, b-2 ... and b-40 is the newest
  /// post of all.
  Map<int, List<Post>> world() => {
    -1: fixtureHistory(-1, to: 40, label: 'a', step: 200),
    -2: fixtureHistory(-2, to: 40, label: 'b', step: 200, dateOffset: 100),
  };

  AppDatabase openDatabase() =>
      AppDatabase(NativeDatabase(File('${dir.path}/app.sqlite')));

  setUp(() {
    dir = Directory.systemTemp.createTempSync('positioning');
    db = openDatabase();
    gw = TimelineGateway(
      world(),
      channels: [fixtureChannel(-1, 'Alpha'), fixtureChannel(-2, 'Beta')],
    );
  });

  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  Widget app(Feed feed) => MaterialApp(
    home: TimelineScreen(db: db, gateway: gw, feed: feed),
  );

  Future<Feed> feedOf(
    WidgetTester tester,
    String name, {
    Map<int, String> channels = const {-1: 'Alpha', -2: 'Beta'},
    Map<int, int> marks = const {},
  }) async => (await tester.runAsync(
    () => fixtureFeed(db, name, channels, marks: marks, gateway: gw),
  ))!;

  Future<void> open(WidgetTester tester, Widget widget) async {
    await tester.pumpWidget(widget);
    await settleFixtures(tester);
    await tester.pumpAndSettle();
  }

  /// The app is started again: the database object goes and a new one opens the same file,
  /// so nothing of the last session is left but what was written down.
  Future<void> restart(WidgetTester tester) async {
    await unmountFixtures(tester);
    await tester.runAsync(() async {
      await db.close();
      db = openDatabase();
    });
  }

  /// The app rests in the background and comes back. The states are stepped through in the
  /// order Android reports them, which is the only order the binding accepts.
  Future<void> pauseAndResume(
    WidgetTester tester, {
    Future<void> Function()? whileAway,
  }) async {
    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
    if (whileAway != null) await whileAway();
    for (final state in const [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
    await settleFixtures(tester);
    await tester.pumpAndSettle();
  }

  double top(WidgetTester tester, String text) =>
      tester.getTopLeft(find.text(text)).dy;
  double divider(WidgetTester tester) => top(tester, 'Unread posts');
  Finder cardOf(String text) =>
      find.ancestor(of: find.text(text), matching: find.byType(PostCard));

  /// Telegram's read position of the feed's channels: the only read state there is.
  /// Lets the read marker's debounce run out, so what the opening screen read is written
  /// before a test takes its "before" picture; otherwise a busy machine decides whether
  /// it lands before or after.
  Future<void> flushReads(WidgetTester tester) async {
    await settleFixtures(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await settleFixtures(tester);
  }

  Future<Map<int, int>> marksOf(WidgetTester tester, Feed feed) async {
    final sources = (await tester.runAsync(() => db.sourcesOf(feed.id)))!;
    return {for (final s in sources) s.chatId: gw.readPositions[s.chatId] ?? 0};
  }

  // ---- where a feed opens ----

  testWidgets('a feed nobody has read opens at its oldest post', (
    tester,
  ) async {
    final feed = await feedOf(tester, 'Fresh');
    await open(tester, app(feed));

    expect(find.text('Unread posts'), findsOneWidget);
    // Nothing is read, so the divider stands above the first post of the feed, with the
    // end of the history above it and the newest post far below.
    expect(find.text('Beginning of the feed'), findsOneWidget);
    expect(divider(tester), lessThan(top(tester, 'a-1')));
    expect(top(tester, 'a-1'), lessThan(top(tester, 'b-1')));
    expect(find.text('b-40'), findsNothing);
    await unmountFixtures(tester);
  });

  testWidgets('a part-read feed opens on the first post after the marks', (
    tester,
  ) async {
    final feed = await feedOf(tester, 'Part', marks: {-1: 20, -2: 20});
    await open(tester, app(feed));

    expect(find.text('Unread posts'), findsOneWidget);
    // a-21 is older than b-21, so it is the oldest unread post of the feed and the divider
    // sits on top of it, near the top of the window.
    expect(divider(tester), lessThan(200));
    expect(divider(tester), lessThan(top(tester, 'a-21')));
    expect(top(tester, 'a-21'), lessThan(top(tester, 'b-21')));
    expect(find.text('Beginning of the feed'), findsNothing);
    expect(find.text('b-40'), findsNothing);

    // The button counts the unread posts below the reader: forty of them, less the handful
    // that fit on the screen under the divider.
    final badge = tester.widget<Badge>(find.byType(Badge));
    final counted = int.parse(((badge.label as Text?)!).data!);
    expect(counted, lessThan(40));
    expect(counted, greaterThan(25));
    await unmountFixtures(tester);
  });

  testWidgets('a feed read to its end opens at the newest post', (
    tester,
  ) async {
    final feed = await feedOf(tester, 'Done', marks: {-1: 40, -2: 40});
    await open(tester, app(feed));

    expect(find.text('Unread posts'), findsNothing);
    // b-40 is the newest post of the two channels, and it stands at the bottom edge.
    expect(find.text('b-40'), findsOneWidget);
    expect(tester.getBottomLeft(cardOf('b-40')).dy, greaterThan(500));
    expect(find.text('a-1'), findsNothing);
    expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);
    await unmountFixtures(tester);
  });

  testWidgets('one unread channel decides where the feed opens', (
    tester,
  ) async {
    // Alpha is read through, Beta was never opened: the feed starts at Beta's first post,
    // however old it is.
    final feed = await feedOf(tester, 'Mixed', marks: {-1: 40});
    await open(tester, app(feed));

    expect(find.text('Unread posts'), findsOneWidget);
    expect(divider(tester), lessThan(top(tester, 'b-1')));
    expect(top(tester, 'a-1'), lessThan(divider(tester)));
    expect(find.text('b-40'), findsNothing);
    await unmountFixtures(tester);
  });

  testWidgets('a channel read in one feed is read in every feed', (
    tester,
  ) async {
    final first = await feedOf(
      tester,
      'First',
      channels: {-1: 'Alpha'},
      marks: {-1: 20},
    );
    final second = await feedOf(tester, 'Second', channels: {-1: 'Alpha'});

    // Read through in the first feed, with the button to the end.
    await open(tester, app(first));
    expect(find.text('Unread posts'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
    await tester.pumpAndSettle();
    await settleFixtures(tester);
    await unmountFixtures(tester);
    expect(gw.readPositions[-1], 40);

    // The other feed over the same channel has nothing new: one read position per channel,
    // Telegram's own, as in the official app.
    await open(tester, app(second));
    expect(find.text('Unread posts'), findsNothing);
    expect(find.text('a-40'), findsOneWidget);
    await unmountFixtures(tester);
  });

  testWidgets("a channel of its own opens at Telegram's own read position", (
    tester,
  ) async {
    await open(
      tester,
      MaterialApp(
        home: TimelineScreen(
          db: db,
          gateway: gw,
          channel: fixtureChannel(-1, 'Alpha', lastReadMessageId: 30),
        ),
      ),
    );

    expect(find.text('Unread posts'), findsOneWidget);
    expect(divider(tester), lessThan(top(tester, 'a-31')));
    expect(find.text('a-40'), findsNothing);
    await unmountFixtures(tester);
  });

  // ---- reading moves the marks, and the marks move the next opening ----

  testWidgets('reading a feed through, then starting the app again', (
    tester,
  ) async {
    final feed = await feedOf(tester, 'Through', marks: {-1: 20, -2: 20});
    await open(tester, app(feed));
    expect(find.text('Unread posts'), findsOneWidget);

    // The reader takes the button to the newest posts, the way the official app offers it.
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
    await tester.pumpAndSettle();
    await settleFixtures(tester);
    expect(find.text('b-40'), findsOneWidget);

    await restart(tester);
    // Both channels were seen to their newest post, so nothing is unread any more.
    final marks = await marksOf(tester, feed);
    expect(marks, {-1: 40, -2: 40});

    await open(tester, app(feed));
    expect(find.text('Unread posts'), findsNothing);
    expect(find.text('b-40'), findsOneWidget);
    await unmountFixtures(tester);
  });

  testWidgets('what the reader read in one session is where the next starts', (
    tester,
  ) async {
    final feed = await feedOf(tester, 'Session', marks: {-1: 20, -2: 20});
    await open(tester, app(feed));
    // A few screens of reading, from the divider towards the newest posts.
    for (var i = 0; i < 3; i++) {
      // The drag starts on a bubble, whose taps hold the touch for the slop (20 px)
      // before the list takes it: each drag moves the list 400 px.
      await tester.dragFrom(_middle, const Offset(0, -420));
      await tester.pumpAndSettle();
    }
    await settleFixtures(tester);
    await restart(tester);

    final marks = await marksOf(tester, feed);
    expect(marks[-1], greaterThan(21));
    expect(marks[-1], lessThan(40));
    expect(marks[-2], greaterThan(21));

    // The new session opens under a divider again, on the first post left unread.
    await open(tester, app(feed));
    expect(find.text('Unread posts'), findsOneWidget);
    final first = marks[-1]! + 1;
    expect(find.text('a-$first'), findsOneWidget);
    expect(find.text('a-21'), findsNothing);
    await unmountFixtures(tester);
  });

  testWidgets('scrolling back over read posts never moves a mark backwards', (
    tester,
  ) async {
    final feed = await feedOf(tester, 'Back', marks: {-1: 40, -2: 40});
    await open(tester, app(feed));
    // Towards the older posts: in a chat-like list that is a drag downwards.
    await tester.dragFrom(_middle, const Offset(0, 1500));
    await tester.pumpAndSettle();
    await settleFixtures(tester);
    await unmountFixtures(tester);

    expect(await marksOf(tester, feed), {-1: 40, -2: 40});
  });

  // ---- the app rests and comes back ----

  testWidgets('the app comes back from the background where it left', (
    tester,
  ) async {
    final feed = await feedOf(tester, 'Resume', marks: {-1: 20, -2: 20});
    await open(tester, app(feed));
    await flushReads(tester);
    final before = top(tester, 'a-21');
    final dividerBefore = divider(tester);
    final marksBefore = await marksOf(tester, feed);

    await pauseAndResume(tester);

    expect(top(tester, 'a-21'), closeTo(before, 0.5));
    expect(divider(tester), closeTo(dividerBefore, 0.5));
    expect(find.text('b-40'), findsNothing);
    expect(await marksOf(tester, feed), marksBefore);
    await unmountFixtures(tester);
  });

  testWidgets('posts that arrive while the app rests wait behind the button', (
    tester,
  ) async {
    final feed = await feedOf(tester, 'Away', marks: {-1: 20, -2: 20});
    await open(tester, app(feed));
    await flushReads(tester);
    final before = top(tester, 'a-21');

    await pauseAndResume(
      tester,
      whileAway: () async {
        gw.arrive(fixturePost(-2, 41, date: 8300, text: 'b-41'));
        gw.arrive(fixturePost(-1, 41, date: 8400, text: 'a-41'));
        await tester.pump();
      },
    );

    // The reader has not moved, and the new posts are counted, not shown.
    expect(top(tester, 'a-21'), closeTo(before, 0.5));
    expect(find.text('b-41'), findsNothing);
    expect(find.byTooltip('2 new posts'), findsOneWidget);

    await tester.tap(find.byTooltip('2 new posts'));
    await tester.pumpAndSettle();
    await settleFixtures(tester);
    expect(find.text('a-41'), findsOneWidget);
    await unmountFixtures(tester);

    // Read at last: the marks cover the posts that arrived while the app rested.
    final marks = await marksOf(tester, feed);
    expect(marks, {-1: 41, -2: 41});
  });

  testWidgets('a post arriving while the reader is at the newest lands under', (
    tester,
  ) async {
    final feed = await feedOf(tester, 'Live', marks: {-1: 40, -2: 40});
    await open(tester, app(feed));
    expect(find.text('b-40'), findsOneWidget);

    gw.arrive(fixturePost(-2, 41, date: 8300, text: 'b-41'));
    await settleFixtures(tester);
    await tester.pumpAndSettle();

    // The list is glued to the newest end, so the post appears at the bottom instead of
    // waiting behind the button.
    expect(find.text('b-41'), findsOneWidget);
    expect(tester.getBottomLeft(cardOf('b-41')).dy, greaterThan(500));
    expect(find.byTooltip('1 new post'), findsNothing);
    await unmountFixtures(tester);

    expect((await marksOf(tester, feed))[-2], 41);
  });

  testWidgets('a feed whose channels were all left still opens', (
    tester,
  ) async {
    gw.histories.clear();
    final feed = await feedOf(tester, 'Empty', channels: {-9: 'Gone'});
    await open(tester, app(feed));

    expect(find.text('No posts.'), findsOneWidget);
    expect(find.text('Unread posts'), findsNothing);
    expect(await marksOf(tester, feed), {-9: 0});
    await unmountFixtures(tester);
  });

  testWidgets('the divider stays where it was while the reader reads', (
    tester,
  ) async {
    final feed = await feedOf(tester, 'Divider', marks: {-1: 20, -2: 20});
    await open(tester, app(feed));
    final before = divider(tester);

    // A screenful towards the newest posts, then back to where the reading started: the
    // divider belongs to this visit and does not follow the marks the reader just moved.
    for (final by in const [-400.0, -400.0, 400.0, 400.0]) {
      await tester.dragFrom(_middle, Offset(0, by));
      await tester.pumpAndSettle();
    }
    await settleFixtures(tester);

    expect(find.text('Unread posts'), findsOneWidget);
    expect(divider(tester), closeTo(before, 2));
    expect(divider(tester), lessThan(top(tester, 'a-21')));
    await unmountFixtures(tester);
  });

  testWidgets('posts that arrived while the app was down sit below the rest', (
    tester,
  ) async {
    final feed = await feedOf(tester, 'Grown', marks: {-1: 20, -2: 20});
    // Three posts came in while the app was not running: the channel's history has them,
    // nothing was pushed to the app.
    for (var id = 41; id <= 43; id++) {
      gw.arrivedUnseen(
        fixturePost(-2, id, date: id * 200 + 100, text: 'b-$id'),
      );
    }
    await open(tester, app(feed));

    // The oldest unread post is still where the reader stopped, not at the new end.
    expect(divider(tester), lessThan(top(tester, 'a-21')));
    expect(find.text('b-43'), findsNothing);
    final badge = tester.widget<Badge>(find.byType(Badge));
    expect(int.parse(((badge.label as Text?)!).data!), greaterThan(30));
    await unmountFixtures(tester);
  });

  // ---- read and unread as in the official app ----

  testWidgets('at the last post every channel of the feed is read', (
    tester,
  ) async {
    // Beta posted ten times in the middle of Alpha's forty: at the newest end of the feed
    // only Alpha is on the screen.
    gw.histories[-2] = fixtureHistory(
      -2,
      to: 10,
      label: 'b',
      step: 200,
      dateOffset: 2000,
    );
    final feed = await feedOf(tester, 'Middle', marks: {-1: 5});
    await open(tester, app(feed));
    expect(find.text('Unread posts'), findsOneWidget);

    // The divider was on the screen, so the button goes to the very end.
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
    await tester.pumpAndSettle();
    await settleFixtures(tester);
    expect(find.text('a-40'), findsOneWidget);
    expect(find.textContaining('b-'), findsNothing);
    await unmountFixtures(tester);

    // Beta's posts were passed on the way, so they are read too.
    expect(await marksOf(tester, feed), {-1: 40, -2: 10});
  });

  testWidgets('the button goes to the unread divider first, then to the end', (
    tester,
  ) async {
    final feed = await feedOf(tester, 'Back', marks: {-1: 20, -2: 20});
    // The reader left this feed scrolled up, at a post read long ago.
    await tester.runAsync(
      () => db.setSetting(
        SettingKeys.positionOfFeed(feed.id),
        const SavedPosition(chatId: -1, rowId: 10, edge: 0.1).encode(),
      ),
    );
    await open(tester, app(feed));
    expect(find.text('a-10'), findsOneWidget);
    expect(find.text('Unread posts'), findsNothing);

    await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
    await tester.pumpAndSettle();
    await settleFixtures(tester);
    expect(find.text('Unread posts'), findsOneWidget);
    expect(divider(tester), lessThan(200));
    expect(find.text('b-40'), findsNothing);

    await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
    await tester.pumpAndSettle();
    await settleFixtures(tester);
    expect(find.text('b-40'), findsOneWidget);
    expect(tester.getBottomLeft(cardOf('b-40')).dy, greaterThan(500));
    await unmountFixtures(tester);
  });

  testWidgets('the button goes back to where a reply quote was tapped', (
    tester,
  ) async {
    gw.histories[-1]![0] = const Post(
      chatId: -1,
      messageId: 40,
      date: 8000,
      text: 'a-40',
      replyTo: ReplyTarget(chatId: -1, messageId: 5, text: 'the quote'),
    );
    final feed = await feedOf(tester, 'Reply', marks: {-1: 40, -2: 40});
    await open(tester, app(feed));
    await tester.tap(find.text('the quote'));
    await tester.pumpAndSettle();
    await settleFixtures(tester, rounds: 6);
    await tester.pumpAndSettle();
    expect(find.text('a-5'), findsOneWidget);
    expect(find.text('a-40'), findsNothing);

    await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
    await tester.pumpAndSettle();
    await settleFixtures(tester, rounds: 6);
    await tester.pumpAndSettle();
    expect(find.text('a-40'), findsOneWidget);
    expect(find.text('a-5'), findsNothing);
    await unmountFixtures(tester);
  });

  testWidgets('a feed left scrolled up opens there again after a restart', (
    tester,
  ) async {
    final feed = await feedOf(tester, 'Kept', marks: {-1: 40, -2: 40});
    await open(tester, app(feed));
    // Towards the older posts, and away.
    await tester.dragFrom(_middle, const Offset(0, 1500));
    await tester.pumpAndSettle();
    await settleFixtures(tester);
    final shown = [
      for (var id = 1; id <= 40; id++)
        for (final label in ['a', 'b'])
          if (find.text('$label-$id').evaluate().isNotEmpty)
            (text: '$label-$id', top: top(tester, '$label-$id')),
    ].where((r) => r.top > 100 && r.top < 450).toList();
    expect(shown, isNotEmpty);
    await restart(tester);

    await open(tester, app(feed));
    for (final row in shown) {
      expect(top(tester, row.text), closeTo(row.top, 2));
    }
    expect(find.text('Unread posts'), findsNothing);
    await unmountFixtures(tester);
  });

  testWidgets('a feed left at its newest post keeps no position', (
    tester,
  ) async {
    final feed = await feedOf(tester, 'Newest', marks: {-1: 40, -2: 40});
    await tester.runAsync(
      () => db.setSetting(
        SettingKeys.positionOfFeed(feed.id),
        const SavedPosition(chatId: -1, rowId: 10, edge: 0.1).encode(),
      ),
    );
    await open(tester, app(feed));
    expect(find.text('a-10'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
    await tester.pumpAndSettle();
    await settleFixtures(tester);
    expect(find.text('b-40'), findsOneWidget);
    await unmountFixtures(tester);
    expect(
      await tester.runAsync(
        () => db.setting(SettingKeys.positionOfFeed(feed.id)),
      ),
      isNull,
    );
  });
}
