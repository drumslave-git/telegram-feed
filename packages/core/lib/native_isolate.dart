/// Core isolate for native platforms: TDLib over FFI, served through [CoreServer].
///
/// Phase 1: spawned by the UI with [spawnCoreIsolate]. Phase 2: spawned by the foreground
/// service's task handler with the same [coreIsolateMain]. The host that spawns it registers
/// the returned port with `IsolateNameServer` under [corePortName] (this package is pure Dart
/// and cannot import `dart:ui`), and UI engines look it up instead of spawning.
library;

import 'dart:async';
import 'dart:isolate';

import 'package:telegram_gateway/tdlib_ffi.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'src/core_server.dart';
import 'src/protocol.dart';

export 'src/protocol.dart' show corePortName;

/// Everything the core isolate needs to start; only sendable values.
final class CoreBootstrap {
  const CoreBootstrap({
    required this.apiId,
    required this.apiHash,
    required this.databaseDirectory,
    required this.filesDirectory,
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
@pragma('vm:entry-point')
Future<void> coreIsolateMain(CoreBootstrap b) async {
  final transport = await FfiTransport.create(
    libraryPath: b.libraryPath,
    logVerbosity: b.logVerbosity,
  );
  final gateway = TdlibGateway(
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
  final server = CoreServer(
    gateway,
    log: (s) => print(s),
  ); // ignore: avoid_print
  b.replyTo?.send(server.sendPort);
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
