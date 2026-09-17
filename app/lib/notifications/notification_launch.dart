import 'dart:async';

import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core_host.dart';
import '../feeds/timeline_screen.dart';
import '../service/notifier.dart';

/// Global navigator so notification taps can push screens from outside the tree.
final navigatorKey = GlobalKey<NavigatorState>();

/// Notification policy access (needed for the urgent channel's DND bypass).
abstract final class NotificationPolicy {
  static const _channel = MethodChannel('tf/notifications');

  static Future<bool> get isGranted async {
    try {
      return await _channel.invokeMethod<bool>('isPolicyAccessGranted') ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> openSettings() =>
      _channel.invokeMethod<void>('openPolicyAccessSettings');
}

/// UI-side handling of notification taps: opens the post in the first feed that contains
/// its channel (SPEC), or the Telegram app for the "Open in Telegram" action.
final class NotificationLaunch {
  NotificationLaunch(this.host);
  final CoreHost host;
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

Future<void> openInTelegram(AppDatabase db, PostRef ref) async {
  final username = (await db.allWatched())
      .where((w) => w.chatId == ref.chatId)
      .map((w) => w.username)
      .firstOrNull;
  final uri = telegramPostUri(
    chatId: ref.chatId,
    messageId: ref.messageId,
    username: username,
  );
  final web = telegramPostWebUri(chatId: ref.chatId, messageId: ref.messageId);
  for (final u in [uri, web]) {
    if (u != null && await launchUrl(u, mode: LaunchMode.externalApplication)) {
      return;
    }
  }
}

/// Pushes the timeline of the first feed containing the post's channel, focused on the post.
Future<void> openPost(CoreHost host, PostRef ref) async {
  final feeds = await host.db.feedsContaining(ref.chatId);
  final nav = navigatorKey.currentState;
  if (feeds.isEmpty || nav == null) return;
  await nav.push(
    MaterialPageRoute<void>(
      builder: (_) => TimelineScreen(
        db: host.db,
        gateway: host.gateway,
        feed: feeds.first,
        focusChatId: ref.chatId,
        focusMessageId: ref.messageId,
      ),
    ),
  );
}
