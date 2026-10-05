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
    this._paused = false,
    this.onPaused,
    this.accounts,
    this.dropAccount,
    this.onMarks,
    this.marksDelay = const Duration(seconds: 1),
    this.onPush,
  }) : _gateway = gateway {
    _port.listen(_onMessage);
    final e = engine;
    e?.quiet = _paused;
    _subscribe();
    if (e != null) {
      _matchSub = e.matches.listen(
        (m) => _broadcast(CoreStream.matches, encodeMatch(m)),
      );
      _marksSub = e.marksChanged.listen((_) {
        _marksTimer ??= Timer(marksDelay, () => unawaited(_saveMarks()));
      });
    }
  }

  TelegramGateway _gateway;
  final void Function(String)? log;

  /// Rule engine fed from the gateway's post events while not paused.
  final RuleEngine? engine;

  /// Re-reads rules and watched channels (the host owns the database).
  final Future<void> Function()? onRefresh;

  /// The servers of the other logged-in accounts this core serves, by account id; the
  /// host asks for them to run those accounts' alerts.
  final Map<int, SendPort> Function()? accounts;

  /// Stops serving another account and closes its TDLib client, so its files may be
  /// deleted: the account is being removed from the device.
  final Future<void> Function(int id)? dropAccount;

  /// Hands TDLib back: closes its client and stops its receive pump, so another core may
  /// take over in this process (core handover, ARCHITECTURE 8). Run once, by [shutdown].
  final Future<void> Function()? onShutdown;
  bool _stopped = false;

  /// Keeps [setPaused] for the next start: the pause is a kill switch, and a restart of
  /// the app or the phone must not undo it.
  final Future<void> Function(bool paused)? onPaused;

  /// Hands a push on to the other accounts this core serves ([handlePush] of each).
  final Future<void> Function(String payload)? onPush;

  /// Keeps the engine's marks ([RuleEngine.marks]) for the next run; called [marksDelay]
  /// after they moved, and once more at [shutdown].
  final Future<void> Function(Map<int, int> marks)? onMarks;
  final Duration marksDelay;
  Timer? _marksTimer;

  /// True once the core has handed TDLib back and stopped serving.
  bool get stopped => _stopped;
  StreamSubscription<RuleMatch>? _matchSub;
  StreamSubscription<PostEvent>? _engineSub;
  StreamSubscription<void>? _marksSub;
  bool _paused;

  bool get paused => _paused;

  /// Attaches the engine to the current gateway. It stays attached through a pause, in
  /// which it looks at posts without matching them.
  void _attachEngine() {
    _engineSub?.cancel();
    _engineSub = null;
    final e = engine;
    if (e != null) _engineSub = e.attach(_gateway.postEvents);
  }

  void setPaused(bool value) {
    if (_paused == value) return;
    _paused = value;
    engine?.quiet = value;
    unawaited(onPaused?.call(value));
    _broadcast(CoreStream.paused, {'paused': value});
  }

  Future<void> _saveMarks() async {
    _marksTimer?.cancel();
    _marksTimer = null;
    final e = engine;
    if (e == null) return;
    try {
      await onMarks?.call(e.marks);
    } on Object catch (err) {
      log?.call('core: rule marks not saved: $err');
    }
  }

  /// Brings the rules up to date with the posts that came while nothing evaluated them
  /// (ARCHITECTURE 6.2): every watched channel whose newest post is past its mark has its
  /// newest [catchUpPosts] posts looked at. The host asks for the first one once its
  /// alerts listen, since a match made earlier would reach no one; from then on the core
  /// also catches up by itself whenever TDLib is logged in and its connection comes back.
  /// One at a time; an ask in the middle of one runs another after it.
  Future<void> catchUp() {
    _catchUpAsked = true;
    if (_catchingUp case final running?) {
      _catchUpAgain = true;
      return running;
    }
    final run = _catchUpOnce().whenComplete(() {
      _catchingUp = null;
      if (_catchUpAgain && !_stopped) {
        _catchUpAgain = false;
        unawaited(catchUp());
      }
    });
    return _catchingUp = run;
  }

  /// A push came (ARCHITECTURE 6.5): TDLib gets it and fetches what it is about, and the
  /// rules catch up. The posts TDLib fetches afterwards come as new posts, and a
  /// connection that comes back catches up again by itself.
  Future<void> handlePush(String payload) async {
    if (_stopped) return;
    if (_gateway case final PushGateway g) await g.processPush(payload);
    await catchUp();
  }

  Future<void>? _catchingUp;
  bool _catchUpAgain = false;
  bool _catchUpAsked = false;

  /// How many of a channel's newest posts a catch-up looks at.
  static const catchUpPosts = 100;

  Future<void> _catchUpOnce() async {
    final e = engine;
    if (e == null || _stopped || _auth is! AuthReady) return;
    final gateway = _gateway;
    var looked = 0;
    for (final chatId in e.watched) {
      if (_stopped || !identical(gateway, _gateway)) return;
      try {
        final state = await gateway.readState(chatId);
        final mark = e.marks[chatId];
        final behind = mark != null && state.lastMessageId > mark;
        final posts = behind
            ? await gateway.history(chatId, limit: catchUpPosts)
            : const <Post>[];
        if (_stopped || !identical(gateway, _gateway)) return;
        e.catchUp(
          chatId,
          posts,
          lastReadMessageId: state.lastReadMessageId,
          lastMessageId: state.lastMessageId,
        );
        if (behind) looked++;
      } on Object catch (err) {
        // Left for the next catch-up; the other channels go on.
        log?.call('core: catch-up of $chatId failed: $err');
      }
    }
    if (looked > 0) log?.call('core: caught up $looked channel(s)');
    await _saveMarks();
  }

  final _port = ReceivePort();
  final _clients = <SendPort>{};
  final _fileSubs = <int, StreamSubscription<FileProgress>>{};
  var _subs = <StreamSubscription<void>>[];
  AuthState _auth = const AuthStarting();

  /// TDLib's connection as the gateway last reported it, for clients that attach later.
  ConnectionStatus _connection = ConnectionStatus.connecting;

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
    // A new login starts from the posts it finds.
    engine?.restoreMarks(const {});
    _auth = const AuthStarting();
    _connection = ConnectionStatus.connecting;
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
        if (_catchUpAsked &&
            s is AuthReady &&
            _connection == ConnectionStatus.ready) {
          unawaited(catchUp());
        }
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
      gateway.commentsGone.listen(
        (g) => _broadcast(CoreStream.commentsGone, encodeCommentsGone(g)),
      ),
      gateway.connection.listen((c) {
        final back = c == ConnectionStatus.ready && _connection != c;
        _connection = c;
        _broadcast(CoreStream.connection, {'status': c.name});
        if (back && _catchUpAsked) unawaited(catchUp());
      }),
      gateway.readUpdates.listen(
        (r) => _broadcast(CoreStream.readStates, encodeReadState(r)),
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
        p.send({
          'type': 'welcome',
          'auth': encodeAuthState(_auth),
          'connection': _connection.name,
        });
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
    await _marksSub?.cancel();
    await _saveMarks();
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
      case 'resendCode':
        await gateway.resendCode();
      case 'countries':
        return [
          for (final c in await gateway.countries(
            language: a['language'] as String? ?? 'en',
          ))
            encodeCountry(c),
        ];
      case 'phoneInfo':
        return encodePhoneInfo(await gateway.phoneInfo(a['digits'] as String));
      case 'setEmailAddress':
        await gateway.setEmailAddress(a['email'] as String);
      case 'checkEmailCode':
        await gateway.checkEmailCode(a['code'] as String);
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
      case 'countViews':
        await gateway.countViews(
          a['chatId'] as int,
          (a['messageIds'] as List).cast<int>(),
        );
      case 'readState':
        return encodeReadState(await gateway.readState(a['chatId'] as int));
      case 'saveToSavedMessages':
        await gateway.saveToSavedMessages(
          a['chatId'] as int,
          (a['messageIds'] as List).cast<int>(),
        );
      case 'deleteFromSavedMessages':
        await gateway.deleteFromSavedMessages(
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
            limit: a['limit'] as int? ?? 0,
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
      case 'catchUp':
        await catchUp();
      case 'registerPush':
        if (gateway case final PushGateway g) {
          await g.registerPush(
            a['token'] as String,
            otherUserIds: (a['otherUserIds'] as List).cast<int>(),
          );
        }
      case 'processPush':
        final payload = a['payload'] as String;
        await handlePush(payload);
        await onPush?.call(payload);
      case 'accounts':
        return accounts?.call() ?? const <int, SendPort>{};
      case 'dropAccount':
        await dropAccount?.call(a['id'] as int);
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
          replyToId: (a['replyToId'] as int?) ?? 0,
        );
      case 'editComment':
        await gateway.editComment(
          decodeThread(a['thread'] as Map<Object?, Object?>),
          a['messageId'] as int,
          a['text'] as String,
        );
      case 'deleteComments':
        await gateway.deleteComments(
          decodeThread(a['thread'] as Map<Object?, Object?>),
          (a['messageIds'] as List).cast<int>(),
        );
      case 'retryComment':
        await gateway.retryComment(
          decodeThread(a['thread'] as Map<Object?, Object?>),
          a['messageId'] as int,
        );
      case 'closeThread':
        await gateway.closeThread(
          decodeThread(a['thread'] as Map<Object?, Object?>),
        );
      case 'similarChannels':
        return (await gateway.similarChannels(a['chatId'] as int))
            .map(encodeChannel)
            .toList();
      case 'archivedChannels':
        return (await gateway.archivedChannels()).map(encodeChannel).toList();
      case 'savedMessages':
        return encodeChannel(await gateway.savedMessages());
      case 'searchThread':
        return encodeCommentPage(
          await gateway.searchThread(
            decodeThread(a['thread'] as Map<Object?, Object?>),
            query: a['query'] as String,
            fromMessageId: a['fromMessageId'] as int,
            limit: a['limit'] as int,
          ),
        );
      case 'threadAround':
        return (await gateway.threadAround(
          decodeThread(a['thread'] as Map<Object?, Object?>),
          a['messageId'] as int,
          newer: a['newer'] as int,
          older: a['older'] as int,
        )).map(encodeComment).toList();
      case 'searchAllChannels':
        final page = await gateway.searchAllChannels(
          query: a['query'] as String,
          filter: HistoryFilter.values.byName(a['filter'] as String),
          offset: a['offset'] as String,
          limit: a['limit'] as int,
          minDate: (a['minDate'] as int?) ?? 0,
          maxDate: (a['maxDate'] as int?) ?? 0,
        );
        return {
          'posts': page.posts.map(encodePost).toList(),
          'totalCount': page.totalCount,
          'nextOffset': page.nextOffset,
        };
      case 'mediaCounts':
        final counts = await gateway.mediaCounts(a['chatId'] as int);
        return {for (final e in counts.entries) e.key.name: e.value};
      case 'markChannelUnread':
        await gateway.markChannelUnread(
          a['chatId'] as int,
          unread: a['unread'] as bool,
        );
      case 'markCommentsViewed':
        await gateway.markCommentsViewed(
          decodeThread(a['thread'] as Map<Object?, Object?>),
          (a['messageIds'] as List).cast<int>(),
        );
      case 'report':
        return encodeReportStep(
          await gateway.report(
            a['chatId'] as int,
            (a['messageIds'] as List).cast<int>(),
            optionId: a['optionId'] as String,
            text: a['text'] as String,
          ),
        );
      case 'mapThumbnail':
        return encodeFileRef(
          await gateway.mapThumbnail(
            (a['lat'] as num).toDouble(),
            (a['lon'] as num).toDouble(),
            width: a['width'] as int,
            height: a['height'] as int,
          ),
        );
      case 'mediaCalendar':
        final days = await gateway.mediaCalendar(
          a['chatId'] as int,
          fromMessageId: a['fromMessageId'] as int,
        );
        return days.map(encodePost).toList();
      case 'pinnedPosts':
        final pinned = await gateway.pinnedPosts(a['chatId'] as int);
        return pinned.map(encodePost).toList();
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
      case 'storageByKind':
        return encodeStorageSlices(await gateway.storageByKind());
      case 'clearCache':
        return encodeStorage(
          await gateway.clearCache(kinds: decodeStorageKinds(a['kinds'])),
        );
      case 'setCacheLimits':
        await gateway.setCacheLimits(
          keepSeconds: a['keepSeconds'] as int,
          maxBytes: a['maxBytes'] as int,
        );
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
    await _marksSub?.cancel();
    _marksTimer?.cancel();
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
