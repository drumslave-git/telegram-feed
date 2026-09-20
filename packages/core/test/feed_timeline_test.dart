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

  /// Posts newer than an id, newest first (the merge pages this way after a jump).
  @override
  Future<List<Post>> historyAfter(
    int chatId, {
    required int afterMessageId,
    int limit = 30,
  }) async {
    calls.add('after:$chatId:$afterMessageId');
    final newer = [
      for (final p in network[chatId] ?? const <Post>[])
        if (p.messageId > afterMessageId) p,
    ];
    return newer.sublist(newer.length > limit ? newer.length - limit : 0);
  }

  /// Searches the same histories: substring match on the text, media kind for the tabs.
  @override
  Future<SearchPage> searchHistory(
    int chatId, {
    String query = '',
    HistoryFilter filter = HistoryFilter.any,
    int fromMessageId = 0,
    int limit = 30,
  }) async {
    calls.add('search:$chatId:$query:${filter.name}:$fromMessageId');
    final all = [
      for (final p in network[chatId] ?? const <Post>[])
        if ((query.isEmpty ||
                p.text.toLowerCase().contains(query.toLowerCase())) &&
            _matches(filter, p))
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

  static bool _matches(HistoryFilter f, Post post) {
    final m = post.media;
    return switch (f) {
      HistoryFilter.any => true,
      HistoryFilter.photoAndVideo => m is PhotoMedia || m is VideoMedia,
      HistoryFilter.document => m is DocumentMedia,
      HistoryFilter.url => post.text.contains('http'),
      HistoryFilter.audio => m is AudioMedia && !m.isVoice,
      HistoryFilter.voice => m is AudioMedia && m.isVoice,
    };
  }

  @override
  Future<int> messageIdByDate(int chatId, int unixDate) async {
    calls.add('byDate:$chatId:$unixDate');
    for (final p in network[chatId] ?? const <Post>[]) {
      if (p.date <= unixDate) return p.messageId;
    }
    return 0;
  }

  @override
  Future<ChannelInfo> channelInfo(int chatId) async =>
      ChannelInfo(chatId: chatId);

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
  Future<void> saveToSavedMessages(int chatId, List<int> messageIds) async {}
  @override
  Future<FileRef> download(FileRef ref, {int priority = 16}) async => ref;
  @override
  Future<FileProgress> downloadFrom(
    int fileId, {
    int offset = 0,
    int priority = 32,
  }) async => FileProgress(fileId: fileId, downloaded: 0, total: 0);
  @override
  Future<int> downloadedPrefix(int fileId, int offset) async => 0;
  @override
  Future<void> cancelDownload(int fileId) async {}
  @override
  Future<List<ChatFolder>> chatFolders() async => const [];
  @override
  Future<void> close() async {}

  @override
  Future<Thread?> discussion(int chatId, int messageId) async => null;
  @override
  Future<List<Comment>> threadHistory(
    Thread thread, {
    int fromMessageId = 0,
    int limit = 30,
  }) async => const [];
  @override
  Future<void> reply(Thread thread, String text) async {}
  @override
  Stream<Comment> get comments => const Stream.empty();
  @override
  Future<void> closeThread(Thread thread) async {}

  /// Ready, unless a test says otherwise.
  final connectionStatus = StreamController<ConnectionStatus>.broadcast();

  @override
  Stream<ConnectionStatus> get connection async* {
    yield ConnectionStatus.ready;
    yield* connectionStatus.stream;
  }

  @override
  Future<Post?> pinnedPost(int chatId) async => null;
  @override
  Future<Map<String, StickerMedia>> customEmoji(List<String> ids) async =>
      const {};
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
  test('opened at anchors: older first, then back towards the newest', () async {
    final g = HistoryGateway({
      -1: series(-1, 20, start: 0, step: 10), // ids 20..1, dates 200..10
      -2: series(-2, 20, start: 5, step: 10), // ids 20..1, dates 205..15
    });
    // Open around date 100: -1 at its id 10 (date 100), -2 at its id 9 (date 95).
    final t = FeedTimeline(
      g,
      [-1, -2],
      pageSize: 4,
      historyLimit: 4,
      startAt: {-1: 10, -2: 9},
    );
    expect(t.anchored, isTrue);
    expect(t.atTop, isFalse);

    final older = await t.loadMore();
    expect(older.map((i) => i.head.date), [100, 95, 90, 85]);
    // The anchors themselves are the newest rows: nothing newer was loaded yet.
    expect(t.items.first.head.date, 100);

    final added = await t.loadNewer();
    expect(added, 8); // four from each source
    // Four posts per source: -1 reached date 140, -2 date 135; still below the newest.
    expect(t.items.first.head.date, 140);
    expect(t.exhaustedNewer, isFalse);

    // Paging up until both sources run out ends at the newest posts of the feed.
    while (!t.exhaustedNewer) {
      await t.loadNewer();
    }
    expect(t.items.first.head.date, 205);
    final dates = t.items.map((i) => i.head.date).toList();
    expect(dates, List.of(dates)..sort((a, b) => b.compareTo(a)));
  });

  test(
    'a source with nothing that old stays out of an anchored timeline',
    () async {
      final g = HistoryGateway({
        -1: series(-1, 5, start: 0, step: 10),
        -2: series(-2, 5, start: 500, step: 10), // all newer than the anchor
      });
      final t = FeedTimeline(g, [-1, -2], pageSize: 10, startAt: {-1: 3});
      await t.loadMore();
      expect(t.items.map((i) => i.chatId).toSet(), {-1});
      expect(t.exhausted, isTrue);
    },
  );

  test('unreadBefore counts the unread rows below a position', () async {
    final g = HistoryGateway({-1: series(-1, 10, start: 0, step: 10)});
    final t = FeedTimeline(g, [-1], pageSize: 10);
    await t.loadMore();
    // Rows are newest first: ids 10..1, read up to id 6.
    const marks = {-1: 6};
    expect(t.unreadBefore(0, marks), 0); // at the newest post
    expect(t.unreadBefore(3, marks), 3); // ids 10, 9, 8 are unread
    expect(t.unreadBefore(t.items.length, marks), 4); // 10, 9, 8, 7
    expect(t.unreadBefore(3, const {}), 3); // nothing read yet
  });

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

  group('filter', () {
    const file = FileRef(id: 1, remoteId: 'r', size: 1);
    Post photo(int id, {int album = 0, String text = ''}) => Post(
      chatId: -1,
      messageId: id,
      date: id,
      text: text,
      albumId: album,
      media: const PhotoMedia(sizes: [file]),
    );
    Post video(int id, {int album = 0, String text = ''}) => Post(
      chatId: -1,
      messageId: id,
      date: id,
      text: text,
      albumId: album,
      media: const VideoMedia(file: file, durationSeconds: 30),
    );
    const videosOnly = FeedFilter(kinds: {MediaKind.video});
    Post text(int id) =>
        Post(chatId: -1, messageId: id, date: id, text: 't$id');

    test('hidden posts never become rows, live ones included', () async {
      final gw = HistoryGateway({
        -1: [text(5), photo(4), text(3), photo(2), text(1)],
      });
      final t = FeedTimeline(gw, [
        -1,
      ], filter: const FeedFilter(media: MediaPresence.withMedia));
      await t.loadMore();
      expect(t.items.map((i) => i.head.messageId), [4, 2]);
      expect(t.apply(PostAdded(text(6))), isFalse);
      expect(t.pendingNew, 0);
      expect(t.apply(PostAdded(photo(7))), isTrue);
      expect(t.items.first.head.messageId, 7);
    });

    test('reading a row covers the hidden posts that follow it', () async {
      final gw = HistoryGateway({
        -1: [text(6), text(5), photo(4), text(3), photo(2), text(1)],
      });
      final t = FeedTimeline(gw, [
        -1,
      ], filter: const FeedFilter(media: MediaPresence.withMedia));
      await t.loadMore();
      expect(t.coveredFrom(-1, 2), 3); // up to the next shown post (4)
      expect(t.coveredFrom(-1, 4), 6); // everything newer is hidden
      expect(t.coveredFrom(-1, 6), 6);
      expect(t.sortedDownTo(-1, 1), isTrue);
    });

    test('a shown post waiting behind the button is not skipped', () async {
      final gw = HistoryGateway({
        -1: [photo(2)],
      });
      final t = FeedTimeline(gw, [
        -1,
      ], filter: const FeedFilter(media: MediaPresence.withMedia));
      await t.loadMore();
      t.atTop = false;
      t.apply(PostAdded(photo(3))); // waits as pending
      t.apply(PostAdded(text(4))); // hidden
      expect(t.coveredFrom(-1, 2), 2);
    });

    group('whole posts', () {
      test(
        'the album keeps the parts the filter hides, in either order',
        () async {
          // Two albums of a picture with the caption and a video, sent in both orders.
          final gw = HistoryGateway({
            -1: [
              photo(14, album: 8, text: 'newer caption'),
              video(13, album: 8),
              video(12, album: 7),
              photo(11, album: 7, text: 'older caption'),
            ],
          });
          final t = FeedTimeline(gw, [-1], filter: videosOnly);
          await t.loadMore();
          expect(t.items.map((i) => i.head.messageId), [14, 12]);
          expect(t.items[0].parts.map((x) => x.messageId), [13]);
          expect(t.items[0].text, 'newer caption');
          expect(t.items[1].parts.map((x) => x.messageId), [11]);
          expect(t.items[1].text, 'older caption');
        },
      );

      test('off, only the matching parts of the album show', () async {
        final gw = HistoryGateway({
          -1: [photo(12, album: 7, text: 'caption'), video(11, album: 7)],
        });
        final t = FeedTimeline(gw, [
          -1,
        ], filter: videosOnly.copyWith(wholePost: false));
        await t.loadMore();
        expect(t.items.single.head.messageId, 11);
        expect(t.items.single.parts, isEmpty);
        expect(t.items.single.text, '');
        expect(
          t.coveredFrom(-1, 11),
          12,
        ); // reading the video covers the picture

        // The same album, whole: the picture is the head and brings the caption.
        final whole = FeedTimeline(gw, [-1], filter: videosOnly);
        await whole.loadMore();
        expect(whole.items.single.head.messageId, 12);
        expect(whole.items.single.parts.map((x) => x.messageId), [11]);
        expect(whole.items.single.text, 'caption');
      });

      test('an album without a matching part is not shown at all', () async {
        final gw = HistoryGateway({
          -1: [photo(12, album: 7), photo(11, album: 7, text: 'caption')],
        });
        final t = FeedTimeline(gw, [-1], filter: videosOnly);
        await t.loadMore();
        expect(t.items, isEmpty);
      });

      test('live parts join their row whichever arrives first', () async {
        final gw = HistoryGateway({-1: []});
        final t = FeedTimeline(gw, [-1], filter: videosOnly);
        await t.loadMore();
        // The caption comes first: it waits until the video opens the row.
        expect(
          t.apply(PostAdded(photo(21, album: 3, text: 'caption'))),
          isFalse,
        );
        expect(t.items, isEmpty);
        expect(t.apply(PostAdded(video(22, album: 3))), isTrue);
        expect(t.items.single.head.messageId, 22);
        expect(t.items.single.text, 'caption');
        // And the other way round, on a row that is already listed.
        expect(t.apply(PostAdded(video(31, album: 4))), isTrue);
        expect(t.apply(PostAdded(photo(32, album: 4, text: 'later'))), isTrue);
        expect(t.items.first.head.messageId, 32);
        expect(t.items.first.parts.map((x) => x.messageId), [31]);
        expect(t.pendingNew, 0);
      });

      test('parts wait with the post behind the button', () async {
        final gw = HistoryGateway({-1: []});
        final t = FeedTimeline(gw, [-1], filter: videosOnly)..atTop = false;
        await t.loadMore();
        t.apply(PostAdded(photo(41, album: 5, text: 'caption')));
        t.apply(PostAdded(video(42, album: 5)));
        expect(t.pendingNew, 1); // the row, not its parts
        t.releasePending();
        expect(t.items.single.head.messageId, 42);
        expect(t.items.single.text, 'caption');
      });
    });
  });
}
