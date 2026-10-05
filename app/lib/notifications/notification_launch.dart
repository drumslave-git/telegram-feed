import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:app_db/app_db.dart';
import 'package:flutter/foundation.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../host/accounts.dart';
import '../host/app_host.dart';
import '../service/core_bootstrap.dart' show appPaths;
import '../service/notifier.dart';
import 'open_post.dart';

export 'notification_policy.dart';
export 'open_post.dart';

/// UI-side handling of notification taps: opens the post in the feed of the rule that
/// raised the notification (the first feed that holds the channel when that feed is gone),
/// or the Telegram app for the "Open in Telegram" action.
final class NotificationLaunch {
  NotificationLaunch(this.host);
  final AppHost host;
  final _plugin = FlutterLocalNotificationsPlugin();

  Future<void> attach() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        // The same icon as the alerts' notifier: this initialisation writes the
        // plugin's default icon into shared preferences, where it outlives the isolate.
        android: AndroidInitializationSettings(notificationIcon),
      ),
      onDidReceiveNotificationResponse: _onResponse,
      onDidReceiveBackgroundNotificationResponse: notificationActionEntryPoint,
    );
    if (_pending case final ref?) {
      // This host came up for the tap on a notification of its account.
      _pending = null;
      unawaited(openPost(host, ref));
      return;
    }
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final r = launch?.notificationResponse;
    if ((launch?.didNotificationLaunchApp ?? false) && r != null) {
      unawaited(_onResponse(r));
    }
  }

  /// The post of a tap on another account's notification: opened once the host of that
  /// account is up.
  static PostRef? _pending;

  Future<void> _onResponse(NotificationResponse r) async {
    final ref = PostRef.decode(r.payload);
    if (ref == null) return;
    // Handled by the alerts (rule_alerts.dart).
    if (r.actionId == actionListen || r.actionId == actionStop) return;
    // The tap, or "Open in Telegram", took the notification out of the shade; whoever
    // posts them forgets what it listed.
    IsolateNameServer.lookupPortByName(notifierPortName)
        ?.send({'type': notificationTapped, 'payload': r.payload});
    final store = await _otherAccountOf(ref);
    if (r.actionId == actionOpenTelegram) {
      if (store == null) return openInTelegram(host.db, ref);
      // The channel's username is in the database of the account that watches it.
      final db = AppDatabase(appDatabaseFile(File(store.dbOf(ref.account))));
      try {
        await openInTelegram(db, ref);
      } finally {
        await db.close();
      }
      return;
    }
    final switchTo = AccountSwitch.root;
    if (store == null || switchTo == null) return openPost(host, ref);
    // A post of another account: that account comes up first, and its host opens it.
    _pending = ref;
    await store.setActive(ref.account);
    await switchTo();
  }

  /// The store, when [ref] names an account that is on this device and is not the one in
  /// use; null otherwise.
  Future<AccountStore?> _otherAccountOf(PostRef ref) async {
    if (ref.account == 0) return null;
    try {
      final store = AccountStore((await appPaths()).support);
      final (:accounts, :active) = await store.load();
      return ref.account != active && accounts.any((a) => a.id == ref.account)
          ? store
          : null;
    } on Object catch (e) {
      debugPrint('accounts: not read for a tap: $e');
      return null;
    }
  }
}
