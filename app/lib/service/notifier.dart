import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_plan.dart';

export 'notification_plan.dart';

/// Posts notifications for rule matches. Lives in the service host isolate (plugins with
/// platform callbacks cannot run in the core isolate, spike P0-2).
final class Notifier {
  Notifier([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// The last post shown per chat; only its title and channel are reused, to re-post that
  /// chat's group summary after a cancellation.
  final _lastPerChat = <int, NotificationPlan>{};

  Future<void> init() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_feed'),
      ),
      onDidReceiveNotificationResponse: notificationActionEntryPoint,
      onDidReceiveBackgroundNotificationResponse: notificationActionEntryPoint,
    );
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        channelSilent,
        'Silent posts',
        description: 'Rules with silent priority: no sound, no heads-up',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
      ),
    );
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        channelNormal,
        'Posts',
        description: 'Rules with normal priority',
        importance: Importance.defaultImportance,
      ),
    );
    await _ensureUrgentChannel();
  }

  /// Which urgent channel to post on. Re-checked before every urgent notification so that
  /// granting policy access later takes effect without restarting the service.
  Future<String> _ensureUrgentChannel() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return channelUrgent;
    final bypass = await android.hasNotificationPolicyAccess() ?? false;
    if (bypass == _urgentBypassesDnd) return _urgentChannel;
    await android.createNotificationChannel(
      AndroidNotificationChannel(
        bypass ? channelUrgentDnd : channelUrgent,
        'Urgent posts',
        description: bypass
            ? 'Rules with urgent priority; bypasses Do Not Disturb'
            : 'Rules with urgent priority',
        importance: Importance.high,
        bypassDnd: bypass,
      ),
    );
    // One "Urgent posts" row in the system settings, not two.
    await android.deleteNotificationChannel(
      channelId: bypass ? channelUrgent : channelUrgentDnd,
    );
    _urgentBypassesDnd = bypass;
    return _urgentChannel;
  }

  bool? _urgentBypassesDnd;
  String get _urgentChannel =>
      (_urgentBypassesDnd ?? false) ? channelUrgentDnd : channelUrgent;

  static Importance _importanceOf(String planChannel) => switch (planChannel) {
    channelSilent => Importance.low,
    channelUrgent => Importance.high,
    _ => Importance.defaultImportance,
  };

  static Priority _priorityOf(String planChannel) => switch (planChannel) {
    channelSilent => Priority.low,
    channelUrgent => Priority.high,
    _ => Priority.defaultPriority,
  };

  Future<void> show(NotificationPlan plan) async {
    final channelId = plan.channelId == channelUrgent
        ? await _ensureUrgentChannel()
        : plan.channelId;
    await _plugin.show(
      id: plan.id,
      title: plan.title,
      body: plan.body,
      payload: plan.payload,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelId,
          importance: _importanceOf(plan.channelId),
          priority: _priorityOf(plan.channelId),
          groupKey: plan.groupKey,
          styleInformation: BigTextStyleInformation(plan.body),
          actions: const [
            AndroidNotificationAction(actionListen, 'Listen'),
            AndroidNotificationAction(
              actionOpenTelegram,
              'Open in Telegram',
              showsUserInterface: true,
              cancelNotification: true,
            ),
          ],
        ),
      ),
    );
    final chatId = PostRef.decode(plan.payload)?.chatId;
    if (chatId != null) _lastPerChat[chatId] = plan;
    final live = await _liveInGroup(plan.groupKey, plan.summaryId);
    // The post just shown counts even when Android has not listed it yet.
    live.add(plan.id);
    await _showSummary(plan, channelId, live.length);
  }

  /// Group summary per channel so several posts collapse into one row.
  Future<void> _showSummary(
    NotificationPlan plan,
    String channelId,
    int count,
  ) => _plugin.show(
    id: plan.summaryId,
    title: plan.title,
    body: '$count new post${count == 1 ? '' : 's'}',
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelId,
        importance: _importanceOf(plan.channelId),
        priority: _priorityOf(plan.channelId),
        groupKey: plan.groupKey,
        setAsGroupSummary: true,
      ),
    ),
  );

  /// Ids of a group's post notifications that Android still holds, the summary excluded.
  ///
  /// The summary's count is asked of Android rather than tallied: posts the user swiped
  /// away, tapped or had deleted must not keep inflating "N new posts".
  Future<Set<int>> _liveInGroup(String groupKey, int summaryId) async {
    try {
      return {
        for (final n in await _plugin.getActiveNotifications())
          if (n.groupKey == groupKey && n.id != null && n.id != summaryId)
            n.id!,
      };
    } on PlatformException catch (e) {
      // Android below 6.0 has no such query; the count then covers this post alone.
      debugPrint('notifier: active notifications unavailable: $e');
      return <int>{};
    } on MissingPluginException {
      return <int>{};
    }
  }

  /// Drops notifications for deleted posts (ARCHITECTURE 6.2: cancel on delete), and keeps
  /// the group summary honest: it goes when the last post of its channel does.
  Future<void> cancel(int chatId, List<int> messageIds) async {
    for (final id in messageIds) {
      await _plugin.cancel(id: NotificationPlan.idFor(chatId, id));
    }
    final plan = _lastPerChat[chatId];
    if (plan == null) return;
    final live = await _liveInGroup(plan.groupKey, plan.summaryId);
    if (live.isEmpty) {
      _lastPerChat.remove(chatId);
      await _plugin.cancel(id: plan.summaryId);
      return;
    }
    await _showSummary(
      plan,
      plan.channelId == channelUrgent ? _urgentChannel : plan.channelId,
      live.length,
    );
  }
}

/// Entry point for action taps. For background actions Android starts a fresh isolate, so
/// the response is forwarded to whoever registered [notifierPortName] (the service host);
/// for foreground taps the app's own handler also receives it through the plugin.
@pragma('vm:entry-point')
void notificationActionEntryPoint(NotificationResponse response) {
  final port = IsolateNameServer.lookupPortByName(notifierPortName);
  if (port == null) {
    debugPrint('notifier: no host port for action ${response.actionId}');
    return;
  }
  port.send({
    'actionId': response.actionId,
    'payload': response.payload,
    'type': response.notificationResponseType.name,
  });
}
