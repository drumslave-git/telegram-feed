import 'dart:async';
import 'dart:isolate';

import 'package:telegram_gateway/telegram_gateway.dart';

import 'core_server.dart' show MatchEvent;

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
  Future<void> markViewed(int chatId, List<int> messageIds) =>
      _call('markViewed', {'chatId': chatId, 'messageIds': messageIds});

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
  }
}
