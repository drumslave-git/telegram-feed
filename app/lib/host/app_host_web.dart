import 'dart:async';

import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/wasm.dart';
import 'package:flutter/foundation.dart';
import 'package:telegram_gateway/tdweb.dart';
import 'package:telegram_gateway/telegram_gateway.dart';
import 'package:web/web.dart' as web;

import '../credentials.dart';
import '../notifications/open_post.dart';
import '../service/notification_plan.dart';
import '../service/tts_service.dart';
import '../web/browser_notifier.dart';
import 'app_host.dart';

void platformInit() {}

Future<AppHost> startAppHost() => WebHost.start();

Future<void> attachLaunchHandlers(AppHost host) async {}

/// Web host (ARCHITECTURE section 8, web): TDLib runs as tdweb in a Web Worker, the app
/// database on drift's sqlite3 WASM, and the rule engine in the page. Nothing runs while
/// no tab is open. Matches become browser notifications and read-aloud through the Web
/// Speech API (flutter_tts's web implementation).
final class WebHost implements AppHost {
  WebHost._(this.db, this._gateway);

  static Future<WebHost> start() async {
    final db = AppDatabase(await _openDatabase());
    final transport = TdwebTransport.create();
    final gateway = TdlibGateway(
      transport,
      TdlibConfig(
        apiId: tgApiId,
        apiHash: tgApiHash,
        databaseDirectory: '/db',
        filesDirectory: '/db/files',
        useTestDc: tgTestDc,
        deviceModel: 'Web',
        systemVersion: web.window.navigator.platform,
      ),
      log: (s) => debugPrint('core: $s'),
      localFileUrl: transport.objectUrl,
    );
    final host = WebHost._(db, gateway);
    await host._startRules();
    host._reloadWhenClosed();
    return host;
  }

  /// Storage order for drift. tdweb keeps one live tab per instance anyway, so the
  /// multi-tab safety of the SharedWorker storages buys nothing, and dedicated-worker
  /// storages come first: some embedded browsers cannot `fetch` from a SharedWorker at all.
  static const _storagePreference = [
    WasmStorageImplementation.opfsLocks,
    WasmStorageImplementation.unsafeIndexedDb,
    WasmStorageImplementation.opfsShared,
    WasmStorageImplementation.sharedIndexedDb,
    WasmStorageImplementation.inMemory,
  ];

  /// Not named 'telegram_feed': tdweb opens an IndexedDB database of its instance name
  /// for its files, and drift's stores must not collide with it.
  static Future<DatabaseConnection> _openDatabase() async {
    const name = 'telegram_feed_app';
    final probe = await WasmDatabase.probe(
      sqlite3Uri: Uri.parse('sqlite3.wasm'),
      driftWorkerUri: Uri.parse('drift_worker.js'),
      databaseName: name,
    );
    // An existing database stays in the storage API it was created with.
    final existing = {
      for (final (api, dbName) in probe.existingDatabases)
        if (dbName == name) api,
    };
    final choice = _storagePreference.firstWhere(
      (s) =>
          probe.availableStorages.contains(s) &&
          (existing.isEmpty || existing.contains(s.storageApi)),
      orElse: () => WasmStorageImplementation.inMemory,
    );
    debugPrint(
      'web: db storage $choice (available ${probe.availableStorages}, '
      'missing ${probe.missingFeatures})',
    );
    return probe.open(choice, name);
  }

  @override
  final AppDatabase db;
  final TdlibGateway _gateway;
  final _engine = RuleEngine();
  final _notifier = BrowserNotifier();
  TtsService? _tts;
  Map<int, String> _titles = const {};
  final _subs = <StreamSubscription<void>>[];

  @override
  TelegramGateway get gateway => _gateway;

  @override
  bool get runningInService => false;

  @override
  Future<bool> get isBatteryExempt async => true;

  @override
  Future<void> requestBatteryExemption() async {}

  Future<void> _startRules() async {
    await _notifier.init();
    final tts = TtsService(
      db: db,
      speaker: FlutterTtsSpeaker(
        detectLanguage: (text) async => guessLanguageByScript(text),
      ),
    );
    try {
      await tts.init();
      _tts = tts;
    } catch (e) {
      debugPrint('tts unavailable: $e');
    }

    Future<void> refresh() async {
      final specs = <RuleSpec>[];
      for (final r in await db.allRules()) {
        try {
          specs.add(RuleSpec.fromRow(r));
        } on FormatException catch (err) {
          debugPrint('rule ${r.id} skipped: $err');
        }
      }
      final watched = await db.allWatched();
      _titles = {for (final w in watched) w.chatId: w.title};
      _engine.update(
        rules: specs,
        watched: {for (final w in watched) w.chatId},
      );
    }

    await refresh();
    _subs.add(db.watchRules().listen((_) => refresh()));
    _subs.add(db.watchSourceChanges().listen((_) => refresh()));
    _subs.add(_engine.attach(_gateway.postEvents));
    _subs.add(_engine.matches.listen(_onMatch));
    _subs.add(
      _engine.cancellations.listen(
        (e) => _notifier.cancel(e.chatId, e.messageIds),
      ),
    );
  }

  Future<void> _onMatch(RuleMatch m) async {
    final title = _titles[m.post.chatId] ?? '';
    final plan = NotificationPlan.forMatch(
      MatchEvent.fromMatch(m),
      channelTitle: title,
    );
    final ref = PostRef(m.post.chatId, m.post.messageId);
    await _notifier.show(plan, onTap: () => openPost(this, ref));
    if (m.readAloud) {
      _tts?.enqueue(
        TtsItem(
          text: m.post.text,
          channelTitle: title,
          key: (ref.chatId, ref.messageId),
        ),
      );
    }
  }

  /// After a logout TDLib closes its client; tdweb cannot reopen one, so the page reloads
  /// and starts a fresh client (TDLib deleted its database as part of `logOut`).
  void _reloadWhenClosed() {
    _subs.add(
      _gateway.authState.listen((s) {
        if (s is AuthClosed) web.window.location.reload();
      }),
    );
  }

  @override
  Future<void> logOutAndWipe() async {
    await db.wipe();
    await _gateway.logOut();
  }

  @override
  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _tts?.dispose();
    await _engine.close();
    await _gateway.close();
    await db.close();
  }
}
