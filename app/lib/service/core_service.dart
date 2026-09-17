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
import 'package:path_provider/path_provider.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../credentials.dart';
import 'notifier.dart';
import 'tts_service.dart';

/// Paths shared by the UI host and the service host.
Future<({String support, String tdlib, String db})> appPaths() async {
  final support = (await getApplicationSupportDirectory()).path;
  return (support: support, tdlib: '$support/tdlib', db: '$support/app.sqlite');
}

CoreBootstrap coreBootstrap(({String support, String tdlib, String db}) p) =>
    CoreBootstrap(
      apiId: tgApiId,
      apiHash: tgApiHash,
      databaseDirectory: p.tdlib,
      filesDirectory: '${p.tdlib}/files',
      appDatabasePath: p.db,
      useTestDc: tgTestDc,
      deviceModel: Platform.isAndroid ? 'Android' : Platform.operatingSystem,
      systemVersion: Platform.operatingSystemVersion,
    );

const coreServiceId = 1;
const pauseButtonId = 'pause';
const resumeButtonId = 'resume';

/// Call once in `main()` of the UI and before starting the service.
void initCoreService() {
  FlutterForegroundTask.initCommunicationPort();
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'core',
      channelName: 'Watching channels',
      channelDescription:
          'Keeps the Telegram connection open for keyword rules',
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

/// Starts the service (idempotent). Returns false when Android refused.
Future<bool> startCoreService() async {
  if (await FlutterForegroundTask.isRunningService) return true;
  final r = await FlutterForegroundTask.startService(
    serviceId: coreServiceId,
    serviceTypes: [ForegroundServiceTypes.specialUse],
    notificationTitle: 'telegram-feed',
    notificationText: 'Starting…',
    notificationButtons: const [
      NotificationButton(id: pauseButtonId, text: 'Pause'),
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
/// (notifications and TTS from P2-4/P2-5 on).
class CoreServiceHandler extends TaskHandler {
  Isolate? _core;
  CoreClient? _client;
  AppDatabase? _db;
  StreamSubscription<bool>? _pausedSub;
  bool _paused = false;
  final _notifier = Notifier();
  final _actions = ReceivePort();
  Map<int, String> _titles = const {};
  TtsService? _tts;

  /// Recent matched posts so the Listen action can find their text.
  final _recentTexts = <(int, int), String>{};

  static void _log(String s) => debugPrint('service: $s');

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _log('onStart ($starter)');
    final paths = await appPaths();
    _db = AppDatabase(NativeDatabase(File(paths.db)));
    final reply = ReceivePort();
    _core = await Isolate.spawn(
      coreIsolateMain,
      CoreBootstrap(
        apiId: tgApiId,
        apiHash: tgApiHash,
        databaseDirectory: paths.tdlib,
        filesDirectory: '${paths.tdlib}/files',
        appDatabasePath: paths.db,
        useTestDc: tgTestDc,
        deviceModel: Platform.isAndroid ? 'Android' : Platform.operatingSystem,
        systemVersion: Platform.operatingSystemVersion,
        replyTo: reply.sendPort,
      ),
      debugName: 'core',
    );
    final port = await reply.first as SendPort;
    reply.close();
    IsolateNameServer.removePortNameMapping(corePortName);
    IsolateNameServer.registerPortWithName(port, corePortName);
    _client = await CoreClient.connect(port);
    _pausedSub = _client!.pausedChanges.listen((p) {
      _paused = p;
      unawaited(_updateNotification());
    });
    await _notifier.init();
    final tts = TtsService(db: _db!, speaker: FlutterTtsSpeaker());
    try {
      await tts.init();
      _tts = tts;
    } catch (e) {
      _log('tts unavailable: $e');
    }
    IsolateNameServer.removePortNameMapping(notifierPortName);
    IsolateNameServer.registerPortWithName(_actions.sendPort, notifierPortName);
    _actions.listen(_onNotificationAction);
    _client!.matches.listen(_onMatch);
    _client!.postEvents.listen((e) {
      if (e is PostsDeleted) {
        unawaited(_notifier.cancel(e.chatId, e.messageIds));
      }
    });
    await _updateNotification();
    _log('core up, port registered');
  }

  Future<void> _onMatch(MatchEvent m) async {
    _log('match ${m.ruleNames} on ${m.post.chatId}/${m.post.messageId}');
    if (!_titles.containsKey(m.post.chatId)) await _reloadTitles();
    final plan = NotificationPlan.forMatch(
      m,
      channelTitle: _titles[m.post.chatId] ?? '',
    );
    await _notifier.show(plan);
    _remember(m.post.chatId, m.post.messageId, m.post.text);
    if (m.readAloud) _speakPost(m.post.chatId, m.post.messageId);
  }

  void _remember(int chatId, int messageId, String text) {
    _recentTexts[(chatId, messageId)] = text;
    if (_recentTexts.length > 200) _recentTexts.remove(_recentTexts.keys.first);
  }

  /// The "Listen" action and auto-read share this path (ARCHITECTURE 7).
  void _speakPost(int chatId, int messageId) {
    final text = _recentTexts[(chatId, messageId)];
    if (text == null) {
      _log('no text remembered for $chatId/$messageId');
      return;
    }
    _tts?.enqueue(
      TtsItem(
        text: text,
        channelTitle: _titles[chatId],
        key: (chatId, messageId),
      ),
    );
  }

  Future<void> _reloadTitles() async {
    final watched = await _db?.allWatched() ?? const <WatchedChannel>[];
    _titles = {for (final w in watched) w.chatId: w.title};
  }

  void _onNotificationAction(Object? msg) {
    final m = msg as Map<Object?, Object?>;
    final ref = PostRef.decode(m['payload'] as String?);
    _log(
      'notification action ${m['actionId']} on ${ref?.chatId}/${ref?.messageId}',
    );
    if (m['actionId'] == actionListen && ref != null) {
      _speakPost(ref.chatId, ref.messageId);
    }
    // Taps and \"Open in Telegram\" are handled by the app (notification_launch.dart).
  }

  Future<void> _updateNotification() async {
    await _reloadTitles();
    final n = _titles.length;
    await FlutterForegroundTask.updateService(
      notificationTitle: 'telegram-feed',
      notificationText: _paused
          ? 'Paused: rules are not evaluated'
          : 'Watching $n channel${n == 1 ? '' : 's'}',
      notificationButtons: [
        _paused
            ? const NotificationButton(id: resumeButtonId, text: 'Resume')
            : const NotificationButton(id: pauseButtonId, text: 'Pause'),
      ],
    );
  }

  @override
  void onRepeatEvent(DateTime timestamp) => unawaited(_updateNotification());

  @override
  void onReceiveData(Object data) {
    // The UI sends 'refresh' after database changes (feeds, sources, rules).
    if (data == 'refresh') {
      unawaited(_client?.refresh());
      unawaited(_updateNotification());
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
    await _pausedSub?.cancel();
    await _tts?.dispose();
    await _client?.close();
    IsolateNameServer.removePortNameMapping(notifierPortName);
    _actions.close();
    IsolateNameServer.removePortNameMapping(corePortName);
    _core?.kill(priority: Isolate.immediate);
    await _db?.close();
  }
}
