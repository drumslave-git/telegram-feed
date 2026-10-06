import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:core/native_isolate.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../app_name.dart';
import '../l10n/l10n.dart';
import 'account_watch.dart';
import 'core_bootstrap.dart';
import 'core_lock.dart';
import 'launcher_badge.dart';
import 'rule_alerts.dart';

const coreServiceId = 1;

/// Manifest meta-data that names the status bar icon of the service notification.
const serviceIconMetaData = 'dev.telegramfeed.service.NOTIFICATION_ICON';
const pauseButtonId = 'pause';
const resumeButtonId = 'resume';

/// Channel of the permanent service notification. It is as quiet as Android allows: the
/// channel of a foreground service is raised to `IMPORTANCE_LOW` whatever is asked for,
/// so there is nothing below this. The `core_min` channel of an earlier build is deleted.
const serviceChannel = 'core';
const _retiredServiceChannel = 'core_min';

/// Call once in `main()` of the UI. The communication port is registered here and nowhere
/// else: registering it again would drop the one the app is already listening on.
void initCoreService() {
  FlutterForegroundTask.initCommunicationPort();
  _configureServiceNotification(AppLanguage.strings(null));
}

/// The service's notification options, its channel named in [strings].
void _configureServiceNotification(AppLocalizations strings) {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: serviceChannel,
      channelName: strings.serviceChannelName,
      channelDescription: strings.serviceChannelDescription,
      onlyAlertOnce: true,
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(60 * 1000),
      autoRunOnBoot: true,
      autoRunOnMyPackageReplaced: true,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );
}

/// Starts the service (idempotent), its notification in [strings]. Returns false when
/// Android refused.
Future<bool> startCoreService(AppLocalizations strings) async {
  if (await FlutterForegroundTask.isRunningService) return true;
  _configureServiceNotification(strings);
  // One "Watching channels" row in the system settings, not two.
  await FlutterLocalNotificationsPlugin()
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.deleteNotificationChannel(channelId: _retiredServiceChannel);
  final r = await FlutterForegroundTask.startService(
    serviceId: coreServiceId,
    serviceTypes: [ForegroundServiceTypes.specialUse],
    notificationTitle: appName,
    notificationText: strings.serviceStarting,
    notificationIcon: const NotificationIcon(metaDataName: serviceIconMetaData),
    notificationButtons: [
      NotificationButton(id: pauseButtonId, text: strings.servicePause),
    ],
    callback: coreServiceCallback,
  );
  return r is ServiceRequestSuccess;
}

@pragma('vm:entry-point')
void coreServiceCallback() {
  FlutterForegroundTask.setTaskHandler(CoreServiceHandler());
}

/// Runs in the service engine's root isolate: spawns the core isolate, registers its port,
/// keeps the notification current, and owns the plugins that need platform callbacks
/// (notifications and read-aloud, in [RuleAlerts]).
class CoreServiceHandler extends TaskHandler {
  Isolate? _core;
  CoreClient? _client;
  AppDatabase? _db;
  StreamSubscription<bool>? _pausedSub;
  bool _paused = false;
  RuleAlerts? _alerts;
  LauncherBadge? _badge;
  AccountWatch? _watch;

  /// Whether the app is on screen; it may say so before the alerts are up.
  bool _appOpen = false;
  bool _appUnlocked = false;
  Set<int> _appViewing = const {};

  /// The interface language: the Language setting, or the phone's. The app tells the
  /// service when it changes ('language').
  AppLocalizations _strings = AppLanguage.strings(null);

  static void _log(String s) => debugPrint('service: $s');

  /// The run of [onStart]; a destroy in the middle of it waits for it, or the core's
  /// TDLib receive pump would outlive the service (ARCHITECTURE 8).
  Future<void>? _starting;

