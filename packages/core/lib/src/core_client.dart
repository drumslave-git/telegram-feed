import 'dart:async';
import 'dart:isolate';

import 'package:telegram_gateway/telegram_gateway.dart';

import 'rule_engine.dart' show MatchEvent;

/// UI-side handle to a [CoreServer]. Implements [TelegramGateway] so screens do not care
/// whether the core runs in the same isolate, a spawned isolate, or the foreground service.
final class CoreClient implements TelegramGateway {
  CoreClient._(this._server) {
    _inbox.listen(_onMessage);
    _server.send({'type': 'hello', 'port': _inbox.sendPort});
  }

  /// Connects to a server port and waits for its `welcome`.
  static Future<CoreClient> connect(SendPort server) async {
    final c = CoreClient._(server);
    await c._welcome.future;
    return c;
  }

  final SendPort _server;
  final _inbox = ReceivePort();
  final _welcome = Completer<void>();
  final _pending = <int, Completer<Object?>>{};
  final _authCtl = StreamController<AuthState>.broadcast();
  final _postCtl = StreamController<PostEvent>.broadcast();
  final _memberCtl = StreamController<ChannelMembershipEvent>.broadcast();
  final _fileCtl = StreamController<FileProgress>.broadcast();
  final _matchCtl = StreamController<MatchEvent>.broadcast();
  final _commentCtl = StreamController<Comment>.broadcast();
  final _pausedCtl = StreamController<bool>.broadcast();
  AuthState _auth = const AuthStarting();
  int _seq = 0;

  /// Last auth state received (synchronous access for widgets).
  AuthState get currentAuthState => _auth;

  void _onMessage(Object? raw) {
    final m = raw as Map<Object?, Object?>;
    switch (m['type']) {
      case 'welcome':
        _auth = decodeAuthState(m['auth'] as Map<Object?, Object?>);
        if (!_welcome.isCompleted) _welcome.complete();
      case 'result':
        _pending.remove(m['id'] as int)?.complete(m['value']);
      case 'error':
        _pending
            .remove(m['id'] as int)
            ?.completeError(
              TelegramException(m['code'] as int, m['message'] as String),
            );
      case 'event':
        final data = m['data'] as Map<Object?, Object?>;
        switch (m['stream']) {
          case 'auth':
            _auth = decodeAuthState(data);
            _authCtl.add(_auth);
          case 'posts':
            _postCtl.add(decodePostEvent(data));
          case 'membership':
            _memberCtl.add(decodeMembership(data));
          case 'files':
            _fileCtl.add(decodeFileProgress(data));
          case 'matches':
            _matchCtl.add(MatchEvent.decode(data));
          case 'paused':
            _pausedCtl.add(data['paused'] as bool);
          case 'comments':
            _commentCtl.add(decodeComment(data));
        }
    }
  }

  Future<Object?> _call(String method, [Map<String, Object?> args = const {}]) {
    final id = _seq++;
    final c = Completer<Object?>();
    _pending[id] = c;
    _server.send({
      'type': 'call',
      'id': id,
      'method': method,
      'args': args,
      'port': _inbox.sendPort,
    });
    return c.future;
  }

  @override
  Stream<AuthState> get authState async* {
    yield _auth;
    yield* _authCtl.stream;
  }

  /// Rule matches evaluated by the core (phase 2).
  Stream<MatchEvent> get matches => _matchCtl.stream;

  /// Pause state changes of rule evaluation.
  Stream<bool> get pausedChanges => _pausedCtl.stream;

  /// Asks the core to re-read rules and watched channels from the database.
  Future<void> refresh() => _call('refresh');

  /// Asks the core to close TDLib and stop its receive pump, and waits for it. Only the
  /// host taking a core down calls this (core handover, ARCHITECTURE 8).
  Future<void> shutdown() async => await _call('shutdown');

  Future<void> setPaused(bool paused) => _call('setPaused', {'paused': paused});

  Future<bool> isPaused() async => (await _call('isPaused')) as bool;

  @override
  Stream<PostEvent> get postEvents => _postCtl.stream;
  @override
  Stream<ChannelMembershipEvent> get membershipEvents => _memberCtl.stream;

  @override
  Future<void> setPhoneNumber(String phone) =>
      _call('setPhoneNumber', {'phone': phone});
  @override
  Future<void> checkCode(String code) => _call('checkCode', {'code': code});
  @override
  Future<void> checkPassword(String password) =>
      _call('checkPassword', {'password': password});
  @override
  Future<void> registerUser({
    required String firstName,
    String lastName = '',
  }) => _call('registerUser', {'firstName': firstName, 'lastName': lastName});
  @override
  Future<void> requestQrCode() => _call('requestQrCode');
  @override
  Future<void> logOut() => _call('logOut');

  @override
  Future<List<Channel>> myChannels() async =>
      ((await _call('myChannels')) as List)
          .map((e) => decodeChannel(e as Map<Object?, Object?>))
          .toList();

  @override
  Future<List<ChatFolder>> chatFolders() async =>
      ((await _call('chatFolders')) as List)
          .map((e) => decodeChatFolder(e as Map<Object?, Object?>))
          .toList();

  @override
  Future<List<Post>> history(
    int chatId, {
    int fromMessageId = 0,
    int limit = 30,
    bool onlyLocal = false,
  }) async => ((await _call('history', {
    'chatId': chatId,
    'fromMessageId': fromMessageId,
    'limit': limit,
    'onlyLocal': onlyLocal,
  })) as List).map((e) => decodePost(e as Map<Object?, Object?>)).toList();

