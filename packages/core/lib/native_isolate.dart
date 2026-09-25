/// Core isolate for native platforms: TDLib over FFI, served through [CoreServer].
///
/// Phase 1: spawned by the UI with [spawnCoreIsolate]. Phase 2: spawned by the foreground
/// service's task handler with the same [coreIsolateMain]. The host that spawns it registers
/// the returned port with `IsolateNameServer` under [corePortName] (this package is pure Dart
/// and cannot import `dart:ui`), and UI engines look it up instead of spawning.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:app_db/app_db.dart';
import 'package:fake_telegram/fake_telegram.dart';
import 'package:telegram_gateway/tdlib_ffi.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'src/core_server.dart';
import 'src/feed_filter.dart';
import 'src/protocol.dart';
import 'src/rule_engine.dart';

export 'src/protocol.dart' show corePortName;

/// Everything the core isolate needs to start; only sendable values.
final class CoreBootstrap {
  const CoreBootstrap({
    required this.apiId,
    required this.apiHash,
    required this.databaseDirectory,
    required this.filesDirectory,
    this.appDatabasePath,
    this.useTestDc = false,
    this.deviceModel = 'Android',
    this.systemVersion = '',
    this.applicationVersion = '0.1.0',
    this.libraryPath = 'libtdjson.so',
    this.logVerbosity = 1,
    this.fakeMediaDirectory,
    this.replyTo,
  });
  final int apiId;
  final String apiHash;
  final String databaseDirectory;
  final String filesDirectory;

  /// Path of the app's SQLite file; when set, the core runs the rule engine on it.
  final String? appDatabasePath;
  final bool useTestDc;
  final String deviceModel;
  final String systemVersion;
  final String applicationVersion;
  final String libraryPath;
  final int logVerbosity;

  /// When set, the core serves a [FakeTelegram] with the media in this directory instead
  /// of TDLib: the fake build.
  final String? fakeMediaDirectory;

  /// Receives the server's `SendPort` once the core is up.
  final SendPort? replyTo;
}

/// Isolate entry point. Sends the server port to [CoreBootstrap.replyTo].
///
/// The isolate lives for the whole process: `td_receive` may only ever be polled by one
/// thread, so a logout does not respawn anything. When TDLib closes its client
/// ([AuthClosed]) a new client and gateway are created here and swapped into the server.
@pragma('vm:entry-point')
Future<void> coreIsolateMain(CoreBootstrap b) async {
  RuleEngine? engine;
  Future<void> Function()? refresh;
  AppDatabase? appDb;
  final dbPath = b.appDatabasePath;
  if (dbPath != null) {
    final db = appDb = AppDatabase(appDatabaseFile(File(dbPath)));
    final e = engine = RuleEngine();
    refresh = () async {
      final rows = await db.allRules();
      final specs = <RuleSpec>[];
      for (final r in rows) {
        try {
          specs.add(RuleSpec.fromRow(r));
        } on FormatException catch (err) {
          print('core: rule ${r.id} skipped: $err'); // ignore: avoid_print
        }
      }
      e.update(
        rules: specs,
        feeds: {
          for (final entry in (await db.feedsForRules()).entries)
            entry.key: RuleFeed(
              entry.value.chats,
              FeedFilter.decode(entry.value.filterJson),
            ),
        },
      );
    };
    await refresh();
  }
  late final CoreServer server;
  var closing = false;
  server = CoreServer(
    await _newGateway(b),
    log: (s) => print(s), // ignore: avoid_print
    engine: engine,
    onRefresh: refresh,
    paused: await appDb?.setting(SettingKeys.rulesPaused) == 'true',
    onPaused: (p) async {
      await appDb?.setSetting(SettingKeys.rulesPaused, p ? 'true' : 'false');
    },
    onShutdown: () async {
      // Hand TDLib back: close the client so it drops the database lock, then stop the
      // receive pump, so the next core in this process can start one of its own.
      closing = true;
      final gateway = server.gateway;
      if (gateway is TdlibGateway) {
        await gateway.closeAndWait();
      } else {
        await gateway.close();
      }
      await FfiTransport.stopReceiving();
      print('core: handed TDLib back'); // ignore: avoid_print
    },
  );
  _watchForClose(server, b, () => closing);
  b.replyTo?.send(server.sendPort);
}

Future<TelegramGateway> _newGateway(CoreBootstrap b) async {
  final fake = b.fakeMediaDirectory;
  if (fake != null) return FakeTelegram(mediaDirectory: fake);
  final transport = await FfiTransport.create(
    libraryPath: b.libraryPath,
    logVerbosity: b.logVerbosity,
  );
  return TdlibGateway(
    transport,
    TdlibConfig(
      apiId: b.apiId,
      apiHash: b.apiHash,
      databaseDirectory: b.databaseDirectory,
      filesDirectory: b.filesDirectory,
      useTestDc: b.useTestDc,
      deviceModel: b.deviceModel,
      systemVersion: b.systemVersion,
      applicationVersion: b.applicationVersion,
    ),
    log: (s) => print('core: $s'), // ignore: avoid_print
  );
}

void _watchForClose(
  CoreServer server,
  CoreBootstrap b,
  bool Function() closing,
) {
  late StreamSubscription<AuthState> sub;
  sub = server.gateway.authState.listen((s) async {
    if (s is! AuthClosed) return;
    await sub.cancel();
    // A close during the handover is the end of this core, not a logout to recover from.
    if (closing()) return;
    await server.replaceGateway(await _newGateway(b));
    _watchForClose(server, b, closing);
  });
}

/// Spawns the core isolate and returns its server port.
Future<SendPort> spawnCoreIsolate(CoreBootstrap bootstrap) async {
  final reply = ReceivePort();
  await Isolate.spawn(
    coreIsolateMain,
    CoreBootstrap(
      apiId: bootstrap.apiId,
      apiHash: bootstrap.apiHash,
      databaseDirectory: bootstrap.databaseDirectory,
      filesDirectory: bootstrap.filesDirectory,
      appDatabasePath: bootstrap.appDatabasePath,
      useTestDc: bootstrap.useTestDc,
      deviceModel: bootstrap.deviceModel,
      systemVersion: bootstrap.systemVersion,
      applicationVersion: bootstrap.applicationVersion,
      libraryPath: bootstrap.libraryPath,
      logVerbosity: bootstrap.logVerbosity,
      fakeMediaDirectory: bootstrap.fakeMediaDirectory,
      replyTo: reply.sendPort,
    ),
    debugName: 'core',
  );
  final port = await reply.first as SendPort;
  reply.close();
  return port;
}