  /// Held while this service's core runs ([CoreLock]).
  ReceivePort? _lock;
  bool _destroyed = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) {
    final started = _starting = _start(starter);
    return started;
  }

  Future<void> _start(TaskStarter starter) async {
    _log('onStart ($starter)');
    // The app may run a core of its own: it stops this service then, and the service
    // starts none rather than a second one.
    _lock = await CoreLock.take(
      wait: const Duration(seconds: 30),
      standDownHolder: false,
      cancelled: () => _destroyed,
    );
    if (_lock == null) {
      _log('another core holds TDLib; none started');
      return;
    }
    final paths = await appPaths();
    _db = AppDatabase(appDatabaseFile(File(paths.db)));
    _strings = AppLanguage.strings(await _db!.setting(SettingKeys.language));
    final reply = ReceivePort();
    _core = await Isolate.spawn(
      coreIsolateMain,
      coreBootstrap(
        paths,
        others: await otherAccountsToServe(paths.support),
        replyTo: reply.sendPort,
      ),
      debugName: 'core',
    );
    final port = await reply.first as SendPort;
    reply.close();
    IsolateNameServer.removePortNameMapping(corePortName);
    IsolateNameServer.registerPortWithName(port, corePortName);
    _client = await CoreClient.connect(port);
    // A pause kept from before the restart is the core's; the notification says so.
    _paused = await _client!.isPaused();
    _pausedSub = _client!.pausedChanges.listen((p) {
      _paused = p;
      unawaited(_updateNotification());
    });
    // Every logged-in account notifies: the core serves the others beside this one.
    final watch = _watch = await AccountWatch.open(
      _client!,
      support: paths.support,
    );
    final alerts = RuleAlerts.of(
      _client!,
      db: _db!,
      account: watch.activeId,
      accountName: watch.activeName,
      others: watch.alerts,
      // The app may not be open, and then nobody listens.
      onReading: (now) =>
          FlutterForegroundTask.sendDataToMain({'reading': now?.encode()}),
      // Android counts a tap on a notification as the app being used, so the service's
      // notification is posted again within it: a service that Android started after a
      // reboot or an update then may take the audio focus, and read aloud, from now on.
      onAction: _updateNotification,
      log: _log,
    );
    alerts.appOpen = _appOpen;
    alerts.unlocked = _appUnlocked;
    alerts.viewing = _appViewing;
    _alerts = alerts;
    await alerts.start(_strings);
    _badge = LauncherBadge(
      db: _db!,
      channels: watch.channels,
      changes: watch.changes,
    );
    await _badge!.start();
    await _updateNotification();
    _log('core up, port registered');
  }

  Future<void> _updateNotification() async {
    final n =
        await _alerts?.reloadTitles() ?? (await _db?.allWatched())?.length ?? 0;
    await FlutterForegroundTask.updateService(
      notificationTitle: appName,
      notificationText: _paused
          ? _strings.servicePaused
          : _strings.serviceWatching(n),
      // Named again on every update: Android restores a running service with the content
      // saved when it was started, which may come from a build that had no icon of its own
      // and so fell back to the launcher icon, in colour.
      notificationIcon: const NotificationIcon(
        metaDataName: serviceIconMetaData,
      ),
      notificationButtons: [
        _paused
            ? NotificationButton(
                id: resumeButtonId,
                text: _strings.serviceResume,
              )
            : NotificationButton(
                id: pauseButtonId,
                text: _strings.servicePause,
              ),
      ],
    );
  }

  @override
  void onRepeatEvent(DateTime timestamp) => unawaited(_updateNotification());

  /// The app's interface language changed (its setting, or the phone's language while
  /// the setting follows the phone): the permanent notification, the rule notifications
  /// and the channels' names in Android's settings follow.
  Future<void> _setLanguage(String code) async {
    final strings = AppLanguage.stringsOfLanguage(code);
    if (strings == null || strings.localeName == _strings.localeName) return;
    _strings = strings;
    await FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          AndroidNotificationChannel(
            serviceChannel,
            strings.serviceChannelName,
            description: strings.serviceChannelDescription,
            importance: Importance.low,
            playSound: false,
            enableVibration: false,
          ),
        );
    await _alerts?.setStrings(strings);
    await _updateNotification();
  }

  @override
  void onReceiveData(Object data) {
    // The UI sends 'refresh' after database changes (feeds, sources, rules), 'sounds'
    // after a rule sound or vibration changed, 'badge' after a switch of the badge
    // counter, and whether it is on screen.
    if (data == 'refresh') {
      unawaited(_client?.refresh());
      unawaited(_updateNotification());
    }
    if (data == 'sounds') unawaited(_alerts?.reloadSounds());
    // A switch of the badge counter changed.
    if (data == 'badge') unawaited(_badge?.refresh());
    if (data is Map && data['language'] is String) {
      unawaited(_setLanguage(data['language'] as String));
    }
    // Posts that match while the app is on screen do not pop up (appOpenMessage).
    if (data is Map && data['appOpen'] is bool) {
      _appOpen = data['appOpen'] as bool;
      _alerts?.appOpen = _appOpen;
      // Behind its lock, or gone: a match hides what its post says (rule_alerts.dart).
      _appUnlocked = data['unlocked'] == true;
      _alerts?.unlocked = _appUnlocked;
      // The timeline in front: its own posts do not pop up over it.
      _appViewing = {
        for (final id in (data['viewing'] as List? ?? const []))
          if (id is int) id,
      };
      _alerts?.viewing = _appViewing;
    }
    // The read-aloud banner asks what is read, and stops it (reading_now.dart).
    if (data is Map) {
      switch (data['tts']) {
        case 'state':
          _alerts?.publishReading();
        case 'stop':
          unawaited(
            _alerts?.stop(data['chatId'] as int, data['messageId'] as int),
          );
        case 'clear':
          unawaited(_alerts?.stopAll());
      }
    }
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == pauseButtonId) unawaited(_client?.setPaused(true));
    if (id == resumeButtonId) unawaited(_client?.setPaused(false));
  }

  @override
  void onNotificationPressed() => FlutterForegroundTask.launchApp();

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _log('onDestroy timeout=$isTimeout');
    _destroyed = true;
    try {
      await _starting?.timeout(const Duration(seconds: 10));
    } on Object catch (e) {
      _log('start unfinished at destroy: $e');
    }
    await _pausedSub?.cancel();
    await _alerts?.dispose();
    await _badge?.dispose();
    await _watch?.dispose();
    // Give TDLib back before the isolate goes: its client has to drop the database lock
    // and its receive pump has to stop, or the app's own core aborts the process.
    try {
      await _client?.shutdown().timeout(const Duration(seconds: 10));
    } on Object catch (e) {
      _log('core shutdown: $e');
    }
    await _client?.close();
    IsolateNameServer.removePortNameMapping(corePortName);
    _core?.kill(priority: Isolate.immediate);
    await _db?.close();
    CoreLock.release(_lock);
    _lock = null;
    _log('core down');
  }
}