  @override
  Future<List<Post>> historyAfter(
    int chatId, {
    required int afterMessageId,
    int limit = 30,
  }) async => ((await _call('historyAfter', {
    'chatId': chatId,
    'afterMessageId': afterMessageId,
    'limit': limit,
  })) as List).map((e) => decodePost(e as Map<Object?, Object?>)).toList();

  @override
  Future<SearchPage> searchHistory(
    int chatId, {
    String query = '',
    HistoryFilter filter = HistoryFilter.any,
    int fromMessageId = 0,
    int limit = 30,
  }) async => decodeSearchPage(
    (await _call('searchHistory', {
      'chatId': chatId,
      'query': query,
      'filter': filter.name,
      'fromMessageId': fromMessageId,
      'limit': limit,
    })) as Map<Object?, Object?>,
  );

  @override
  Future<int> messageIdByDate(int chatId, int unixDate) async =>
      (await _call('messageIdByDate', {'chatId': chatId, 'unixDate': unixDate}))
          as int;

  @override
  Future<ChannelInfo> channelInfo(int chatId) async => decodeChannelInfo(
    (await _call('channelInfo', {'chatId': chatId})) as Map<Object?, Object?>,
  );

  @override
  Future<void> markViewed(int chatId, List<int> messageIds) =>
      _call('markViewed', {'chatId': chatId, 'messageIds': messageIds});

  @override
  Future<void> saveToSavedMessages(int chatId, List<int> messageIds) => _call(
    'saveToSavedMessages',
    {'chatId': chatId, 'messageIds': messageIds},
  );

  @override
  Future<FileRef> download(FileRef ref, {int priority = 16}) async =>
      decodeFileRef(
        (await _call('download', {
          'ref': encodeFileRef(ref),
          'priority': priority,
        })) as Map<Object?, Object?>,
      );

  @override
  Stream<FileProgress> fileProgress(int fileId) {
    unawaited(_call('watchFile', {'fileId': fileId}));
    return _fileCtl.stream.where((p) => p.fileId == fileId);
  }

  @override
  Future<FileProgress> downloadFrom(
    int fileId, {
    int offset = 0,
    int priority = 32,
  }) async => decodeFileProgress(
    (await _call('downloadFrom', {
      'fileId': fileId,
      'offset': offset,
      'priority': priority,
    })) as Map<Object?, Object?>,
  );

  @override
  Future<int> downloadedPrefix(int fileId, int offset) async =>
      (await _call('downloadedPrefix', {'fileId': fileId, 'offset': offset}))
          as int;

  @override
  Future<void> cancelDownload(int fileId) =>
      _call('cancelDownload', {'fileId': fileId});

  @override
  Future<Thread?> discussion(int chatId, int messageId) async {
    final r = await _call('discussion', {
      'chatId': chatId,
      'messageId': messageId,
    });
    return r == null ? null : decodeThread(r as Map<Object?, Object?>);
  }

  @override
  Future<List<Comment>> threadHistory(
    Thread thread, {
    int fromMessageId = 0,
    int limit = 30,
  }) async => ((await _call('threadHistory', {
    'thread': encodeThread(thread),
    'fromMessageId': fromMessageId,
    'limit': limit,
  })) as List).map((e) => decodeComment(e as Map<Object?, Object?>)).toList();

  @override
  Future<void> reply(Thread thread, String text) =>
      _call('reply', {'thread': encodeThread(thread), 'text': text});

  @override
  Stream<Comment> get comments => _commentCtl.stream;

  @override
  Future<void> closeThread(Thread thread) =>
      _call('closeThread', {'thread': encodeThread(thread)});

  @override
  Future<Post?> pinnedPost(int chatId) async {
    final answer = await _call('pinnedPost', {'chatId': chatId});
    return answer == null ? null : decodePost(answer as Map<Object?, Object?>);
  }

  @override
  Future<Map<String, StickerMedia>> customEmoji(List<String> ids) async {
    final answer = (await _call('customEmoji', {'ids': ids})) as Map;
    return {
      for (final entry in answer.entries)
        entry.key as String:
            decodeMedia(entry.value as Map<Object?, Object?>) as StickerMedia,
    };
  }

  @override
  Future<List<String>> availableReactions(int chatId, int messageId) async =>
      ((await _call('availableReactions', {
        'chatId': chatId,
        'messageId': messageId,
      })) as List).cast<String>();

  @override
  Future<void> react(
    int chatId,
    int messageId,
    String emoji, {
    bool remove = false,
  }) => _call('react', {
    'chatId': chatId,
    'messageId': messageId,
    'emoji': emoji,
    'remove': remove,
  });

  @override
  Future<UserInfo> me() async =>
      decodeUser((await _call('me')) as Map<Object?, Object?>);

  @override
  Future<StorageStats> storageStats() async =>
      decodeStorage((await _call('storageStats')) as Map<Object?, Object?>);

  @override
  Future<StorageStats> clearCache() async =>
      decodeStorage((await _call('clearCache')) as Map<Object?, Object?>);

  /// Detaches from the server; the core keeps running for other clients.
  @override
  Future<void> close() async {
    _server.send({'type': 'bye', 'port': _inbox.sendPort});
    _inbox.close();
    for (final c in _pending.values) {
      c.completeError(const TelegramException(-1, 'client closed'));
    }
    _pending.clear();
    await _authCtl.close();
    await _postCtl.close();
    await _memberCtl.close();
    await _fileCtl.close();
    await _matchCtl.close();
    await _pausedCtl.close();
    await _commentCtl.close();
  }
}
