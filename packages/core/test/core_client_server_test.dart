import 'dart:async';
import 'dart:isolate';

import 'package:core/core.dart';
import 'package:rules/rules.dart';
import 'package:telegram_gateway/telegram_gateway.dart';
import 'package:test/test.dart';

/// Scripted gateway: records calls, lets tests push events.
final class FakeGateway implements TelegramGateway {
  final calls = <String>[];
  final authCtl = StreamController<AuthState>.broadcast();
  final postCtl = StreamController<PostEvent>.broadcast();
  final memberCtl = StreamController<ChannelMembershipEvent>.broadcast();
  final fileCtl = StreamController<FileProgress>.broadcast();
  AuthState auth = const AuthWaitPhoneNumber();

  @override
  Stream<AuthState> get authState async* {
    yield auth;
    yield* authCtl.stream;
  }

  @override
  Stream<PostEvent> get postEvents => postCtl.stream;
  @override
  Stream<ChannelMembershipEvent> get membershipEvents => memberCtl.stream;
  @override
  Stream<FileProgress> fileProgress(int fileId) =>
      fileCtl.stream.where((p) => p.fileId == fileId);

  @override
  Future<void> setPhoneNumber(String phone) async => calls.add('phone:$phone');
  @override
  Future<void> checkCode(String code) async {
    if (code == 'bad') throw const TelegramException(400, 'PHONE_CODE_INVALID');
    calls.add('code:$code');
  }

  @override
  Future<void> checkPassword(String password) async => calls.add('pw');
  @override
  Future<void> registerUser({
    required String firstName,
    String lastName = '',
  }) async => calls.add('register:$firstName');
  @override
  Future<void> requestQrCode() async => calls.add('qr');
  @override
  Future<void> logOut() async => calls.add('logout');

  @override
  Future<List<Channel>> myChannels() async => const [
    Channel(
      chatId: -1001,
      title: 'News',
      username: 'news',
      memberCount: 3,
      lastMessageId: 42,
    ),
    Channel(chatId: -1002, title: 'Left', isMember: false),
  ];

  @override
  Future<List<Post>> history(
    int chatId, {
    int fromMessageId = 0,
    int limit = 30,
    bool onlyLocal = false,
  }) async {
    calls.add('history:$chatId:$fromMessageId:$limit:$onlyLocal');
    return [
      Post(
        chatId: chatId,
        messageId: 7,
        date: 1,
        text: 'photo',
        media: const PhotoMedia(
          sizes: [
            FileRef(id: 9, remoteId: 'r', size: 10, width: 100, height: 50),
          ],
        ),
      ),
      Post(chatId: chatId, messageId: 6, date: 0, text: 'text'),
    ];
  }

  @override
  Future<List<Post>> historyAfter(
    int chatId, {
    required int afterMessageId,
    int limit = 30,
  }) async {
    calls.add('after:$chatId:$afterMessageId:$limit');
    return [Post(chatId: chatId, messageId: 9, date: 5, text: 'newer')];
  }

  @override
  Future<SearchPage> searchHistory(
    int chatId, {
    String query = '',
    HistoryFilter filter = HistoryFilter.any,
    int fromMessageId = 0,
    int limit = 30,
  }) async {
    calls.add('search:$chatId:$query:${filter.name}:$fromMessageId:$limit');
    return SearchPage(
      posts: [Post(chatId: chatId, messageId: 5, date: 3, text: 'hit')],
      totalCount: 12,
      nextFromMessageId: 5,
    );
  }

  @override
  Future<int> messageIdByDate(int chatId, int unixDate) async {
    calls.add('byDate:$chatId:$unixDate');
    return 77;
  }

  @override
  Future<ChannelInfo> channelInfo(int chatId) async {
    calls.add('info:$chatId');
    return ChannelInfo(
      chatId: chatId,
      description: 'About',
      memberCount: 9,
      inviteLink: 'https://t.me/+x',
      bigPhoto: const FileRef(id: 3, remoteId: 'b', size: 4),
    );
  }

  @override
  Future<void> markViewed(int chatId, List<int> messageIds) async =>
      calls.add('viewed:$chatId:${messageIds.join(",")}');

  @override
  Future<void> saveToSavedMessages(int chatId, List<int> messageIds) async =>
      calls.add('saved:$chatId:${messageIds.join(",")}');

