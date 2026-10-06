import 'dart:async';

import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:push_runner/push_runner.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

/// Every logged-in account has Telegram push it to this install's FCM token
/// (ARCHITECTURE 6.5), naming the other accounts of the device, so a push says which of
/// them it is for. An account registers again when the token or the other accounts
/// change ([SettingKeys.pushRegistered]).
abstract final class PushRegistration {
  /// What [SettingKeys.pushRegistered] holds for [token] and the other accounts' ids.
  static String keyOf(String token, List<int> otherIds) =>
      '$token ${otherIds.join(',')}';

  /// Whether [stored] is a registration of [token].
  static bool isFor(String? stored, String token) =>
      stored != null && stored.startsWith('$token ');

  /// Registers what is not registered yet: [main] is the account in use, [others] the
  /// other logged-in ones, each with its database. Without a token (no push in this
  /// build or on this phone) nothing happens.
  static Future<void> ensure({
    required CoreClient main,
    required AppDatabase mainDb,
    List<({CoreClient client, AppDatabase db})> others = const [],
    Future<String?> Function() token = PushRunner.token,
    void Function(String)? log,
  }) async {
    final say = log ?? (s) => debugPrint('push: $s');
    final t = await token();
    if (t == null) {
      say('no FCM token: rules notify only while the app runs');
      return;
    }
    final accounts = [(client: main, db: mainDb), ...others];
    final ids = <int?>[];
    for (final a in accounts) {
      try {
        ids.add((await a.client.me()).id);
      } on Object catch (e) {
        say('an account is not logged in: $e');
        ids.add(null);
      }
    }
    for (var i = 0; i < accounts.length; i++) {
      if (ids[i] == null) continue;
      final otherIds = [
        for (var j = 0; j < ids.length; j++)
          if (j != i && ids[j] != null) ids[j]!,
      ]..sort();
      final key = keyOf(t, otherIds);
      final a = accounts[i];
      final stored = await a.db.setting(SettingKeys.pushRegistered);
      if (stored == key) continue;
      try {
        await a.client.registerPush(t, otherUserIds: otherIds);
        await a.db.setSetting(SettingKeys.pushRegistered, key);
        say('account ${ids[i]} registered for push');
      } on Object catch (e) {
        say('account ${ids[i]} not registered for push: $e');
      }
    }
  }

  /// [ensure] once the account in use is logged in; at once when it already is.
  static Future<void> whenLoggedIn({
    required CoreClient main,
    required AppDatabase mainDb,
    List<({CoreClient client, AppDatabase db})> others = const [],
  }) async {
    try {
      await main.authState.firstWhere((s) => s is AuthReady);
    } on StateError {
      return; // the client closed first
    }
    await ensure(main: main, mainDb: mainDb, others: others);
  }
}
