import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Notification policy access (needed for the urgent channel's DND bypass). Android only;
/// elsewhere the channel has no handler and access reads as not granted.
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

  /// Function form for injection into widgets.
  static Future<bool> isGrantedFn() => isGranted;
}

/// Android's permission to notify at all. Without it a rule matches in silence, so the
/// app asks where it can say why: after the first rule is saved, and from Notifications
/// and sounds. Android grants the ask once, so it is never spent on a blank screen.
abstract final class NotificationPermissionAsk {
  static const _channel = MethodChannel('tf/notifications');

  /// Function form for injection into widgets.
  static Future<bool> grantedFn() => granted;

  static Future<bool> get granted async {
    try {
      return await _channel.invokeMethod<bool>('areNotificationsEnabled') ??
          true;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return true;
    }
  }

  /// Asks Android for it, and answers whether it is granted afterwards.
  static Future<bool> request() async {
    try {
      final now = await FlutterForegroundTask.requestNotificationPermission();
      return now == NotificationPermission.granted;
    } on Object {
      return granted;
    }
  }
}