  @override
  Future<FileRef> download(FileRef ref, {int priority = 16}) async {
    calls.add('download:${ref.id}:$priority');
    fileCtl.add(FileProgress(fileId: ref.id, downloaded: 5, total: 10));
    fileCtl.add(
      FileProgress(fileId: ref.id, downloaded: 10, total: 10, localPath: '/x'),
    );
    return ref.copyWith(localPath: '/x');
  }

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
  Future<void> close() async => calls.add('close');

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

void main() {
  group('in-process server and client', () {
    late FakeGateway gw;
    late CoreServer server;
    late CoreClient client;

    setUp(() async {
      gw = FakeGateway();
      server = CoreServer(gw);
      client = await CoreClient.connect(server.sendPort);
    });

    tearDown(() async {
      await client.close();
      await server.close();
    });

    test('welcome carries the current auth state', () {
      expect(client.currentAuthState, isA<AuthWaitPhoneNumber>());
    });

    test('calls, results and typed errors round-trip', () async {
      await client.setPhoneNumber('+1');
      expect(gw.calls, ['phone:+1']);
      await expectLater(
        client.checkCode('bad'),
        throwsA(isA<TelegramException>().having((e) => e.code, 'code', 400)),
      );
      final channels = await client.myChannels();
      expect(channels.map((c) => c.title), ['News', 'Left']);
      expect(channels.first.username, 'news');
      expect(channels.first.lastMessageId, 42);
      expect(channels.last.isMember, isFalse);

      final posts = await client.history(
        -1001,
        fromMessageId: 9,
        limit: 2,
        onlyLocal: true,
      );
      expect(gw.calls.last, 'history:-1001:9:2:true');
      expect(posts.map((p) => p.messageId), [7, 6]);
      expect((posts.first.media as PhotoMedia).sizes.single.width, 100);

      await client.markViewed(-1001, [7, 6]);
      expect(gw.calls.last, 'viewed:-1001:7,6');

      await client.saveToSavedMessages(-1001, [7, 6]);
      expect(gw.calls.last, 'saved:-1001:7,6');

      expect(
        (await client.historyAfter(-1001, afterMessageId: 7)).single.messageId,
        9,
      );
      expect(gw.calls.last, 'after:-1001:7:30');

      final page = await client.searchHistory(
        -1001,
        query: 'rain',
        filter: HistoryFilter.photoAndVideo,
        fromMessageId: 9,
        limit: 5,
      );
      expect(gw.calls.last, 'search:-1001:rain:photoAndVideo:9:5');
      expect(page.posts.single.text, 'hit');
      expect(page.totalCount, 12);
      expect(page.isLast, isFalse);

      expect(await client.messageIdByDate(-1001, 1700), 77);
      expect(gw.calls.last, 'byDate:-1001:1700');

      final info = await client.channelInfo(-1001);
      expect(info.description, 'About');
      expect(info.memberCount, 9);
      expect(info.inviteLink, 'https://t.me/+x');
      expect(info.bigPhoto?.id, 3);
    });

    test('events are forwarded', () async {
      final auth = <AuthState>[];
      final posts = <PostEvent>[];
      final members = <ChannelMembershipEvent>[];
      final s1 = client.authState.listen(auth.add);
      final s2 = client.postEvents.listen(posts.add);
      final s3 = client.membershipEvents.listen(members.add);
      gw.authCtl.add(const AuthReady());
      gw.postCtl.add(const PostsDeleted(chatId: -1001, messageIds: [1, 2]));
      gw.memberCtl.add(
        const ChannelMembershipEvent(chatId: -1001, isMember: false),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await s1.cancel();
      await s2.cancel();
      await s3.cancel();
      expect(auth.first, isA<AuthWaitPhoneNumber>()); // replayed
      expect(auth.last, isA<AuthReady>());
      expect((posts.single as PostsDeleted).messageIds, [1, 2]);
      expect(members.single.isMember, isFalse);
    });

    test('replaceGateway keeps clients and switches event sources', () async {
      final auth = <AuthState>[];
      final sub = client.authState.listen(auth.add);
      final next = FakeGateway()..auth = const AuthWaitPhoneNumber();
      await server.replaceGateway(next);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(gw.calls, contains('close'));
      // Replayed current state, then the reset, then the new gateway's state.
      expect(auth.map((s) => s.runtimeType).toList(), [
        AuthWaitPhoneNumber,
        AuthStarting,
        AuthWaitPhoneNumber,
      ]);
      await client.setPhoneNumber('+2');
      expect(next.calls, ['phone:+2']);
      expect(gw.calls, isNot(contains('phone:+2')));
      await sub.cancel();
    });

    test('shutdown hands TDLib back, answers, then stops serving', () async {
      var handedBack = 0;
      final gw2 = FakeGateway();
      final stopping = CoreServer(gw2, onShutdown: () async => handedBack++);
      final other = await CoreClient.connect(stopping.sendPort);
      final events = <PostEvent>[];
      final sub = other.postEvents.listen(events.add);
      await Future<void>.delayed(Duration.zero);

      // The answer comes before the port goes, so the caller knows TDLib is free.
      await other.shutdown();
      expect(handedBack, 1);
      expect(stopping.stopped, isTrue);

      // Nothing is served afterwards, and the gateway's events no longer reach anyone.
      gw2.postCtl.add(
        const PostAdded(Post(chatId: -1, messageId: 1, date: 1, text: 'x')),
      );
      await expectLater(
        other.refresh().timeout(const Duration(milliseconds: 200)),
        throwsA(isA<TimeoutException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(events, isEmpty);

      await stopping.shutdown(); // idempotent
      expect(handedBack, 1);
      await sub.cancel();
      await other.close();
    });

    test('download streams progress then completes', () async {
      final progress = <FileProgress>[];
      final sub = client.fileProgress(9).listen(progress.add);
      await Future<void>.delayed(Duration.zero);
      final ref = await client.download(
        const FileRef(id: 9, remoteId: 'r', size: 10),
        priority: 4,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await sub.cancel();
      expect(ref.localPath, '/x');
      expect(gw.calls.last, 'download:9:4');
      expect(progress.map((p) => p.downloaded), [5, 10]);
    });
  });

  test('rule matches are broadcast; pause detaches; refresh reloads', () async {
    final gw = FakeGateway();
    final engine = RuleEngine()
      ..update(
        rules: [
          RuleSpec(
            id: 1,
            name: 'hi',
            condition: RuleParser.parse('hello'),
            priority: RulePriority.urgent,
            readAloud: true,
          ),
        ],
        watched: {-1},
      );
    var refreshed = 0;
    final server = CoreServer(
      gw,
      engine: engine,
      onRefresh: () async => refreshed++,
    );
    final client = await CoreClient.connect(server.sendPort);
    final got = <MatchEvent>[];
    final paused = <bool>[];
    final s1 = client.matches.listen(got.add);
    final s2 = client.pausedChanges.listen(paused.add);

    gw.postCtl.add(
      PostAdded(Post(chatId: -1, messageId: 1, date: 1, text: 'hello there')),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(got.single.ruleNames, ['hi']);
    expect(got.single.priority, RulePriority.urgent);
    expect(got.single.readAloud, isTrue);
    expect(got.single.post.messageId, 1);

    await client.setPaused(true);
    expect(await client.isPaused(), isTrue);
    gw.postCtl.add(
      PostAdded(Post(chatId: -1, messageId: 2, date: 1, text: 'hello again')),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(got.length, 1); // paused: not evaluated
    await client.setPaused(false);
    gw.postCtl.add(
      PostAdded(Post(chatId: -1, messageId: 3, date: 1, text: 'hello 3')),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(got.length, 2);
    expect(paused, [true, false]);

    await client.refresh();
    expect(refreshed, 1);

    await s1.cancel();
    await s2.cancel();
    await client.close();
    await server.close();
    await engine.close();
  });

  test('server in another isolate: maps cross the port', () async {
    final reply = ReceivePort();
    final iso = await Isolate.spawn(_serveFake, reply.sendPort);
    final port = await reply.first as SendPort;
    final client = await CoreClient.connect(port);
    expect(client.currentAuthState, isA<AuthWaitPhoneNumber>());
    final posts = await client.history(-1001);
    expect(posts.length, 2);
    expect(posts.first.media, isA<PhotoMedia>());
    await client.close();
    iso.kill();
  });
}

void _serveFake(SendPort reply) {
  final server = CoreServer(FakeGateway());
  reply.send(server.sendPort);
}
