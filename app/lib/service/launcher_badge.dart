import 'dart:async';

import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

/// The number on the app's icon, as the official app's badge counter: the unread posts
/// of the account's channels, or the channels that have unread posts, with or without
/// the muted ones, or no number at all (Notifications and sounds). It lives beside the
/// core, like the rule alerts, so the number follows while the app is closed, and is
/// counted again a moment after a post arrived or was read. The app calls [refresh] when
/// a switch changes: the settings are written in the app, which the service's own
/// connection to the database does not hear of.
/// `LauncherBadge.kt` hands it to the launchers that show numbers.
class LauncherBadge {
  LauncherBadge({
    required this.db,
    required this.channels,
    required this.changes,
    MethodChannel? channel,
    this.settle = const Duration(seconds: 1),
  }) : _channel = channel ?? const MethodChannel('tf/badge');

  /// Counts what the core at [client] reads.
  LauncherBadge.of(CoreClient client, {required AppDatabase db})
    : this(
        db: db,
        channels: client.myChannels,
        changes: [client.postEvents, client.readUpdates],
      );

  final AppDatabase db;

  /// The account's channels, each with how many of its posts are unread.
  final Future<List<Channel>> Function() channels;

  /// Whatever may change the number: a post that arrives or goes, a channel that is read.
  final List<Stream<Object?>> changes;

  /// How long the counting waits after a change, so a burst of posts is counted once.
  final Duration settle;
  final MethodChannel _channel;
  final _subs = <StreamSubscription<Object?>>[];
  Timer? _timer;
  int? _sent;

  /// The number for [channels]: their unread posts, or with [posts] off how many of them
  /// have unread posts. A channel marked as unread counts as one. Muted channels count
  /// only with [muted].
  static int countOf(
    Iterable<Channel> channels, {
    required bool muted,
    required bool posts,
  }) {
    var count = 0;
    for (final c in channels) {
      if (c.isMuted && !muted) continue;
      final unread = c.unreadCount > 0
          ? c.unreadCount
          : c.isMarkedUnread
          ? 1
          : 0;
      count += posts ? unread : unread.clamp(0, 1);
    }
    return count;
  }

  Future<void> start() async {
    for (final stream in changes) {
      _subs.add(stream.listen((_) => _schedule()));
    }
    await refresh();
  }

  void _schedule() => _timer ??= Timer(settle, () {
    _timer = null;
    unawaited(refresh());
  });

  /// The settings that decide the number.
  static const settings = [
    SettingKeys.badgeEnabled,
    SettingKeys.badgeMuted,
    SettingKeys.countUnreadPosts,
  ];

  /// Counts and, when the number changed, tells the launcher.
  Future<void> refresh() async {
    var count = 0;
    try {
      if (await db.setting(SettingKeys.badgeEnabled) != 'false') {
        count = countOf(
          await channels(),
          muted: await db.setting(SettingKeys.badgeMuted) == 'true',
          posts: await db.setting(SettingKeys.countUnreadPosts) != 'false',
        );
      }
    } on Object catch (e) {
      // Not logged in, or the core is going: nothing is unread.
      debugPrint('badge: not counted: $e');
    }
    if (count == _sent) return;
    _sent = count;
    try {
      await _channel.invokeMethod<void>('set', count);
    } on MissingPluginException {
      // An engine without the app's channels.
    } on PlatformException catch (e) {
      debugPrint('badge: $e');
    }
  }

  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
  }
}
