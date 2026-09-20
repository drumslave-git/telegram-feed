import 'package:app_db/app_db.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/post_card.dart' show ChatPill, PostCard;
import 'package:telegram_feed/feeds/timeline_screen.dart';
import 'package:telegram_feed/feeds/timeline_search.dart';
import 'package:telegram_feed/home/channel_list.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'feeds_screen_test.dart' show ChannelsGateway;

final class TimelineGateway extends ChannelsGateway {
  TimelineGateway(
    this.histories, {
    List<Channel> channels = const [],
    super.folders,
  }) : super(channels);
  final Map<int, List<Post>> histories;
  final reactions = <String>[];

  @override
  Future<void> react(
    int chatId,
    int messageId,
    String emoji, {
    bool remove = false,
  }) async => reactions.add('$chatId/$messageId ${remove ? '-' : '+'}$emoji');

  @override
  Future<SearchPage> searchHistory(
    int chatId, {
    String query = '',
    HistoryFilter filter = HistoryFilter.any,
    int fromMessageId = 0,
    int limit = 30,
  }) async {
    final all = [
      for (final p in histories[chatId] ?? const <Post>[])
        if (query.isEmpty || p.text.toLowerCase().contains(query.toLowerCase()))
          p,
    ];
    final older = fromMessageId == 0
        ? all
        : all.where((p) => p.messageId < fromMessageId).toList();
    final page = older.take(limit).toList();
    return SearchPage(
      posts: page,
      totalCount: all.length,
      nextFromMessageId: page.length < older.length ? page.last.messageId : 0,
    );
  }

  @override
  Future<int> messageIdByDate(int chatId, int unixDate) async {
    for (final p in histories[chatId] ?? const <Post>[]) {
      if (p.date <= unixDate) return p.messageId;
    }
    return 0;
  }

  @override
  Future<List<Post>> historyAfter(
    int chatId, {
    required int afterMessageId,
    int limit = 30,
  }) async {
    final newer = [
      for (final p in histories[chatId] ?? const <Post>[])
        if (p.messageId > afterMessageId) p,
    ];
    return newer.sublist(newer.length > limit ? newer.length - limit : 0);
  }

  @override
  Future<List<Post>> history(
    int chatId, {
    int fromMessageId = 0,
    int limit = 30,
    bool onlyLocal = false,
  }) async {
    final all = histories[chatId] ?? const <Post>[];
    return (fromMessageId == 0
            ? all
            : all.where((p) => p.messageId < fromMessageId))
        .take(limit)
        .toList();
  }
}

