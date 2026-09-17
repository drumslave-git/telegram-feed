import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import '../service/notification_plan.dart';

/// Browser `Notification` API for rule matches while a tab is open (ARCHITECTURE section 8,
/// web). No channels or grouping: the tab's own notifications are replaced per post by tag.
final class BrowserNotifier {
  final _open = <int, web.Notification>{};

  bool get supported => globalContext.has('Notification');

  String get permission =>
      supported ? web.Notification.permission : 'unsupported';

  /// Asks for permission once; browsers only prompt from a page the user has interacted with,
  /// so a refusal here just means notifications stay off until the next visit.
  Future<void> init() async {
    if (!supported || web.Notification.permission != 'default') return;
    try {
      await web.Notification.requestPermission().toDart;
    } catch (e) {
      debugPrint('notifications: $e');
    }
  }

  Future<void> show(NotificationPlan plan, {VoidCallback? onTap}) async {
    if (!supported || web.Notification.permission != 'granted') return;
    final n = web.Notification(
      plan.title,
      web.NotificationOptions(
        body: plan.body,
        tag: 'post-${plan.id}',
        silent: plan.channelId == channelSilent,
      ),
    );
    n.onclick = ((web.Event _) {
      web.window.focus();
      n.close();
      onTap?.call();
    }).toJS;
    n.onclose = ((web.Event _) => _open.remove(plan.id)).toJS;
    _open[plan.id] = n;
  }

  Future<void> cancel(int chatId, List<int> messageIds) async {
    for (final id in messageIds) {
      _open.remove(NotificationPlan.idFor(chatId, id))?.close();
    }
  }
}
