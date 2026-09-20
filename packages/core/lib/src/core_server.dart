import 'dart:async';
import 'dart:isolate';

import 'package:telegram_gateway/telegram_gateway.dart';

import 'protocol.dart';
import 'rule_engine.dart';

/// Wire form of a [RuleMatch] (post plus what to do with it).
Map<String, Object?> encodeMatch(RuleMatch m) =>
    MatchEvent.fromMatch(m).encode();

/// Serves a [TelegramGateway] to any number of [CoreClient]s over ports. Runs in the core
/// isolate.
final class CoreServer {
  CoreServer(
    TelegramGateway gateway, {
    this.log,
    this.engine,
    this.onRefresh,
    this.onShutdown,
  }) : _gateway = gateway {
    _port.listen(_onMessage);
    _subscribe();
    final e = engine;
    if (e != null) {
      _matchSub = e.matches.listen(
        (m) => _broadcast(CoreStream.matches, encodeMatch(m)),
      );
    }
  }

  TelegramGateway _gateway;
  final void Function(String)? log;

  /// Rule engine fed from the gateway's post events while not paused.
  final RuleEngine? engine;

  /// Re-reads rules and watched channels (the host owns the database).
  final Future<void> Function()? onRefresh;

  /// Hands TDLib back: closes its client and stops its receive pump, so another core may
  /// take over in this process (core handover, ARCHITECTURE 8). Run once, by [shutdown].
  final Future<void> Function()? onShutdown;
  bool _stopped = false;

  /// True once the core has handed TDLib back and stopped serving.
  bool get stopped => _stopped;
  StreamSubscription<RuleMatch>? _matchSub;
  StreamSubscription<PostEvent>? _engineSub;
  bool _paused = false;

  bool get paused => _paused;

  /// Attaches the engine to the current gateway unless paused.
  void _attachEngine() {
    _engineSub?.cancel();
    _engineSub = null;
    final e = engine;
    if (e != null && !_paused) _engineSub = e.attach(_gateway.postEvents);
  }

  void setPaused(bool value) {
    if (_paused == value) return;
    _paused = value;
    _attachEngine();
    _broadcast(CoreStream.paused, {'paused': value});
  }

  final _port = ReceivePort();
  final _clients = <SendPort>{};
  final _fileSubs = <int, StreamSubscription<FileProgress>>{};
  var _subs = <StreamSubscription<void>>[];
  AuthState _auth = const AuthStarting();

  TelegramGateway get gateway => _gateway;

  /// Swaps in a fresh gateway (after TDLib closed its client on logout). Clients keep their
  /// port and simply see the new gateway's auth states; the old gateway is closed.
  Future<void> replaceGateway(TelegramGateway next) async {
    for (final s in _subs) {
      await s.cancel();
    }
    for (final s in _fileSubs.values) {
      await s.cancel();
    }
    _fileSubs.clear();
    final old = _gateway;
    _gateway = next;
    _auth = const AuthStarting();
    _broadcast(CoreStream.auth, encodeAuthState(_auth));
    _subscribe();
    await old.close();
  }

