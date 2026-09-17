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

import 'host/app_host.dart';
import 'service/core_service.dart';

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
    return host;
  }

  @override
  final AppDatabase db;
  final ({String support, String tdlib, String db}) _paths;
  late final CoreClient _client;
  bool _inService = false;
  final _subs = <StreamSubscription<void>>[];

  @override
  TelegramGateway get gateway => _client;
  CoreClient get core => _client;

  /// True when the core runs under the foreground service (rules keep working in background).
  @override
  bool get runningInService => _inService;

  Future<void> _connect() async {
    var port = IsolateNameServer.lookupPortByName(corePortName);
    if (port == null && Platform.isAndroid) {
      if (await FlutterForegroundTask.checkNotificationPermission() !=
          NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
      if (await startCoreService()) {
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
    await db.wipe();
    await gateway.logOut();
  }

  @override
  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _client.close();
    await db.close();
  }
}
