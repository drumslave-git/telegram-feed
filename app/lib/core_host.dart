import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:core/native_isolate.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'ai/semantic_gate.dart';
import 'host/app_host.dart';
import 'service/core_service.dart';
import 'service/reading_now.dart';
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
    final db = AppDatabase(appDatabaseFile(File(paths.db), inBackground: true));
    final host = CoreHost._(db, paths);
    await host._connect();
    host._forwardChanges();
    await host._followReadingAndPause();
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

  /// Where the core runs is settled here. The core cannot move between the service and the
  /// app while it is up (TDLib is polled by one isolate per engine group,
  /// `native_isolate.dart`), so a change of background watching takes effect when the app
  /// starts again; [restart] does that on request.
  Future<void> _connect() async {
    final background =
        await db.setting(SettingKeys.backgroundWatching) != 'false';
    if (!background && Platform.isAndroid) await _stopService();
    var port = IsolateNameServer.lookupPortByName(corePortName);
    if (port == null && Platform.isAndroid && background) {
      // The notification permission is NOT asked here. This runs before the login
      // screen, on a blank spinner, and Android lets an app ask only once: a reflexive
      // "Don't allow" would silence every rule for good. The service runs without it
      // (its own notification is simply not shown), and the app asks for it where it
      // can say what it is for: when a rule is saved, and on Notifications and sounds.
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

  /// Background watching is off, so the service must go even when Android brought it back
  /// on boot (it restores the service before Dart runs). Its core has to be really gone
  /// first: `isRunningService` turning false says nothing about the core isolate, and the
  /// TDLib receive pump it leaves behind aborts the process as soon as this engine starts
  /// one of its own ("Receive must not be called simultaneously from two different
  /// threads"). The service takes the core's port out of `IsolateNameServer` once its core
  /// has handed TDLib back, so that mapping is the handshake; a core still registered
  /// afterwards is shut down from here.
  Future<void> _stopService() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
      final end = DateTime.now().add(const Duration(seconds: 15));
      while (DateTime.now().isBefore(end) &&
          (await FlutterForegroundTask.isRunningService ||
              IsolateNameServer.lookupPortByName(corePortName) != null)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    await _shutdownForeignCore();
  }

  /// Shuts down a core that is still registered in this process and waits for it, so this
  /// engine may spawn its own. Does nothing when there is none.
  Future<void> _shutdownForeignCore() async {
    final port = IsolateNameServer.lookupPortByName(corePortName);
    IsolateNameServer.removePortNameMapping(corePortName);
    if (port == null) return;
    debugPrint('core: a core is still registered; asking it to stand down');
    try {
      final client = await CoreClient.connect(port)
          .timeout(const Duration(seconds: 5));
      await client.shutdown().timeout(const Duration(seconds: 10));
      await client.close();
    } on Object catch (e) {
      debugPrint('core: stand down failed: $e');
    }
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

  @override
  ValueListenable<ReadingNow?> get reading => _reading;
  final _reading = ValueNotifier<ReadingNow?>(null);

  @override
  ValueListenable<bool> get paused => _paused;
  final _paused = ValueNotifier<bool>(false);

  @override
  Future<void> setPaused(bool paused) => _client.setPaused(paused);

  @override
  void stopReading({bool clear = false}) {
    final now = _reading.value;
    if (!_inService) return;
    if (clear) {
      FlutterForegroundTask.sendDataToTask(clearReading);
    } else if (now != null) {
      FlutterForegroundTask.sendDataToTask(stopReadingOf(now));
    }
  }

  /// Read-aloud lives in the service, which says what it reads after every change; the
  /// pause is the core's.
  Future<void> _followReadingAndPause() async {
    _paused.value = await _client.isPaused();
    _subs.add(_client.pausedChanges.listen((p) => _paused.value = p));
    if (!_inService) return;
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    FlutterForegroundTask.sendDataToTask(askReading);
  }

  void _onTaskData(Object data) {
    if (data is Map && data.containsKey('reading')) {
      _reading.value = ReadingNow.decode(data['reading']);
    }
  }

  /// Rules and watched channels are written by the UI; the core re-reads them on request.
  void _forwardChanges() {
    void refresh() {
      unawaited(_client.refresh());
      if (_inService) FlutterForegroundTask.sendDataToTask('refresh');
    }

    _subs.add(db.watchRules().listen((_) => refresh()));
    // Rule sounds live in the service's notification channels, which it makes again.
    for (final key in const [
      SettingKeys.normalSound,
      SettingKeys.urgentSound,
      SettingKeys.normalVibrate,
      SettingKeys.urgentVibrate,
    ]) {
      _subs.add(
        db.watchSetting(key).skip(1).listen((_) {
          if (_inService) FlutterForegroundTask.sendDataToTask('sounds');
        }),
      );
    }
    _subs.add(db.watchSourceChanges().listen((_) => refresh()));
    // Feed filters decide which posts may notify (ARCHITECTURE 5.8).
    _subs.add(db.watchFeeds().skip(1).listen((_) => refresh()));
  }

  /// Starts the app afresh: the core goes down first, from the service or from this
  /// process, so TDLib is closed; the new process then settles where the core runs.
  @override
  Future<void> restart() async {
    if (Platform.isAndroid) await _stopService();
    await const MethodChannel('tf/app').invokeMethod<void>('restart');
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
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    for (final s in _subs) {
      await s.cancel();
    }
    await sync.dispose();
    await _client.close();
    await db.close();
  }
}
