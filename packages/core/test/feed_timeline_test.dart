import 'dart:async';

import 'package:core/core.dart';
import 'package:telegram_gateway/telegram_gateway.dart';
import 'package:test/test.dart';

/// Histories per chat, newest first; `local` is what only_local returns.
final class HistoryGateway implements TelegramGateway {
  HistoryGateway(this.network, {this.local = const {}});
  final Map<int, List<Post>> network;
  final Map<int, List<Post>> local;
  final calls = <String>[];

  @override
  Future<List<Post>> history(
    int chatId, {
    int fromMessageId = 0,
    int limit = 30,
    bool onlyLocal = false,
  }) async {
    calls.add('$chatId:$fromMessageId:${onlyLocal ? 'local' : 'net'}');
    final all = (onlyLocal ? local[chatId] : network[chatId]) ?? const [];
    final older = fromMessageId == 0
        ? all
        : all.where((p) => p.messageId < fromMessageId).toList();
    return older.take(limit).toList();
  }

  @override
  Stream<AuthState> get authState => const Stream.empty();
  @override
  Stream<ChannelMembershipEvent> get membershipEvents => const Stream.empty();
  @override
  Stream<PostEvent> get postEvents => const Stream.empty();
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
  Future<List<Channel>> myChannels() async => const [];
  @override
  Future<void> markViewed(int chatId, List<int> messageIds) async {}
  @override
  Future<FileRef> download(FileRef ref, {int priority = 16}) async => ref;
  @override
  Future<void> close() async {}
  @override
  Future<UserInfo> me() async =>
      const UserInfo(id: 1, firstName: 'Test', phoneNumber: '+1');
  @override
  Future<StorageStats> storageStats() async =>
      const StorageStats(filesBytes: 0, fileCount: 0, databaseBytes: 0);
  @override
  Future<StorageStats> clearCache() => storageStats();
}

Post p(int chat, int id, int date, {int album = 0, String? text}) => Post(
  chatId: chat,
  messageId: id,
  date: date,
  text: text ?? 'm$id',
  albumId: album,
);

/// n posts for a chat: ids n..1, dates spaced by [step] starting at [start].
List<Post> series(int chat, int n, {int start = 1000, int step = 10}) => [
  for (var i = n; i >= 1; i--) p(chat, i, start + i * step),
];

