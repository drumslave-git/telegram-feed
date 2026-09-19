import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:core/native_isolate.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'ai/semantic_gate.dart';
import 'host/app_host.dart';
import 'service/core_service.dart';
import 'sync/drive_auth.dart';
import 'sync/sync_controller.dart';

/// Owns the app's connection to the core and the app database.
///
/// The core runs in the foreground service (ARCHITECTURE section 8): the host starts the
/// service, waits for the core's port in `IsolateNameServer` and connects. If the service
/// cannot start (notification permission denied, not Android), the core is spawned in-process
/// so the app still works while it is open.
final class CoreHost implements AppHost {
  CoreHost._(this.db, this._paths);

  static Future<CoreHost> start() async {
    final paths = await appPaths();
    final db = AppDatabase(NativeDatabase.createInBackground(File(paths.db)));
    final host = CoreHost._(db, paths);
    await host._connect();
    host._forwardChanges();
    unawaited(host.sync.start());
    return host;
  }

  @override
  final AppDatabase db;
  final ({String support, String tdlib, String db}) _paths;
  late final CoreClient _client;
  bool _inService = false;

  @override
  late final SyncController sync = SyncController(
    db: db,
    auth: GoogleDriveAuth(),
  );
  final _subs = <StreamSubscription<void>>[];

  @override
  TelegramGateway get gateway => _client;
  CoreClient get core => _client;

  /// True when the core runs under the foreground service (rules keep working in background).
  @override
  bool get runningInService => _inService;

  /// Where the core runs, and how loud the service notification is, are settled here.
  /// The core cannot move between the service and the app while it is up — TDLib is polled
  /// by one isolate per engine group (`native_isolate.dart`) — so both settings take effect
  /// the next time the app starts.
  Future<void> _connect() async {
    final background =
        await db.setting(SettingKeys.backgroundWatching) != 'false';
    final minimal =
        await db.setting(SettingKeys.minimalServiceNotification) == 'true';
    if (!background && Platform.isAndroid) await _stopService();
    var port = IsolateNameServer.lookupPortByName(corePortName);
    if (port == null && Platform.isAndroid && background) {
      if (await FlutterForegroundTask.checkNotificationPermission() !=
          NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
      if (await startCoreService(minimal: minimal)) {
        port = await _waitForPort(const Duration(seconds: 15));
        _inService = port != null;
        if (port == null) {
          debugPrint('core: service started but no port; in-process fallback');
        }
      }
    } else if (port != null) {
      _inService = await FlutterForegroundTask.isRunningService;
    }
    port ??= await _spawnInProcess();
    _client = await CoreClient.connect(port);
  }

  /// Background watching is off, so the service must go even when Android brought it back
  /// on boot. Waiting for it to be gone keeps its core isolate, and the TDLib receive
  /// isolate with it, from overlapping with the one spawned in this engine.
  Future<void> _stopService() async {
    if (!await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.stopService();
    final end = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(end) &&
        await FlutterForegroundTask.isRunningService) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    IsolateNameServer.removePortNameMapping(corePortName);
  }

  Future<SendPort?> _waitForPort(Duration timeout) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      final p = IsolateNameServer.lookupPortByName(corePortName);
      if (p != null) return p;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return null;
  }

  Future<SendPort> _spawnInProcess() async {
    final port = await spawnCoreIsolate(coreBootstrap(_paths));
    IsolateNameServer.removePortNameMapping(corePortName);
    IsolateNameServer.registerPortWithName(port, corePortName);
    return port;
  }

  /// Rules and watched channels are written by the UI; the core re-reads them on request.
  void _forwardChanges() {
    void refresh() {
      unawaited(_client.refresh());
      if (_inService) FlutterForegroundTask.sendDataToTask('refresh');
    }

    _subs.add(db.watchRules().listen((_) => refresh()));
    _subs.add(db.watchSourceChanges().listen((_) => refresh()));
    // Feed filters decide which posts may notify (ARCHITECTURE 5.8).
    _subs.add(db.watchFeeds().skip(1).listen((_) => refresh()));
  }

  /// Battery optimisation: without the exemption Android kills the service after a while.
  @override
  Future<bool> get isBatteryExempt async =>
      !Platform.isAndroid ||
      await FlutterForegroundTask.isIgnoringBatteryOptimizations;

  @override
  Future<void> requestBatteryExemption() =>
      FlutterForegroundTask.requestIgnoreBatteryOptimization();

  /// Logs out and wipes everything the app stored (ARCHITECTURE section 10). TDLib deletes
  /// its own database and files directory as part of `logOut`.
  @override
  Future<void> logOutAndWipe() async {
    // Sync goes off first: an emptied database must never be merged into the Drive file.
    await sync.turnOff();
    await const SecureSecretStore().write(AiKeys.apiKeySecret, null);
    await db.wipe();
    await gateway.logOut();
  }

  @override
  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await sync.dispose();
    await _client.close();
    await db.close();
  }
}
