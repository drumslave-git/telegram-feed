import 'dart:async';
import 'dart:isolate';

import 'package:telegram_gateway/telegram_gateway.dart';

import 'protocol.dart';

/// Serves a [TelegramGateway] to any number of [CoreClient]s over ports. Runs wherever the
/// gateway lives: the core isolate on Android, the main isolate on the web.
final class CoreServer {
  CoreServer(this.gateway, {this.log}) {
    _port.listen(_onMessage);
    _subs = [
      gateway.authState.listen((s) {
        _auth = s;
        _broadcast(CoreStream.auth, encodeAuthState(s));
      }),
      gateway.postEvents.listen(
        (e) => _broadcast(CoreStream.posts, encodePostEvent(e)),
      ),
      gateway.membershipEvents.listen(
        (e) => _broadcast(CoreStream.membership, encodeMembership(e)),
      ),
    ];
  }

  final TelegramGateway gateway;
  final void Function(String)? log;
  final _port = ReceivePort();
  final _clients = <SendPort>{};
  final _fileSubs = <int, StreamSubscription<FileProgress>>{};
  late final List<StreamSubscription<void>> _subs;
  AuthState _auth = const AuthStarting();

  /// Hand this to clients (directly, or through `IsolateNameServer`).
  SendPort get sendPort => _port.sendPort;

  void _broadcast(CoreStream stream, Map<String, Object?> data) {
    final msg = {'type': 'event', 'stream': stream.name, 'data': data};
    for (final c in _clients) {
      c.send(msg);
    }
  }

  Future<void> _onMessage(Object? raw) async {
    final m = raw as Map<Object?, Object?>;
    switch (m['type']) {
      case 'hello':
        final p = m['port'] as SendPort;
        _clients.add(p);
        p.send({'type': 'welcome', 'auth': encodeAuthState(_auth)});
      case 'bye':
        _clients.remove(m['port'] as SendPort);
      case 'call':
        final reply = m['port'] as SendPort;
        final id = m['id'] as int;
        try {
          final value = await _call(
            m['method'] as String,
            (m['args'] as Map<Object?, Object?>?) ?? const {},
          );
          reply.send({'type': 'result', 'id': id, 'value': value});
        } on TelegramException catch (e) {
          reply.send({
            'type': 'error',
            'id': id,
            'code': e.code,
            'message': e.message,
          });
        } catch (e) {
          reply.send({'type': 'error', 'id': id, 'code': -1, 'message': '$e'});
        }
      default:
        log?.call('core: unknown message ${m['type']}');
    }
  }

  Future<Object?> _call(String method, Map<Object?, Object?> a) async {
    switch (method) {
      case 'setPhoneNumber':
        await gateway.setPhoneNumber(a['phone'] as String);
      case 'checkCode':
        await gateway.checkCode(a['code'] as String);
      case 'checkPassword':
        await gateway.checkPassword(a['password'] as String);
      case 'registerUser':
        await gateway.registerUser(
          firstName: a['firstName'] as String,
          lastName: a['lastName'] as String,
        );
      case 'requestQrCode':
        await gateway.requestQrCode();
      case 'logOut':
        await gateway.logOut();
      case 'myChannels':
        return (await gateway.myChannels()).map(encodeChannel).toList();
      case 'history':
        final posts = await gateway.history(
          a['chatId'] as int,
          fromMessageId: a['fromMessageId'] as int,
          limit: a['limit'] as int,
          onlyLocal: a['onlyLocal'] as bool,
        );
        return posts.map(encodePost).toList();
      case 'markViewed':
        await gateway.markViewed(
          a['chatId'] as int,
          (a['messageIds'] as List).cast<int>(),
        );
      case 'download':
        final ref = decodeFileRef(a['ref'] as Map<Object?, Object?>);
        _watchFile(ref.id);
        final done = await gateway.download(
          ref,
          priority: a['priority'] as int,
        );
        return encodeFileRef(done);
      case 'watchFile':
        _watchFile(a['fileId'] as int);
      default:
        throw TelegramException(-1, 'unknown method $method');
    }
    return null;
  }

  /// Forwards progress for a file until it completes.
  void _watchFile(int fileId) {
    if (_fileSubs.containsKey(fileId)) return;
    _fileSubs[fileId] = gateway.fileProgress(fileId).listen((p) {
      _broadcast(CoreStream.files, encodeFileProgress(p));
      if (p.isComplete) {
        _fileSubs.remove(fileId)?.cancel();
      }
    });
  }

  Future<void> close() async {
    for (final s in _subs) {
      await s.cancel();
    }
    for (final s in _fileSubs.values) {
      await s.cancel();
    }
    _port.close();
    await gateway.close();
  }
}