void main() {
  late AppDatabase db;
  late TimelineGateway gw;
  late Feed feed;

  Post post(int chat, int id, int date, String text) =>
      Post(chatId: chat, messageId: id, date: date, text: text);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    gw = TimelineGateway({
      -1: [post(-1, 3, 300, 'one-newest'), post(-1, 1, 100, 'one-old')],
      -2: [post(-2, 2, 200, 'two-mid')],
    });
  });

  Future<void> settle(WidgetTester tester) => tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await tester.pump();
  });

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('merges sources, oldest on top, and shows live posts', (
    tester,
  ) async {
    await tester.runAsync(() async {
      feed = await db.createFeed('Mix');
      await db.addSource(feed.id, -1, title: 'One');
      await db.addSource(feed.id, -2, title: 'Two');
    });
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(db: db, gateway: gw, feed: feed),
      ),
    );
    await settle(tester);

    double y(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(y('one-old'), lessThan(y('two-mid')));
    expect(y('two-mid'), lessThan(y('one-newest')));
    expect(find.text('One'), findsNWidgets(2)); // both posts of channel One
    expect(find.byType(PostCard), findsNWidgets(3));
    // Every row has the avatar of its channel (initials here: the fake has no photos), at
    // the right end of the title line inside the bubble.
    expect(find.byType(ChannelAvatar), findsNWidgets(3));
    final title = tester.getRect(find.text('One').first);
    final avatar = tester.getRect(find.byType(ChannelAvatar).first);
    expect(avatar.left, greaterThan(title.right - 1));
    expect(avatar.center.dy, closeTo(title.center.dy, 4));
    expect(find.text('Beginning of the feed'), findsOneWidget);
    // Posts of 1970 in a feed read today: one day label above the oldest of them.
    expect(find.text('January 1, 1970'), findsOneWidget);

    gw.posts.add(PostAdded(post(-2, 9, 900, 'two-live')));
    await settle(tester);
    expect(y('one-newest'), lessThan(y('two-live')));

    gw.posts.add(PostEdited(post(-2, 9, 900, 'two-live-edited')));
    await settle(tester);
    expect(find.text('two-live-edited'), findsOneWidget);

    gw.posts.add(const PostsDeleted(chatId: -1, messageIds: [3]));
    await settle(tester);
    expect(find.text('one-newest'), findsNothing);
    await unmount(tester);
  });

  /// 40 posts of one channel, ids 1..40, newest first as the gateway returns them.
  List<Post> forty() => [
    for (var id = 40; id >= 1; id--) post(-1, id, id * 100, 'post-$id'),
  ];

  testWidgets('opens at the first unread post, under the divider', (
    tester,
  ) async {
    gw.histories[-1] = forty();
    await tester.runAsync(() async {
      feed = await db.createFeed('Unread');
      await db.addSource(feed.id, -1, title: 'One');
      await db.markRead(feed.id, -1, 20);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(db: db, gateway: gw, feed: feed),
      ),
    );
    await settle(tester);
    await tester.pumpAndSettle();

    expect(find.text('Unread posts'), findsOneWidget);
    expect(find.text('post-21'), findsOneWidget);
    expect(find.text('post-40'), findsNothing); // the newest is far below
    final divider = tester.getTopLeft(find.text('Unread posts')).dy;
    expect(divider, lessThan(200)); // near the top of the 600 px window
    expect(divider, lessThan(tester.getTopLeft(find.text('post-21')).dy));
    // The button to the newest posts counts the unread ones below the reader: of the
    // twenty unread posts, seven are on screen.
    expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);
    expect(
      find.descendant(of: find.byType(Badge), matching: find.text('13')),
      findsOneWidget,
    );
    await unmount(tester);
  });

  testWidgets('everything read: opens at the newest post, no divider', (
    tester,
  ) async {
    gw.histories[-1] = forty();
    await tester.runAsync(() async {
      feed = await db.createFeed('Read');
      await db.addSource(feed.id, -1, title: 'One');
      await db.markRead(feed.id, -1, 40);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(db: db, gateway: gw, feed: feed),
      ),
    );
    await settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('Unread posts'), findsNothing);
    expect(find.text('post-40'), findsOneWidget);
    expect(find.byTooltip('Newest posts'), findsNothing);
    await unmount(tester);
  });

  testWidgets('a few unread posts: the newest sits at the bottom, no gap', (
    tester,
  ) async {
    gw.histories[-1] = forty();
    await tester.runAsync(() async {
      feed = await db.createFeed('Few');
      await db.addSource(feed.id, -1, title: 'One');
      await db.markRead(feed.id, -1, 39);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(db: db, gateway: gw, feed: feed),
      ),
    );
    await settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('Unread posts'), findsOneWidget);
    final card = find.ancestor(
      of: find.text('post-40'),
      matching: find.byType(PostCard),
    );
    expect(tester.getBottomLeft(card).dy, greaterThan(580));
    await unmount(tester);
  });

  testWidgets('posts seen to their end are marked read', (tester) async {
    gw.histories[-1] = forty();
    await tester.runAsync(() async {
      feed = await db.createFeed('Marks');
      await db.addSource(feed.id, -1, title: 'One');
      await db.markRead(feed.id, -1, 20);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(db: db, gateway: gw, feed: feed),
      ),
    );
    await settle(tester);
    await tester.pumpAndSettle();
    await unmount(tester); // closing the screen flushes the marks
    final marks = await tester.runAsync(() => db.readMarks(feed.id));
    // The rows that fit under the divider were on screen; the newest posts were not.
    expect(marks![-1], greaterThan(21));
    expect(marks[-1], lessThan(40));
  });

  testWidgets('reopening within the session lands on the same post', (
    tester,
  ) async {
    gw.histories[-1] = forty();
    await tester.runAsync(() async {
      feed = await db.createFeed('Back');
      await db.addSource(feed.id, -1, title: 'One');
      await db.markRead(feed.id, -1, 40);
    });
    Widget app() => MaterialApp(
      home: TimelineScreen(db: db, gateway: gw, feed: feed),
    );
    await tester.pumpWidget(app());
    await settle(tester);
    await tester.pumpAndSettle();
    // Towards older posts: in a chat-like list that is a drag downwards.
    await tester.drag(
      find.byType(PostCard).first,
      const Offset(0, 1500),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(find.text('post-40'), findsNothing);
    final visible = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .where((t) => t.startsWith('post-'))
        .toSet();
    await unmount(tester);

    await tester.pumpWidget(app());
    await settle(tester);
    await tester.pumpAndSettle();
    final again = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .where((t) => t.startsWith('post-'))
        .toSet();
    expect(again.intersection(visible), isNotEmpty);
    expect(find.text('post-40'), findsNothing);
    await unmount(tester);
  });

  testWidgets('new posts while reading older ones wait behind the button', (
    tester,
  ) async {
    gw.histories[-1] = forty();
    await tester.runAsync(() async {
      feed = await db.createFeed('Live');
      await db.addSource(feed.id, -1, title: 'One');
      await db.markRead(feed.id, -1, 20);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(db: db, gateway: gw, feed: feed),
      ),
    );
    await settle(tester);
    await tester.pumpAndSettle();

    gw.posts.add(PostAdded(post(-1, 41, 4100, 'post-41')));
    await settle(tester);
    expect(find.text('post-41'), findsNothing);
    expect(find.byTooltip('1 new post'), findsOneWidget);

    await tester.tap(find.byTooltip('1 new post'));
    await tester.pumpAndSettle();
    expect(find.text('post-41'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('focus on a post from a notification loads and marks it', (
    tester,
  ) async {
    await tester.runAsync(() async {
      feed = await db.createFeed('Mix');
      await db.addSource(feed.id, -1, title: 'One');
    });
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          db: db,
          gateway: gw,
          feed: feed,
          focusChatId: -1,
          focusMessageId: 1,
        ),
      ),
    );
    await settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('one-old'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('reactions: pills show counts, tap toggles, the menu adds', (
    tester,
  ) async {
    gw.histories[-1] = [
      Post(
        chatId: -1,
        messageId: 3,
        date: 300,
        text: 'hot take',
        reactions: const [
          Reaction(emoji: '🔥', count: 4, chosen: true),
          Reaction(emoji: '👍', count: 1),
        ],
      ),
    ];
    await tester.runAsync(() async {
      feed = await db.createFeed('R');
      await db.addSource(feed.id, -1, title: 'One');
    });
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(db: db, gateway: gw, feed: feed),
      ),
    );
    await settle(tester);
    expect(find.text('🔥 4'), findsOneWidget);
    await tester.tap(find.text('🔥 4'));
    await settle(tester);
    expect(gw.reactions, ['-1/3 -🔥']);
    await tester.tap(find.text('👍 1'));
    await settle(tester);
    expect(gw.reactions.last, '-1/3 +👍');

    // A tap on the bubble opens the menu, with the emoji the channel allows on top.
    await tester.tap(find.text('hot take'));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('Open in Telegram'), findsOneWidget);
    await tester.tap(find.text('👍'));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(gw.reactions.last, '-1/3 +👍');
    await unmount(tester);
  });

  testWidgets('share sends text with the link; copy link fills the clipboard', (
    tester,
  ) async {
    gw.histories[-1001446168251] = [
      Post(
        chatId: -1001446168251,
        messageId: 5 << 20,
        date: 300,
        text: 'shareable',
      ),
    ];
    await tester.runAsync(() async {
      feed = await db.createFeed('S');
      await db.addSource(
        feed.id,
        -1001446168251,
        title: 'News',
        username: 'news',
      );
    });
    final shared = <String>[];
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
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(
          db: db,
          gateway: gw,
          feed: feed,
          share: (text, {required subject}) async =>
              shared.add('$subject|$text'),
        ),
      ),
    );
    await settle(tester);

    // Sharing is in the menu; nothing stands beside the bubble.
    expect(find.byTooltip('Share'), findsNothing);
    await tester.longPress(find.text('shareable'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(shared, ['News|News\n\nshareable\n\nhttps://t.me/news/5']);

    await tester.tap(find.text('shareable'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy link'));
    await tester.pumpAndSettle();
    expect(copied, 'https://t.me/news/5');
    expect(find.textContaining('Link copied'), findsOneWidget);

    // The snack bar covers the post until it has gone.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('shareable'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save to Saved Messages'));
    await tester.pumpAndSettle();
    expect(gw.saved, ['-1001446168251:${5 << 20}']);
    expect(find.text('Saved to Saved Messages'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('the menu of a video post leads to the autoplay settings', (
    tester,
  ) async {
    gw.histories[-1] = [
      post(-1, 4, 400, 'just text'),
      const Post(
        chatId: -1,
        messageId: 3,
        date: 300,
        text: 'with a video',
        media: VideoMedia(
          file: FileRef(
            id: 9,
            remoteId: 'v',
            size: 100,
            width: 640,
            height: 360,
          ),
          durationSeconds: 12,
        ),
      ),
    ];
    await tester.runAsync(() async {
      feed = await db.createFeed('V');
      await db.addSource(feed.id, -1, title: 'One');
      await db.markRead(
        feed.id,
        -1,
        4,
      ); // opens at the newest post, both texts in view
    });
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(db: db, gateway: gw, feed: feed),
      ),
    );
    await settle(tester);

    await tester.tap(find.text('just text'));
    await tester.pumpAndSettle();
    expect(find.text('Copy link'), findsOneWidget);
    expect(find.text('Video autoplay settings'), findsNothing);
    await tester.tapAt(const Offset(10, 10)); // the barrier closes the menu
    await tester.pumpAndSettle();

    await tester.tap(find.text('with a video'));
    await tester.pumpAndSettle();
    // The menu scrolls; its last entry is below the fold on this small screen.
    await tester.ensureVisible(find.text('Video autoplay settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Video autoplay settings'));
    await settle(tester);
    await tester.pumpAndSettle();
    final autoplay = find.widgetWithText(
      SwitchListTile,
      'Autoplay short videos',
    );
    expect(tester.widget<SwitchListTile>(autoplay).value, isTrue);
    await tester.tap(autoplay);
    await settle(tester);
    expect(
      await tester.runAsync(() => db.setting(SettingKeys.autoplay)),
      'false',
    );
    await unmount(tester);
  });

  testWidgets('the newest post keeps its distance from the bottom edge', (
    tester,
  ) async {
    await tester.runAsync(() async {
      feed = await db.createFeed('P');
      await db.addSource(feed.id, -1, title: 'One');
      await db.markRead(feed.id, -1, 3); // opens at the newest post
    });
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(db: db, gateway: gw, feed: feed),
      ),
    );
    await settle(tester);

    final screen = tester.getSize(find.byType(MaterialApp)).height;
    final lowest = tester
        .widgetList<PostCard>(find.byType(PostCard))
        .map((c) => tester.getRect(find.byWidget(c)).bottom)
        .reduce((a, b) => a > b ? a : b);
    // The card's own 3 px would leave the bubble all but touching the edge.
    expect(screen - lowest, greaterThanOrEqualTo(8));
    await unmount(tester);
  });

  testWidgets('feed without channels explains what to do', (tester) async {
    await tester.runAsync(() async => feed = await db.createFeed('Empty'));
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(db: db, gateway: gw, feed: feed),
      ),
    );
    await settle(tester);
    expect(find.textContaining('no channels yet'), findsOneWidget);
    await unmount(tester);
  });
  testWidgets('search: merged results, a tap opens the timeline at the post', (
    tester,
  ) async {
    // Forty posts per channel, so the match is far outside the first page.
    gw.histories[-1] = [
      for (var id = 40; id >= 1; id--)
        post(-1, id, id * 100, id == 4 ? 'rain in Berlin' : 'one-$id'),
    ];
    gw.histories[-2] = [
      for (var id = 40; id >= 1; id--)
        post(-2, id, id * 100 + 50, id == 30 ? 'rain in Prague' : 'two-$id'),
    ];
    await tester.runAsync(() async {
      feed = await db.createFeed('Mix');
      await db.addSource(feed.id, -1, title: 'One');
      await db.addSource(feed.id, -2, title: 'Two');
    });
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(db: db, gateway: gw, feed: feed),
      ),
    );
    await settle(tester);

    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'rain');
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);

    // Both channels answered, newest match first. The rows mark the query, so their text
    // is rich: they are found by what they contain.
    Finder inResults(String text) => find.descendant(
      of: find.byType(SearchResults),
      matching: find.textContaining(text),
    );
    expect(find.byType(SearchResultTile), findsNWidgets(2));
    expect(inResults('in Prague'), findsOneWidget);
    expect(inResults('in Berlin'), findsOneWidget);
    expect(
      tester.getTopLeft(inResults('in Prague')).dy,
      lessThan(tester.getTopLeft(inResults('in Berlin')).dy),
    );
    expect(find.text('2 results'), findsOneWidget);

    // The older match: the timeline is rebuilt around it and the stepper appears.
    await tester.tap(find.byType(SearchResultTile).last);
    await settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('2 of 2'), findsOneWidget);
    expect(find.byType(SearchResults), findsNothing);
    expect(
      find.descendant(
        of: find.byType(PostCard),
        matching: find.text('rain in Berlin'),
      ),
      findsOneWidget,
    );
    // Around it: the neighbouring posts of both channels, not the newest ones.
    expect(find.text('one-40'), findsNothing);
    expect(find.textContaining('two-'), findsWidgets);

    // Step to the newer match.
    await tester.tap(find.byTooltip('Newer match'));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('1 of 2'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(PostCard),
        matching: find.text('rain in Prague'),
      ),
      findsOneWidget,
    );
    await unmount(tester);
  });

  testWidgets('a jumped timeline pages back to the newest posts', (
    tester,
  ) async {
    gw.histories[-1] = [
      for (var id = 40; id >= 1; id--)
        post(-1, id, id * 100, id == 2 ? 'rain' : 'one-$id'),
    ];
    await tester.runAsync(() async {
      feed = await db.createFeed('One');
      await db.addSource(feed.id, -1, title: 'One');
    });
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(db: db, gateway: gw, feed: feed),
      ),
    );
    await settle(tester);
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'rain');
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    await tester.tap(find.byType(SearchResultTile).first);
    await settle(tester);
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: find.byType(PostCard), matching: find.text('rain')),
      findsOneWidget,
    );
    expect(find.text('one-40'), findsNothing);
    // The button of a jumped timeline goes back to the live one (the search bar has an
    // arrow of its own for the next match).
    await tester.tap(
      find.descendant(
        of: find.byType(FloatingActionButton),
        matching: find.byIcon(Icons.keyboard_arrow_down),
      ),
    );
    await settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('one-40'), findsOneWidget);
    await unmount(tester);
  });
  testWidgets(
    'jump to date: the calendar opens from a day pill and from search',
    (tester) async {
      // Three days of posts in two channels, 24 hours apart.
      const day = 86400;
      const base = 1700000000; // 2023-11-14 22:13 UTC
      gw.histories[-1] = [
        for (var i = 6; i >= 1; i--) post(-1, i, base + i * day ~/ 2, 'one-$i'),
      ];
      gw.histories[-2] = [
        for (var i = 6; i >= 1; i--)
          post(-2, i, base + i * day ~/ 2 + 60, 'two-$i'),
      ];
      await tester.runAsync(() async {
        feed = await db.createFeed('Mix');
        await db.addSource(feed.id, -1, title: 'One');
        await db.addSource(feed.id, -2, title: 'Two');
      });
      await tester.pumpWidget(
        MaterialApp(
          home: TimelineScreen(db: db, gateway: gw, feed: feed),
        ),
      );
      await settle(tester);
      await tester.pumpAndSettle();

      // A day pill leads to the calendar; so does the button in the search bar.
      await tester.tap(find.byType(ChatPill).first);
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Jump to date'));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      // The search bar made way for the calendar.
      expect(find.byTooltip('Search'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Jumping to the first day lands on its first post, with the older ones above it.
      final first = DateTime.fromMillisecondsSinceEpoch(
        (base + day ~/ 2) * 1000,
      );
      final state = tester.state<TimelineViewState>(find.byType(TimelineView));
      await tester.runAsync(
        () => state.jumpToDate(DateTime(first.year, first.month, first.day)),
      );
      await settle(tester);
      await tester.pumpAndSettle();
      expect(find.text('one-1'), findsOneWidget);
      expect(
        find.text('one-6'),
        findsNothing,
      ); // the newest posts are far below
      await unmount(tester);
    },
  );

  testWidgets('jump to a date before the first post says so', (tester) async {
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
    final state = tester.state<TimelineViewState>(find.byType(TimelineView));
    await tester.runAsync(() => state.jumpToDate(DateTime(1969, 1, 1)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nothing here from'), findsOneWidget);
    await unmount(tester);
  });
  testWidgets('a date jump opens at the first post of a busy day', (
    tester,
  ) async {
    final day = DateTime(2026, 9, 15);
    int at(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;
    // More posts on that day than a page holds, and a few from the day before.
    gw.histories[-1] = [
      for (var i = 45; i >= 1; i--)
        post(
          -1,
          100 + i,
          at(day.add(Duration(minutes: 10 * i))),
          'day-${i.toString().padLeft(2, '0')}',
        ),
      for (var i = 5; i >= 1; i--)
        post(
          -1,
          50 + i,
          at(day.subtract(Duration(hours: 24 - i))),
          'before-$i',
        ),
    ];
    await tester.runAsync(() async {
      feed = await db.createFeed('One');
      await db.addSource(feed.id, -1, title: 'One');
    });
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(db: db, gateway: gw, feed: feed),
      ),
    );
    await settle(tester);

    final state = tester.state<TimelineViewState>(find.byType(TimelineView));
    await tester.runAsync(() => state.jumpToDate(day));
    await settle(tester);
    await tester.pumpAndSettle();

    // The first post of the day, not the last one the first page reached.
    expect(find.text('day-01'), findsOneWidget);
    expect(find.text('before-5'), findsOneWidget); // the day before, above it
    expect(
      find.text('day-45'),
      findsNothing,
    ); // the end of the day is far below
    await unmount(tester);
  });
}