  void _subscribe() {
    _attachEngine();
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
      gateway.comments.listen(
        (c) => _broadcast(CoreStream.comments, encodeComment(c)),
      ),
      gateway.connection.listen(
        (c) => _broadcast(CoreStream.connection, {'status': c.name}),
      ),
    ];
  }

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
          // The caller waits for this answer, so the port only goes after it is sent.
          if (_stopped) _port.close();
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

  /// Stops serving and gives TDLib back through [onShutdown]. Idempotent.
  Future<void> shutdown() async {
    if (_stopped) return;
    _stopped = true;
    await _matchSub?.cancel();
    await _engineSub?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    _subs = [];
    for (final s in _fileSubs.values) {
      await s.cancel();
    }
    _fileSubs.clear();
    _clients.clear();
    await onShutdown?.call();
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
      case 'chatFolders':
        return (await gateway.chatFolders()).map(encodeChatFolder).toList();
      case 'history':
        final posts = await gateway.history(
          a['chatId'] as int,
          fromMessageId: a['fromMessageId'] as int,
          limit: a['limit'] as int,
          onlyLocal: a['onlyLocal'] as bool,
        );
        return posts.map(encodePost).toList();
      case 'historyAfter':
        final newer = await gateway.historyAfter(
          a['chatId'] as int,
          afterMessageId: a['afterMessageId'] as int,
          limit: a['limit'] as int,
        );
        return newer.map(encodePost).toList();
      case 'searchHistory':
        return encodeSearchPage(
          await gateway.searchHistory(
            a['chatId'] as int,
            query: a['query'] as String,
            filter: HistoryFilter.values.byName(a['filter'] as String),
            fromMessageId: a['fromMessageId'] as int,
            limit: a['limit'] as int,
          ),
        );
      case 'messageIdByDate':
        return gateway.messageIdByDate(
          a['chatId'] as int,
          a['unixDate'] as int,
        );
      case 'channelInfo':
        return encodeChannelInfo(await gateway.channelInfo(a['chatId'] as int));
      case 'markViewed':
        await gateway.markViewed(
          a['chatId'] as int,
          (a['messageIds'] as List).cast<int>(),
        );
      case 'saveToSavedMessages':
        await gateway.saveToSavedMessages(
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
      case 'downloadFrom':
        final fileId = a['fileId'] as int;
        _watchFile(fileId);
        return encodeFileProgress(
          await gateway.downloadFrom(
            fileId,
            offset: a['offset'] as int,
            priority: a['priority'] as int,
          ),
        );
      case 'downloadedPrefix':
        return gateway.downloadedPrefix(a['fileId'] as int, a['offset'] as int);
      case 'cancelDownload':
        await gateway.cancelDownload(a['fileId'] as int);
      case 'watchFile':
        _watchFile(a['fileId'] as int);
      case 'refresh':
        await onRefresh?.call();
      case 'shutdown':
        await shutdown();
      case 'setPaused':
        setPaused(a['paused'] as bool);
      case 'isPaused':
        return _paused;
      case 'discussion':
        final t = await gateway.discussion(
          a['chatId'] as int,
          a['messageId'] as int,
        );
        return t == null ? null : encodeThread(t);
      case 'threadHistory':
        final list = await gateway.threadHistory(
          decodeThread(a['thread'] as Map<Object?, Object?>),
          fromMessageId: a['fromMessageId'] as int,
          limit: a['limit'] as int,
        );
        return list.map(encodeComment).toList();
      case 'reply':
        await gateway.reply(
          decodeThread(a['thread'] as Map<Object?, Object?>),
          a['text'] as String,
        );
      case 'closeThread':
        await gateway.closeThread(
          decodeThread(a['thread'] as Map<Object?, Object?>),
        );
      case 'pinnedPost':
        final pinned = await gateway.pinnedPost(a['chatId'] as int);
        return pinned == null ? null : encodePost(pinned);
      case 'customEmoji':
        return {
          for (final e in (await gateway.customEmoji(
            (a['ids'] as List).cast<String>(),
          )).entries)
            e.key: encodeMedia(e.value),
        };
      case 'availableReactions':
        return gateway.availableReactions(
          a['chatId'] as int,
          a['messageId'] as int,
        );
      case 'react':
        await gateway.react(
          a['chatId'] as int,
          a['messageId'] as int,
          a['emoji'] as String,
          remove: a['remove'] as bool,
        );
      case 'me':
        return encodeUser(await gateway.me());
      case 'storageStats':
        return encodeStorage(await gateway.storageStats());
      case 'clearCache':
        return encodeStorage(await gateway.clearCache());
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
    await _matchSub?.cancel();
    await _engineSub?.cancel();
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
