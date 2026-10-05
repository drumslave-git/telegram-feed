/// The native half of push (ARCHITECTURE 6.5): the FCM token, the queue of what waits
/// for a run, and the run itself, which the app's `pushMain` hosts in an engine of its
/// own while the app is closed.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

/// Something that waits for a run: a push, a notification's button pressed while nothing
/// ran, or a new FCM token to register.
sealed class PushItem {
  const PushItem();

  static PushItem? decode(String raw) {
    final Object? m;
    try {
      m = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    return switch (m) {
      {'push': final String payload} => PushMessage(payload),
      {'action': final Map<String, Object?> action} => PushAction(action),
      {'register': true} => const PushRegister(),
      _ => null,
    };
  }
}

/// A push from Telegram: the FCM message's data as JSON, with `google.sent_time`.
final class PushMessage extends PushItem {
  const PushMessage(this.payload);
  final String payload;
}

/// A notification's button pressed while nothing ran: what the notification plugin
/// reported of it.
final class PushAction extends PushItem {
  const PushAction(this.response);
  final Map<String, Object?> response;
}

/// FCM gave the app a new token, which every account has to register.
final class PushRegister extends PushItem {
  const PushRegister();
}

abstract final class PushRunner {
  static const channel = MethodChannel('tf/push');

  /// The FCM token; null where push is not available: a build without a Firebase
  /// project of its own, a phone without Google Play services, or no platform side.
  static Future<String?> token() async {
    try {
      return await channel.invokeMethod<String>('token');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Everything that waits for a run, taken off the queue.
  static Future<List<PushItem>> take() async {
    final raw = await channel.invokeListMethod<String>('take') ?? const [];
    return [for (final r in raw) ?PushItem.decode(r)];
  }

  /// Queues a notification's button pressed while nothing ran, and starts a run for it.
  static Future<void> startRun(Map<String, Object?> response) =>
      channel.invokeMethod<void>('queue', jsonEncode({'action': response}));

  /// While this engine hosts a run: [onQueued] whenever something more was queued, and
  /// [onStop] when Android ends the run early.
  static void listen({
    required void Function() onQueued,
    required void Function() onStop,
  }) {
    channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'queued':
          onQueued();
        case 'stop':
          onStop();
      }
    });
  }

  /// The run is over: the job ends and its engine goes.
  static Future<void> done() => channel.invokeMethod<void>('done');
}
