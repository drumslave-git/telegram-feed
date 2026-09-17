import 'dart:convert';
import 'dart:ui';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notification channels (ARCHITECTURE.md section 6.3), one per rule priority.
const channelSilent = 'posts_silent';
const channelNormal = 'posts_normal';
const channelUrgent = 'posts_urgent';

/// Action ids on post notifications.
const actionListen = 'listen';
const actionOpenTelegram = 'open_tg';

/// Port name under which the service host receives notification actions
/// (the background action isolate has no other way to reach it).
const notifierPortName = 'telegram_feed.notifier';

/// Payload carried by every post notification and its actions.
final class PostRef {
  const PostRef(this.chatId, this.messageId);
  final int chatId;
  final int messageId;

  String encode() => jsonEncode({'chatId': chatId, 'messageId': messageId});

  static PostRef? decode(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final m = jsonDecode(payload) as Map<String, Object?>;
      return PostRef(m['chatId'] as int, m['messageId'] as int);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}

/// What to post for a match: pure, so it can be unit-tested without the plugin.
final class NotificationPlan {
  const NotificationPlan({
    required this.id,
    required this.channelId,
    required this.title,
    required this.body,
    required this.groupKey,
    required this.summaryId,
    required this.payload,
  });
  final int id;
  final String channelId;
  final String title;
  final String body;
  final String groupKey;
  final int summaryId;
  final String payload;

  static String channelFor(RulePriority p) => switch (p) {
    RulePriority.silent => channelSilent,
    RulePriority.normal => channelNormal,
    RulePriority.urgent => channelUrgent,
  };

  /// Stable notification id for a post (so a repeat show replaces, and cancel finds it).
  static int idFor(int chatId, int messageId) =>
      Object.hash(chatId, messageId) & 0x7fffffff;

  /// Ids for group summaries live in a separate range keyed by chat.
  static int summaryIdFor(int chatId) =>
      (chatId.hashCode & 0x3fffffff) | 0x40000000;

  factory NotificationPlan.forMatch(
    MatchEvent m, {
    required String channelTitle,
  }) {
    final text = m.post.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final body = text.length > 240 ? '${text.substring(0, 240)}…' : text;
    return NotificationPlan(
      id: idFor(m.post.chatId, m.post.messageId),
      channelId: channelFor(m.priority),
      title: channelTitle.isEmpty ? 'New post' : channelTitle,
      body: body,
      groupKey: 'chat-${m.post.chatId}',
      summaryId: summaryIdFor(m.post.chatId),
      payload: PostRef(m.post.chatId, m.post.messageId).encode(),
    );
  }
}

/// Posts notifications for rule matches. Lives in the service host isolate (plugins with
/// platform callbacks cannot run in the core isolate, spike P0-2).
final class Notifier {
  Notifier([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final _shownPerChat = <int, int>{};

  Future<void> init() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
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
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        channelUrgent,
        'Urgent posts',
        description: 'Rules with urgent priority; bypasses Do Not Disturb once policy access is granted',
        importance: Importance.high,
        bypassDnd: true,
      ),
    );
  }

  Future<void> show(NotificationPlan plan) async {
    final importance = switch (plan.channelId) {
      channelSilent => Importance.low,
      channelUrgent => Importance.high,
      _ => Importance.defaultImportance,
    };
    final priority = switch (plan.channelId) {
      channelSilent => Priority.low,
      channelUrgent => Priority.high,
      _ => Priority.defaultPriority,
    };
    await _plugin.show(
      id: plan.id,
      title: plan.title,
      body: plan.body,
      payload: plan.payload,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          plan.channelId,
          plan.channelId,
          importance: importance,
          priority: priority,
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
    // Group summary per channel so several posts collapse into one row.
    final chatId = PostRef.decode(plan.payload)?.chatId;
    if (chatId != null) {
      final n = _shownPerChat[chatId] = (_shownPerChat[chatId] ?? 0) + 1;
      await _plugin.show(
        id: plan.summaryId,
        title: plan.title,
        body: '$n new post${n == 1 ? '' : 's'}',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            plan.channelId,
            plan.channelId,
            importance: importance,
            priority: priority,
            groupKey: plan.groupKey,
            setAsGroupSummary: true,
          ),
        ),
      );
    }
  }

  /// Drops notifications for deleted posts (ARCHITECTURE 6.2: cancel on delete).
  Future<void> cancel(int chatId, List<int> messageIds) async {
    for (final id in messageIds) {
      await _plugin.cancel(id: NotificationPlan.idFor(chatId, id));
    }
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
