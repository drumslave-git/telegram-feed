import 'package:app_db/app_db.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/timeline_screen.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'feeds_screen_test.dart' show ChannelsGateway;

final class TimelineGateway extends ChannelsGateway {
  TimelineGateway(this.histories, {List<Channel> channels = const []})
    : super(channels);
  final Map<int, List<Post>> histories;

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

  testWidgets('merges sources newest first and shows live posts', (
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

    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .where((s) => s.startsWith('one') || s.startsWith('two'))
        .toList();
    expect(texts, ['one-newest', 'two-mid', 'one-old']);
    expect(find.text('One'), findsNWidgets(2)); // both posts of channel One
    expect(find.byTooltip('Open in Telegram'), findsNWidgets(3));
    expect(find.text('End of feed'), findsOneWidget);

    gw.posts.add(PostAdded(post(-2, 9, 900, 'two-live')));
    await settle(tester);
    expect(find.text('two-live'), findsOneWidget);

    gw.posts.add(PostEdited(post(-2, 9, 900, 'two-live-edited')));
    await settle(tester);
    expect(find.text('two-live-edited'), findsOneWidget);

    gw.posts.add(const PostsDeleted(chatId: -1, messageIds: [3]));
    await settle(tester);
    expect(find.text('one-newest'), findsNothing);
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
}
