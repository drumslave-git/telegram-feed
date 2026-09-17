import 'package:flutter/services.dart';

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
