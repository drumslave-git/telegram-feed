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
import 'package:push_runner/push_runner.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'ai/semantic_gate.dart';
import 'host/accounts.dart';
import 'host/app_host.dart';
import 'host/viewing.dart';
import 'l10n/l10n.dart';
import 'media/cache_limits.dart';
import 'media/video_positions.dart';
import 'service/account_watch.dart';
import 'service/core_bootstrap.dart';
import 'service/core_lock.dart';
import 'service/core_service.dart';
import 'service/launcher_badge.dart';
import 'service/notification_plan.dart';
import 'service/push_registration.dart';
import 'settings/app_lock.dart' show AppLock;
import 'service/reading_now.dart';
import 'service/rule_alerts.dart';
import 'sync/drive_auth.dart';
import 'sync/sync_controller.dart';

/// Owns the app's connection to the core and the app database.
///
/// Where the core runs follows the rules (ARCHITECTURE 8): while an enabled rule of a
/// logged-in account is instant, under the foreground service, which keeps the connection
/// to Telegram open and raises the notifications itself; otherwise in this process, with
/// the rule notifications, read-aloud ([RuleAlerts]) and the number on the app's icon
/// beside it, and Telegram's push starts a run while the app is closed (ARCHITECTURE
/// 6.5). A run that holds a core in this process hands it over first (`push_run.dart`).
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

  /// The core runs under the foreground service.
  bool _inService = false;

  /// Held while this process's core is this engine's ([CoreLock]).
  ReceivePort? _lock;

  @override
  late final SyncController sync = SyncController(
    db: db,
    auth: GoogleDriveAuth(),
  );
  final _subs = <StreamSubscription<void>>[];

  @override
  TelegramGateway get gateway => _client;
  CoreClient get core => _client;

  /// An FCM token, and Telegram took it for the account in use: it refuses one for a
  /// session that logged in through an app without FCM credentials (section 6.5).
  @override
  Future<bool> get pushAvailable async {
    final token = await PushRunner.token();
    if (token == null) return false;
    return PushRegistration.isFor(
      await db.setting(SettingKeys.pushRegistered),
      token,
    );
  }

  /// Whether an enabled rule of a logged-in account is instant: the connection is then
  /// kept open under the foreground service.
  Future<bool> _instantWanted() async {
    if (!Platform.isAndroid) return false;
    if (await db.hasInstantRule()) return true;
    for (final other in await otherAccountsToServe(_paths.support)) {
      final theirs = AppDatabase(appDatabaseFile(File(other.appDatabasePath)));
      try {
        if (await theirs.hasInstantRule()) return true;
      } finally {
        await theirs.close();
      }
    }
    return false;
  }

  /// Settles where the core runs. A core registered while the service is not running is
  /// a push run's: it stands down. The service's core is used while instant rules want
  /// it, and goes when none does.
  Future<void> _connect() async {
    final want = await _instantWanted();
    final running =
        Platform.isAndroid && await FlutterForegroundTask.isRunningService;
    if (running && !want) {
      await _stopService();
    } else if (!running) {
      await _shutdownForeignCore();
    }
    SendPort? port;
    if (want) {
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
    }
    port ??= await _spawnInProcess();
    _client = await CoreClient.connect(port);
  }

  /// The service goes, and its core has to be really gone first: `isRunningService`
  /// turning false says nothing about the core isolate, and the TDLib receive pump it
  /// leaves behind aborts the process as soon as this engine starts one of its own
  /// ("Receive must not be called simultaneously from two different threads"). The
  /// service takes the core's port out of `IsolateNameServer` once its core has handed
  /// TDLib back, so that mapping is the handshake; a core still registered afterwards is
  /// shut down from here.
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

  /// Shuts down a core that is still registered in this process and waits for it.
  /// Does nothing when there is none.
  Future<void> _shutdownForeignCore() => CoreLock.standDown();

  Future<SendPort?> _waitForPort(Duration timeout) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      final p = IsolateNameServer.lookupPortByName(corePortName);
      if (p != null) return p;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return null;
  }

  /// Takes the lock first: a run or the service may still be handing TDLib back, and
  /// one that has not let go in time is taken as gone.
  Future<SendPort> _spawnInProcess() async {
    _lock ??= await CoreLock.take(force: true);
    final port = await spawnCoreIsolate(
      coreBootstrap(_paths, others: await otherAccountsToServe(_paths.support)),
    );
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

  /// The other accounts of a core that runs in this process.
  AccountWatch? _watch;

  /// Read-aloud lives beside the core: in the service, which says what it reads after
  /// every change, or here. The pause is the core's.
  Future<void> _followReadingAndPause() async {
    _paused.value = await _client.isPaused();
    _subs.add(_client.pausedChanges.listen((p) => _paused.value = p));
    if (_inService) {
      FlutterForegroundTask.addTaskDataCallback(_onTaskData);
      FlutterForegroundTask.sendDataToTask(askReading);
    } else {
      await _startOwnAlerts();
    }
    unawaited(_registerPush());
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

  /// Telegram pushes every logged-in account to this install while the app is closed.
  /// Under the service the other accounts are opened for this alone ([_pushWatch]).
  Future<void> _registerPush() async {
    final watch =
        _watch ??
        (_pushWatch = await AccountWatch.open(
          _client,
          support: _paths.support,
        ));
    try {
      await PushRegistration.whenLoggedIn(
        main: _client,
        mainDb: db,
        others: watch.clients,
      );
    } finally {
      await _pushWatch?.dispose();
      _pushWatch = null;
    }
  }

  AccountWatch? _pushWatch;

  /// The alerts and the badge of a core that runs in this process.
  Future<void> _startOwnAlerts() async {
    // Every logged-in account notifies: the core serves the others beside this one.
    final watch = _watch = await AccountWatch.open(
      _client,
      support: _paths.support,
    );
    final alerts = RuleAlerts.of(
      _client,
      db: db,
      account: watch.activeId,
      accountName: watch.activeName,
      others: watch.alerts,
      onReading: (now) => _reading.value = now,
      log: (s) => debugPrint('alerts: $s'),
    );
    _alerts = alerts;
    _languageSetting = await db.setting(SettingKeys.language);
    await alerts.start(AppLanguage.strings(_languageSetting));
    _badge = LauncherBadge(
      db: db,
      channels: watch.channels,
      changes: watch.changes,
    );
    await _badge!.start();
  }

  /// One move at a time.
  Future<void> _move = Future.value();

  /// Moves the core under the foreground service ([on]) or out of it into this process,
  /// at once, when the instant rules call for it. TDLib is polled by one isolate at a
  /// time (`native_isolate.dart`), so the core that runs is shut down first and the other
  /// one started on the same database; the client is bound to the new one
  /// ([CoreClient.rebind]), so the screens keep the gateway they have. Where Android does
  /// not start the service the core comes back into this process.
  Future<void> _setInstant(bool on) {
    final done = _move.then((_) async {
      if (!Platform.isAndroid || on == _inService) return;
      _client.hold();
      if (on) {
        await _moveToService();
      } else {
        await _moveToApp();
      }
      // The new core is told again what the old one knew of the app.
      _paused.value = await _client.isPaused();
      _appOpen = null;
      _languageSent = null;
      _sendLanguage();
      _sendAppOpen(
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed,
      );
    });
    _move = done.catchError((Object e) {
      debugPrint('core: move failed: $e');
    });
    return done;
  }

  Future<void> _moveToApp() async {
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    _reading.value = null;
    // The service goes, and its core hands TDLib back before it does.
    await _stopService();
    await _client.rebind(await _spawnInProcess());
    _inService = false;
    await _startOwnAlerts();
  }

  Future<void> _moveToService() async {
    await _alerts?.dispose();
    _alerts = null;
    await _badge?.dispose();
    _badge = null;
    await _watch?.dispose();
    _watch = null;
    _reading.value = null;
    // This process's core closes TDLib and stops polling it.
    await _client.shutdown();
    IsolateNameServer.removePortNameMapping(corePortName);
    CoreLock.release(_lock);
    _lock = null;
    SendPort? port;
    final language = await db.setting(SettingKeys.language);
    if (await startCoreService(AppLanguage.strings(language))) {
      port = await _waitForPort(const Duration(seconds: 15));
    }
    if (port == null) {
      debugPrint('core: the service did not come up; back in this process');
      await _client.rebind(await _spawnInProcess());
      await _startOwnAlerts();
      return;
    }
    await _client.rebind(port);
    _inService = true;
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    FlutterForegroundTask.sendDataToTask(askReading);
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

    _subs.add(
      db.watchRules().listen((_) {
        refresh();
        // An instant rule came or went: the core moves to where it then runs.
        unawaited(_instantWanted().then(_setInstant));
      }),
    );
    // Rule sounds live in the notification channels, which are made again.
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

  static const _notifications = MethodChannel('tf/notifications');

  /// Battery optimisation: Android may hold back what a push starts while the phone
  /// sleeps, stop the service after a while, and some phones put the app to sleep.
  @override
  Future<bool> get isBatteryExempt async {
    if (!Platform.isAndroid) return true;
    try {
      return await _notifications.invokeMethod<bool>(
            'isIgnoringBatteryOptimizations',
          ) ??
          true;
    } on PlatformException {
      return true;
    }
  }

  @override
  Future<void> requestBatteryExemption() =>
      _notifications.invokeMethod<void>('requestIgnoreBatteryOptimizations');

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
    CoreLock.release(_lock);
    _lock = null;
  }

  @override
  Future<void> dispose() async {
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    await _alerts?.dispose();
    await _badge?.dispose();
    await _watch?.dispose();
    await _pushWatch?.dispose();
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
