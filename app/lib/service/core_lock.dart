import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

/// TDLib may be polled by one isolate of the process at a time: a second receive pump
/// aborts it ("Receive must not be called simultaneously from two different threads").
/// The app's engine, the foreground service's and a push run's can all start a core, so
/// whoever does holds this lock first, from before the core is spawned until it has
/// handed TDLib back (ARCHITECTURE 8). The lock is a name in `IsolateNameServer`, which
/// every engine of the process shares and which registers a name once only.
abstract final class CoreLock {
  static const _name = 'telegram_feed.core_lock';

  /// Whether a core is running or starting in this process.
  static bool get held => IsolateNameServer.lookupPortByName(_name) != null;

  /// Takes the lock. While another holds it, the lock is waited for, and with
  /// [standDownHolder] the core it registered is asked to stand down ([standDown]). A
  /// holder that has not let go after [wait] is taken as gone (its engine died) when
  /// [force]; otherwise, and when [cancelled] says so, null is returned and nothing is
  /// held.
  static Future<ReceivePort?> take({
    Duration wait = const Duration(seconds: 20),
    bool force = false,
    bool standDownHolder = true,
    bool Function()? cancelled,
  }) async {
    final token = ReceivePort();
    final end = DateTime.now().add(wait);
    var asked = false;
    while (!IsolateNameServer.registerPortWithName(token.sendPort, _name)) {
      if (cancelled?.call() ?? false) {
        token.close();
        return null;
      }
      if (standDownHolder && !asked) {
        asked = await standDown();
      }
      if (DateTime.now().isAfter(end)) {
        if (!force) {
          token.close();
          return null;
        }
        debugPrint('core: the lock was not let go; taking it');
        IsolateNameServer.removePortNameMapping(_name);
        continue;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return token;
  }

  /// Lets the lock go: the core of [token]'s holder has handed TDLib back.
  static void release(ReceivePort? token) {
    if (token == null) return;
    if (IsolateNameServer.lookupPortByName(_name) == token.sendPort) {
      IsolateNameServer.removePortNameMapping(_name);
    }
    token.close();
  }

  /// Asks the core registered in this process to hand TDLib back and waits for it; its
  /// holder lets the lock go afterwards. False when no core is registered yet.
  static Future<bool> standDown() async {
    final port = IsolateNameServer.lookupPortByName(corePortName);
    if (port == null) return false;
    IsolateNameServer.removePortNameMapping(corePortName);
    debugPrint('core: a core is still registered; asking it to stand down');
    try {
      final client = await CoreClient.connect(port)
          .timeout(const Duration(seconds: 5));
      await client.shutdown().timeout(const Duration(seconds: 10));
      await client.close();
    } on Object catch (e) {
      debugPrint('core: stand down failed: $e');
    }
    return true;
  }
}
