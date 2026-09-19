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
import 'package:drift/native.dart';
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
  final dbPath = b.appDatabasePath;
  if (dbPath != null) {
    final db = AppDatabase(NativeDatabase(File(dbPath)));
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
        watched: {for (final w in await db.allWatched()) w.chatId},
        filters: {
          for (final entry in (await db.filtersByChat()).entries)
            entry.key: [
              for (final json in entry.value) FeedFilter.decode(json),
            ],
        },
      );
    };
    await refresh();
  }
  final server = CoreServer(
    await _newGateway(b),
    log: (s) => print(s), // ignore: avoid_print
    engine: engine,
    onRefresh: refresh,
  );
  _watchForClose(server, b);
  b.replyTo?.send(server.sendPort);
}

Future<TdlibGateway> _newGateway(CoreBootstrap b) async {
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

void _watchForClose(CoreServer server, CoreBootstrap b) {
  late StreamSubscription<AuthState> sub;
  sub = server.gateway.authState.listen((s) async {
    if (s is! AuthClosed) return;
    await sub.cancel();
    await server.replaceGateway(await _newGateway(b));
    _watchForClose(server, b);
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
      replyTo: reply.sendPort,
    ),
    debugName: 'core',
  );
  final port = await reply.first as SendPort;
  reply.close();
  return port;
}
