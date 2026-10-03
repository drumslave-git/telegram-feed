import 'dart:async';

import 'package:flutter/services.dart';

/// The touches the app answers with a vibration, each with the feedback the official app
/// gives it.
abstract final class Haptics {
  /// A long press took hold (a selection, a menu, a link): Android's `LONG_PRESS`.
  static void longPress() => unawaited(HapticFeedback.vibrate());

  /// A reaction was set or taken back: Android's `KEYBOARD_TAP`.
  static void reaction() => unawaited(HapticFeedback.mediumImpact());

  /// Something was refused, like one post more than a selection holds: a buzz of 200 ms.
  /// No feedback constant is that long, so the activity vibrates itself.
  static void refused() => unawaited(_buzz(200));

  static Future<void> _buzz(int milliseconds) async {
    try {
      await const MethodChannel('tf/app')
          .invokeMethod<void>('buzz', milliseconds);
    } on MissingPluginException {
      await HapticFeedback.vibrate(); // no activity: a widget test
    } on PlatformException {
      await HapticFeedback.vibrate(); // a device without a vibrator says so
    }
  }
}
