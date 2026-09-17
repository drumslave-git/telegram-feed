import 'dart:async';

import 'package:app_db/app_db.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/feeds_screen.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

class ChannelsGateway implements TelegramGateway {
  ChannelsGateway(this.channels);
  final List<Channel> channels;
  final posts = StreamController<PostEvent>.broadcast();

  @override
  Future<List<Channel>> myChannels() async => channels;
  @override
  Stream<PostEvent> get postEvents => posts.stream;

  @override
  Stream<AuthState> get authState => Stream.value(const AuthReady());
  @override
  Stream<ChannelMembershipEvent> get membershipEvents => const Stream.empty();
  @override
  Stream<FileProgress> fileProgress(int fileId) => const Stream.empty();
  @override
  Future<void> setPhoneNumber(String phone) async {}
  @override
  Future<void> checkCode(String code) async {}
  @override
  Future<void> checkPassword(String password) async {}
  @override
  Future<void> registerUser({
    required String firstName,
    String lastName = '',
  }) async {}
  @override
  Future<void> requestQrCode() async {}
  @override
  Future<void> logOut() async {}
  @override
  Future<List<Post>> history(
    int chatId, {
    int fromMessageId = 0,
    int limit = 30,
    bool onlyLocal = false,
  }) async => const [];
  @override
  Future<void> markViewed(int chatId, List<int> messageIds) async {}
  @override
  Future<FileRef> download(FileRef ref, {int priority = 16}) async => ref;
  @override
  Future<void> close() async {}

  @override
  Future<List<String>> availableReactions(int chatId, int messageId) async =>
      const ['👍', '🔥'];
  @override
  Future<void> react(
    int chatId,
    int messageId,
    String emoji, {
    bool remove = false,
  }) async {}
  @override
  Future<UserInfo> me() async =>
      const UserInfo(id: 1, firstName: 'Test', phoneNumber: '+1');
  @override
  Future<StorageStats> storageStats() async =>
      const StorageStats(filesBytes: 0, fileCount: 0, databaseBytes: 0);
  @override
  Future<StorageStats> clearCache() => storageStats();
}

// Drift does real I/O, so every step runs under tester.runAsync (real clock).
void main() {
  late AppDatabase db;
  late ChannelsGateway gw;
  final opened = <String>[];

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    gw = ChannelsGateway(const [
      Channel(chatId: -1, title: 'One', lastMessageId: 100),
      Channel(chatId: -2, title: 'Two', lastMessageId: 200),
    ]);
    opened.clear();
  });
  // No tearDown close: the in-memory database is garbage collected, and closing it while a
  // failed test still has streams open would hang the run.

  Widget app() => MaterialApp(
    home: FeedsScreen(
      db: db,
      gateway: gw,
      onOpenFeed: (f) => opened.add(f.name),
    ),
  );

  /// Lets real async work (database, streams) happen, then rebuilds.
  Future<void> settle(WidgetTester tester) => tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await tester.pump();
  });

  /// Unmounts the screen (cancelling its database streams) before tearDown closes the db.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    // Flush drift's zero-duration cleanup timers scheduled in the test zone.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('empty state, create, rename, delete', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);
    expect(find.textContaining('No feeds yet'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Tech');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    await settle(tester);
    expect(find.text('Tech'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Technology');
    await tester.tap(find.text('Rename').last);
    await tester.pumpAndSettle();
    await settle(tester);
    expect(find.text('Technology'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    await settle(tester);
    expect(find.textContaining('No feeds yet'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('badge counts sources with posts newer than the read mark', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final f = await db.createFeed('News');
      await db.addSource(f.id, -1, title: 'One');
      await db.addSource(f.id, -2, title: 'Two');
      await db.markRead(f.id, -1, 100); // One fully read, Two not
    });

    await tester.pumpWidget(app());
    await settle(tester);
    expect(find.text('1 channel with new posts'), findsOneWidget);

    await tester.runAsync(() async {
      final f = (await db.allFeeds()).single;
      await db.markRead(f.id, -2, 200);
    });
    await settle(tester);
    expect(find.textContaining('with new posts'), findsNothing);

    gw.posts.add(
      PostAdded(Post(chatId: -2, messageId: 201, date: 1, text: 'x')),
    );
    await settle(tester);
    expect(find.text('1 channel with new posts'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('tapping a feed opens it; reordering persists', (tester) async {
    late int a, b;
    await tester.runAsync(() async {
      a = (await db.createFeed('A')).id;
      b = (await db.createFeed('B')).id;
    });
    await tester.pumpWidget(app());
    await settle(tester);

    await tester.tap(find.text('A'));
    expect(opened, ['A']);

    await tester.runAsync(() => db.reorderFeeds([b, a]));
    await settle(tester);
    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect((tiles.first.title as Text).data, 'B');
    await unmount(tester);
  });
}
