import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Volume down stops read-aloud, also with the screen off or locked (ARCHITECTURE 7). While
/// [watch] is on, the app holds a media session that Android gives the volume keys to
/// (`ReadAloudKeys.kt`): volume down, and a headset's pause, call [onStop] instead of
/// lowering the volume. It is let go when nothing is read, so the keys work as usual again.
final class ReadAloudKeys {
  ReadAloudKeys({required this.onStop, MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('tf/readAloudKeys') {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'stop') onStop();
    });
  }

  final MethodChannel _channel;
  final void Function() onStop;
  bool _watching = false;

  /// On while a post is read or waits to be read.
  Future<void> watch(bool on) async {
    if (on == _watching) return;
    _watching = on;
    try {
      await _channel.invokeMethod<void>('watch', on);
    } on MissingPluginException {
      // An engine without the app's channels: the keys keep their usual meaning.
    } on PlatformException catch (e) {
      debugPrint('read-aloud keys: $e');
    }
  }
}
