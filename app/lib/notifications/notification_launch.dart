import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../host/app_host.dart';
import '../service/notifier.dart';
import 'open_post.dart';

export 'notification_policy.dart';
export 'open_post.dart';

/// UI-side handling of notification taps: opens the post in the first feed that contains
/// its channel (SPEC), or the Telegram app for the "Open in Telegram" action.
final class NotificationLaunch {
  NotificationLaunch(this.host);
  final AppHost host;
  final _plugin = FlutterLocalNotificationsPlugin();

  Future<void> attach() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: _onResponse,
      onDidReceiveBackgroundNotificationResponse: notificationActionEntryPoint,
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final r = launch?.notificationResponse;
    if ((launch?.didNotificationLaunchApp ?? false) && r != null) {
      unawaited(_onResponse(r));
    }
  }

  Future<void> _onResponse(NotificationResponse r) async {
    final ref = PostRef.decode(r.payload);
    if (ref == null) return;
    if (r.actionId == actionOpenTelegram) {
      await openInTelegram(host.db, ref);
      return;
    }
    if (r.actionId == actionListen) return; // handled by the service host
    await openPost(host, ref);
  }
}
