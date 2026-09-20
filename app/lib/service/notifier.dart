import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_plan.dart';

export 'notification_plan.dart';

/// White glyph on transparency, the way Android wants a status bar icon: the system tints
/// it like every other app's. It is named on every notification, not left to the plugin's
/// default, because that default lives in shared preferences and the isolate that
/// initialises last would decide it.
const notificationIcon = 'ic_stat_feed';

/// Posts notifications for rule matches. Lives in the service host isolate (plugins with
/// platform callbacks cannot run in the core isolate, spike P0-2).
final class Notifier {
  Notifier([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// The last post shown per chat; only its title and channel are reused, to re-post that
  /// chat's group summary after a cancellation.
  final _lastPerChat = <int, NotificationPlan>{};

  /// Sound and vibration the reader chose per priority (H-33). Android fixes a channel's
  /// sound when it is created, so a change means a channel under a new id and the old one
  /// deleted; [_tagOf] turns the choice into that id.
  NotificationSounds _sounds = const NotificationSounds();

  /// Channel ids in use, by the logical priority of the plan.
  final _actual = <String, String>{};

  /// The suffix a choice gives a channel id. The default choice adds nothing, so an app
  /// that was installed before this setting keeps the channels it has, and only a reader
  /// who picks a sound gets new ones.
  String _suffixOf(String? sound, bool vibrate) {
    if ((sound ?? '').isEmpty && vibrate) return '';
    final words = '${sound ?? ''}|$vibrate';
    return '_${words.hashCode.toUnsigned(20).toRadixString(36)}';
  }

  Future<void> init({
    NotificationSounds sounds = const NotificationSounds(),
  }) async {
    _sounds = sounds;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(notificationIcon),
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
    _actual[channelSilent] = channelSilent;
    final normalId =
        channelNormal + _suffixOf(sounds.normalSound, sounds.normalVibrate);
    await android.createNotificationChannel(
      AndroidNotificationChannel(
        normalId,
        'Posts',
        description: 'Rules with normal priority',
        importance: Importance.defaultImportance,
        sound: (sounds.normalSound ?? '').isEmpty
            ? null
            : UriAndroidNotificationSound(sounds.normalSound!),
        enableVibration: sounds.normalVibrate,
      ),
    );
    _actual[channelNormal] = normalId;
    await _ensureUrgentChannel();
    // One row per priority in the system settings: the channels of earlier choices go.
    await _deleteStaleChannels(android);
  }

  /// Channels of sounds the reader has moved on from; the ids in use are kept.
  Future<void> _deleteStaleChannels(
    AndroidFlutterLocalNotificationsPlugin android,
  ) async {
    final keep = {..._actual.values, channelSilent, _urgentChannel};
    final existing = await android.getNotificationChannels() ?? const [];
    for (final channel in existing) {
      final id = channel.id;
      if (keep.contains(id)) continue;
      if (!id.startsWith(channelNormal) && !id.startsWith(channelUrgent)) {
        continue;
      }
      await android.deleteNotificationChannel(channelId: id);
    }
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
    if (bypass == _urgentBypassesDnd && _actual[channelUrgent] != null) {
      return _urgentChannel;
    }
    _urgentBypassesDnd = bypass;
    final id = _urgentChannel;
    await android.createNotificationChannel(
      AndroidNotificationChannel(
        id,
        'Urgent posts',
        description: bypass
            ? 'Rules with urgent priority; bypasses Do Not Disturb'
            : 'Rules with urgent priority',
        importance: Importance.high,
        bypassDnd: bypass,
        sound: (_sounds.urgentSound ?? '').isEmpty
            ? null
            : UriAndroidNotificationSound(_sounds.urgentSound!),
        enableVibration: _sounds.urgentVibrate,
      ),
    );
    _actual[channelUrgent] = id;
    // One "Urgent posts" row in the system settings, not two.
    final suffix = _suffixOf(_sounds.urgentSound, _sounds.urgentVibrate);
    await android.deleteNotificationChannel(
      channelId: (bypass ? channelUrgent : channelUrgentDnd) + suffix,
    );
    return id;
  }

  bool? _urgentBypassesDnd;

  /// The urgent channel in use: the Do-Not-Disturb one when policy access was granted, and
  /// the sound the reader chose in its id, since Android fixes it at creation.
  String get _urgentChannel {
    final base = (_urgentBypassesDnd ?? false)
        ? channelUrgentDnd
        : channelUrgent;
    return base + _suffixOf(_sounds.urgentSound, _sounds.urgentVibrate);
  }

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
        // The reader's sound is in the channel's id, so the plan's priority is looked up.
        : _actual[plan.channelId] ?? plan.channelId;
    await _plugin.show(
      id: plan.id,
      title: plan.title,
      body: plan.body,
      payload: plan.payload,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelId,
          icon: notificationIcon,
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
        icon: notificationIcon,
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
      plan.channelId == channelUrgent
          ? _urgentChannel
          : _actual[plan.channelId] ?? plan.channelId,
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