void main() {
  test('merges by date desc across sources and pages', () async {
    final g = HistoryGateway({
      -1: series(-1, 50, start: 0, step: 10), // dates 10..500
      -2: series(-2, 50, start: 5, step: 10), // dates 15..505
    });
    final t = FeedTimeline(g, [-1, -2], pageSize: 10, historyLimit: 30);
    final page1 = await t.loadMore();
    expect(page1.length, 10);
    final dates = page1.map((i) => i.head.date).toList();
    expect(dates, List.of(dates)..sort((a, b) => b.compareTo(a)));
    expect(dates.first, 505);

    var total = page1.length;
    while (!t.exhausted) {
      total += (await t.loadMore()).length;
    }
    expect(total, 100);
    expect(
      t.items.map((i) => (i.chatId, i.head.messageId)).toSet().length,
      100,
    );
    // Every fill tried the local database first.
    expect(g.calls.first, endsWith(':local'));
  });

  test('falls back to the network when the local database is empty', () async {
    // The local database holds only the newest post; older ones come from the network.
    final g = HistoryGateway(
      {-1: series(-1, 3)},
      local: {-1: series(-1, 3).take(1).toList()},
    );
    final t = FeedTimeline(g, [-1], pageSize: 10);
    await t.loadMore();
    expect(t.items.length, 3);
    expect(g.calls.take(3), ['-1:0:local', '-1:3:local', '-1:3:net']);
  });

  test(
    'collapses albums into one item with parts, newest part as head',
    () async {
      final g = HistoryGateway({
        -1: [
          p(-1, 5, 50),
          p(-1, 4, 40, album: 7, text: ''),
          p(-1, 3, 40, album: 7, text: 'caption'),
          p(-1, 2, 40, album: 7, text: ''),
          p(-1, 1, 10),
        ],
      });
      final t = FeedTimeline(g, [-1]);
      await t.loadMore();
      expect(t.items.length, 3);
      final album = t.items[1];
      expect(album.isAlbum, isTrue);
      expect(album.head.messageId, 4);
      expect(album.parts.map((x) => x.messageId), [3, 2]);
      expect(album.text, 'caption');
    },
  );

  test(
    'live: new posts at top insert, otherwise pending until released',
    () async {
      final g = HistoryGateway({-1: series(-1, 2), -2: const []});
      final t = FeedTimeline(g, [-1, -2]);
      await t.loadMore();

      expect(t.apply(PostAdded(p(-2, 9, 9999))), isTrue);
      expect(t.items.first.head.messageId, 9);
      expect(t.apply(PostAdded(p(-3, 1, 9999))), isFalse); // not a source
      expect(t.apply(PostAdded(p(-2, 9, 9999))), isFalse); // duplicate

      t.atTop = false;
      expect(t.apply(PostAdded(p(-1, 10, 10000))), isFalse);
      expect(t.apply(PostAdded(p(-1, 11, 10001))), isFalse);
      expect(t.pendingNew, 2);
      expect(t.items.first.head.messageId, 9);
      t.releasePending();
      expect(t.pendingNew, 0);
      expect(t.items.take(3).map((i) => i.head.messageId), [11, 10, 9]);
    },
  );

  test('unread helpers: first unread index and reached marks', () async {
    final g = HistoryGateway({-1: series(-1, 6), -2: series(-2, 6)});
    final t = FeedTimeline(g, [-1, -2], pageSize: 4, historyLimit: 2);
    await t.loadMore(); // 4 newest: ids 6,5 of each chat
    final marks = {-1: 4, -2: 5};
    expect(t.items.where((i) => FeedTimeline.isUnread(i, marks)).length, 3);
    // Ids 6 and 5 of both chats are out; nothing newer than the marks is left.
    expect(t.reachedMarks(marks), isTrue);
    final idx = t.firstUnreadIndex(marks);
    expect(idx, greaterThanOrEqualTo(0));
    expect(t.items[idx].head.messageId, 5);
    expect(t.items[idx].chatId, -1);
    // Everything after idx is read.
    expect(
      t.items.skip(idx + 1).any((i) => FeedTimeline.isUnread(i, marks)),
      isFalse,
    );
    expect(t.firstUnreadIndex({-1: 99, -2: 99}), -1);
  });

  test('live: album parts arriving one by one join the same item', () async {
    final t = FeedTimeline(HistoryGateway({-1: const []}), [-1]);
    await t.loadMore();
    t.apply(PostAdded(p(-1, 20, 500, album: 3)));
    t.apply(PostAdded(p(-1, 21, 500, album: 3)));
    t.apply(PostAdded(p(-1, 22, 500, album: 3)));
    expect(t.items.length, 1);
    expect(t.items.single.head.messageId, 22);
    expect(t.items.single.parts.map((x) => x.messageId), [21, 20]);
  });

  test(
    'live: edits replace in place, deletes remove or promote album parts',
    () async {
      final g = HistoryGateway({
        -1: [p(-1, 5, 50), p(-1, 4, 40, album: 7), p(-1, 3, 40, album: 7)],
      });
      final t = FeedTimeline(g, [-1]);
      await t.loadMore();

      expect(t.apply(PostEdited(p(-1, 5, 50, text: 'edited'))), isTrue);
      expect(t.items.first.head.text, 'edited');
      expect(t.apply(PostEdited(p(-1, 99, 1))), isFalse);

      expect(t.apply(const PostsDeleted(chatId: -1, messageIds: [4])), isTrue);
      expect(t.items[1].head.messageId, 3); // part promoted to head
      expect(t.apply(const PostsDeleted(chatId: -1, messageIds: [3])), isTrue);
      expect(t.items.length, 1);
      expect(t.apply(const PostsDeleted(chatId: -2, messageIds: [5])), isFalse);
    },
  );
}
