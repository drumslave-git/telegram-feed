import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android's secure window flag: while anything holds it, the task switcher shows a blank
/// card and screenshots are refused. The app lock holds it while a PIN is set, a timeline
/// and the viewer while they show protected content; it goes when the last one lets go.
abstract final class SecureWindow {
  static final _holders = <Object>{};

  static Future<void> hold(Object holder) async {
    final first = _holders.isEmpty;
    _holders.add(holder);
    if (first) await _apply(true);
  }

  static Future<void> release(Object holder) async {
    if (_holders.remove(holder) && _holders.isEmpty) await _apply(false);
  }

  /// Holds or lets go as [secure] says.
  static Future<void> set(Object holder, {required bool secure}) =>
      secure ? hold(holder) : release(holder);

  static Future<void> _apply(bool secure) async {
    try {
      await const MethodChannel('tf/app').invokeMethod<void>('secure', secure);
    } on MissingPluginException {
      // No window to tell: a test, or an engine without the app's channels.
    } on PlatformException catch (e) {
      debugPrint('secure window: $e');
    }
  }
}
