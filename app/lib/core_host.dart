import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:core/native_isolate.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'ai/semantic_gate.dart';
import 'host/accounts.dart';
import 'host/app_host.dart';
import 'host/viewing.dart';
import 'l10n/l10n.dart';
import 'media/cache_limits.dart';
import 'media/video_positions.dart';
import 'service/core_service.dart';
import 'service/launcher_badge.dart';
import 'settings/app_lock.dart' show AppLock;
import 'service/notification_plan.dart';
import 'service/reading_now.dart';
import 'service/rule_alerts.dart';
import 'sync/drive_auth.dart';
import 'sync/sync_controller.dart';

/// Owns the app's connection to the core and the app database.
///
/// The core runs in the foreground service (ARCHITECTURE section 8): the host starts the
/// service, waits for the core's port in `IsolateNameServer` and connects. If the service
/// cannot start (not Android) or background watching is off, the core is spawned in-process
/// and the app raises the rule notifications and reads aloud itself ([RuleAlerts]), so the
/// rules work while it is open.
final class CoreHost implements AppHost {
  CoreHost._(this.db, this._paths);

  static Future<CoreHost> start() async {
    final paths = await appPaths();
    final db = AppDatabase(appDatabaseFile(File(paths.db), inBackground: true));
    final host = CoreHost._(db, paths);
    // Where the account's videos were left in the viewer.
    final accounts = AccountStore(paths.support);
    await VideoPositions.attach(
      File(accounts.videoPositionsOf(await accounts.activeId())),
    );
    await host._connect();
    host._forwardChanges();
    // TDLib keeps the limits of its cache; the reader's are handed to it once the
    // account is logged in, and again whenever one changes.
    host._subs.addAll(CacheLimits.follow(db, host.gateway));
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
      final language = await db.setting(SettingKeys.language);
      if (await startCoreService(AppLanguage.strings(language))) {
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
    if (!_inService) {
      if (clear) {
        unawaited(_alerts?.stopAll());
      } else if (now != null) {
        unawaited(_alerts?.stop(now.chatId, now.messageId));
      }
      return;
    }
    if (clear) {
      FlutterForegroundTask.sendDataToTask(clearReading);
    } else if (now != null) {
      FlutterForegroundTask.sendDataToTask(stopReadingOf(now));
    }
  }

  /// The alerts of a core that runs in this process; the service has its own.
  RuleAlerts? _alerts;

  /// The number on the app's icon, counted here while there is no service to do it.
  LauncherBadge? _badge;

  /// Read-aloud lives beside the core: in the service, which says what it reads after
  /// every change, or here. The pause is the core's.
  Future<void> _followReadingAndPause() async {
    _paused.value = await _client.isPaused();
    _subs.add(_client.pausedChanges.listen((p) => _paused.value = p));
    if (_inService) {
      FlutterForegroundTask.addTaskDataCallback(_onTaskData);
      FlutterForegroundTask.sendDataToTask(askReading);
    } else {
      final alerts = RuleAlerts.of(
        _client,
        db: db,
        onReading: (now) => _reading.value = now,
        log: (s) => debugPrint('alerts: $s'),
      );
      _alerts = alerts;
      _languageSetting = await db.setting(SettingKeys.language);
      await alerts.start(AppLanguage.strings(_languageSetting));
      _badge = LauncherBadge.of(_client, db: db);
      await _badge!.start();
    }
    // Posts that match while the app is on screen do not pop up over it.
    _lifecycle = AppLifecycleListener(onStateChange: _sendAppOpen);
    AppLock.locked.addListener(_onLockChanged);
    Viewing.chats.addListener(_onLockChanged);
    _sendAppOpen(
      WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed,
    );
    // The rule notifications speak the app's language.
    _subs.add(
      db.watchSetting(SettingKeys.language).listen((v) {
        _languageSetting = v;
        _sendLanguage();
      }),
    );
    _phoneLanguage = _PhoneLanguage(_sendLanguage);
    WidgetsBinding.instance.addObserver(_phoneLanguage!);
  }

  AppLifecycleListener? _lifecycle;
  bool? _appOpen;
  String? _languageSetting;
  String? _languageSent;
  _PhoneLanguage? _phoneLanguage;

  /// The language the app is shown in: the setting's, or the phone's while the setting
  /// follows the phone, which can change while the service runs.
  void _sendLanguage() {
    final code =
        (AppLanguage.localeOf(_languageSetting) ?? AppLanguage.ofPhone())
            .languageCode;
    if (code == _languageSent) return;
    _languageSent = code;
    if (_inService) {
      FlutterForegroundTask.sendDataToTask({'language': code});
    } else if (AppLanguage.stringsOfLanguage(code) case final strings?) {
      unawaited(_alerts?.setStrings(strings));
    }
  }

  /// Only a resumed app counts as open, so in picture-in-picture posts pop up as usual.
  void _sendAppOpen(AppLifecycleState state) {
    final open = state == AppLifecycleState.resumed;
    final unlocked = open && !AppLock.locked.value;
    final viewing = open ? Viewing.chats.value : const <int>{};
    if (open == _appOpen &&
        unlocked == _appUnlocked &&
        setEquals(viewing, _appViewing)) {
      return;
    }
    _appOpen = open;
    _appUnlocked = unlocked;
    _appViewing = viewing;
    if (_inService) {
      FlutterForegroundTask.sendDataToTask(
        appOpenMessage(open, unlocked: unlocked, viewing: viewing),
      );
    } else {
      _alerts?.appOpen = open;
      _alerts?.unlocked = unlocked;
      _alerts?.viewing = viewing;
    }
  }

  Set<int>? _appViewing;

  bool? _appUnlocked;

  /// The lock screen came up or went, or another timeline is in front: the
  /// notifications follow.
  void _onLockChanged() => _sendAppOpen(
    (_appOpen ?? false) ? AppLifecycleState.resumed : AppLifecycleState.paused,
  );

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
      unawaited(_alerts?.reloadTitles());
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
          unawaited(_alerts?.reloadSounds());
        }),
      );
    }
    // The number on the app's icon is counted beside the core.
    for (final key in LauncherBadge.settings) {
      _subs.add(
        db.watchSetting(key).distinct().skip(1).listen((_) {
          if (_inService) FlutterForegroundTask.sendDataToTask('badge');
          unawaited(_badge?.refresh());
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
    await VideoPositions.wipe();
    await gateway.logOut();
    // Nothing of the account stays in the list of accounts either.
    try {
      final store = AccountStore((await appPaths()).support);
      await AccountRecorder(store, await store.activeId()).loggedOut();
    } on Object catch (e) {
      debugPrint('accounts: logout not recorded: $e');
    }
  }

  @override
  Future<void> standDown() async {
    await dispose();
    // The service's core, or the one this process spawned: either is still the old
    // account's. The next host starts its own on the new account's paths.
    if (Platform.isAndroid) {
      await _stopService();
    } else {
      await _shutdownForeignCore();
    }
  }

  @override
  Future<void> dispose() async {
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    await _alerts?.dispose();
    await _badge?.dispose();
    _lifecycle?.dispose();
    AppLock.locked.removeListener(_onLockChanged);
    Viewing.chats.removeListener(_onLockChanged);
    if (_phoneLanguage case final o?) WidgetsBinding.instance.removeObserver(o);
    for (final s in _subs) {
      await s.cancel();
    }
    await sync.dispose();
    await _client.close();
    await db.close();
  }
}

/// Calls back when the phone's list of languages changes.
final class _PhoneLanguage with WidgetsBindingObserver {
  _PhoneLanguage(this.onChanged);
  final VoidCallback onChanged;

  @override
  void didChangeLocales(List<Locale>? locales) => onChanged();
}
