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
import 'service/launcher_badge.dart';
import 'service/push_registration.dart';
import 'settings/app_lock.dart' show AppLock;
import 'service/reading_now.dart';
import 'service/rule_alerts.dart';
import 'sync/drive_auth.dart';
import 'sync/sync_controller.dart';

/// Owns the app's connection to the core and the app database.
///
/// The core runs in this process (ARCHITECTURE 8), and beside it the rule notifications
/// and read-aloud ([RuleAlerts]) and the number on the app's icon. A run that Android
/// started for a push while the app was closed may hold a core in this process; it hands
/// that core over first (`push_run.dart`). While the app is closed, Telegram's push
/// starts such runs (ARCHITECTURE 6.5).
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

  @override
  late final SyncController sync = SyncController(
    db: db,
    auth: GoogleDriveAuth(),
  );
  final _subs = <StreamSubscription<void>>[];

  @override
  TelegramGateway get gateway => _client;
  CoreClient get core => _client;

  @override
  Future<bool> get pushAvailable async => await PushRunner.token() != null;

  /// A run may hold the core in this process: it stands down, so this engine can start
  /// its own.
  Future<void> _connect() async {
    await _shutdownForeignCore();
    _client = await CoreClient.connect(await _spawnInProcess());
  }

  /// Shuts down a core that is still registered in this process and waits for it, so
  /// this engine may spawn its own: TDLib is polled by one isolate at a time, and a
  /// second receive pump aborts the process ("Receive must not be called simultaneously
  /// from two different threads"). Does nothing when there is none.
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

  Future<SendPort> _spawnInProcess() async {
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
    if (clear) {
      unawaited(_alerts?.stopAll());
    } else if (now != null) {
      unawaited(_alerts?.stop(now.chatId, now.messageId));
    }
  }

  RuleAlerts? _alerts;
  LauncherBadge? _badge;
  AccountWatch? _watch;

  /// Read-aloud, the notifications and the number on the app's icon live beside the
  /// core. The pause is the core's.
  Future<void> _followReadingAndPause() async {
    _paused.value = await _client.isPaused();
    _subs.add(_client.pausedChanges.listen((p) => _paused.value = p));
    await _startAlerts();
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

  Future<void> _startAlerts() async {
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
    // Telegram pushes every logged-in account to this install while the app is closed.
    unawaited(
      PushRegistration.whenLoggedIn(
        main: _client,
        mainDb: db,
        others: watch.clients,
      ),
    );
  }

  AppLifecycleListener? _lifecycle;
  bool? _appOpen;
  String? _languageSetting;
  String? _languageSent;
  _PhoneLanguage? _phoneLanguage;

  /// The language the app is shown in: the setting's, or the phone's while the setting
  /// follows the phone.
  void _sendLanguage() {
    final code =
        (AppLanguage.localeOf(_languageSetting) ?? AppLanguage.ofPhone())
            .languageCode;
    if (code == _languageSent) return;
    _languageSent = code;
    if (AppLanguage.stringsOfLanguage(code) case final strings?) {
      unawaited(_alerts?.setStrings(strings));
    }
  }

  /// Only a resumed app counts as open, so in picture-in-picture posts pop up as usual.
  void _sendAppOpen(AppLifecycleState state) {
    final open = state == AppLifecycleState.resumed;
    _appOpen = open;
    _alerts?.appOpen = open;
    _alerts?.unlocked = open && !AppLock.locked.value;
    _alerts?.viewing = open ? Viewing.chats.value : const <int>{};
  }

  /// The lock screen came up or went, or another timeline is in front: the
  /// notifications follow.
  void _onLockChanged() => _sendAppOpen(
    (_appOpen ?? false) ? AppLifecycleState.resumed : AppLifecycleState.paused,
  );

  /// Rules and watched channels are written by the UI; the core re-reads them on request.
  void _forwardChanges() {
    void refresh() {
      unawaited(_client.refresh());
      unawaited(_alerts?.reloadTitles());
    }

    _subs.add(db.watchRules().listen((_) => refresh()));
    // Rule sounds live in the notification channels, which are made again.
    for (final key in const [
      SettingKeys.normalSound,
      SettingKeys.urgentSound,
      SettingKeys.normalVibrate,
      SettingKeys.urgentVibrate,
    ]) {
      _subs.add(
        db.watchSetting(key).skip(1).listen((_) {
          unawaited(_alerts?.reloadSounds());
        }),
      );
    }
    // The number on the app's icon is counted again when a switch of it changes.
    for (final key in LauncherBadge.settings) {
      _subs.add(
        db.watchSetting(key).distinct().skip(1).listen((_) {
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
  /// sleeps, and some phones put the app to sleep altogether.
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
    // The core is still the old account's: it goes, and the next host starts its own on
    // the new account's paths.
    await _shutdownForeignCore();
  }

  @override
  Future<void> dispose() async {
    await _alerts?.dispose();
    await _badge?.dispose();
    await _watch?.dispose();
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
