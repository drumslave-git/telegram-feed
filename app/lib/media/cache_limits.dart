import 'dart:async';

import 'package:app_db/app_db.dart';
import 'package:flutter/foundation.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

/// How long cached media stays on the phone and how large the cache may grow, as the
/// official app's Storage Usage has it for channels: media that was not used for a week
/// goes, until the reader picks another time, and there is no limit on the size until
/// the reader picks one. TDLib does the removing ([TelegramGateway.setCacheLimits]).
abstract final class CacheLimits {
  static const day = 24 * 60 * 60;
  static const _gb = 1024 * 1024 * 1024;

  /// The times the reader picks from, in seconds; 0 keeps media for good.
  static const keepChoices = [day, 2 * day, 7 * day, 30 * day, 0];
  static const defaultKeep = 7 * day;

  /// The sizes the reader picks from, in bytes; 0 is no limit.
  static const sizeChoices = [2 * _gb, 5 * _gb, 16 * _gb, 32 * _gb, 0];
  static const defaultMaxBytes = 0;

  /// The stored time, or a week where nothing readable is stored.
  static int keepOf(String? stored) {
    final v = int.tryParse(stored ?? '');
    return v == null || v < 0 ? defaultKeep : v;
  }

  /// The stored size, or no limit where nothing readable is stored.
  static int maxBytesOf(String? stored) {
    final v = int.tryParse(stored ?? '');
    return v == null || v < 0 ? defaultMaxBytes : v;
  }

  /// Hands the stored limits to TDLib, which keeps them from then on.
  static Future<void> apply(AppDatabase db, TelegramGateway gateway) async {
    try {
      await gateway.setCacheLimits(
        keepSeconds: keepOf(await db.setting(SettingKeys.cacheKeepSeconds)),
        maxBytes: maxBytesOf(await db.setting(SettingKeys.cacheMaxBytes)),
      );
    } on TelegramException catch (e) {
      debugPrint('cache: limits not set: ${e.message}');
    }
  }

  /// Applies the limits once the account is logged in and whenever one of them changes.
  /// The subscriptions are the caller's to cancel.
  static List<StreamSubscription<void>> follow(
    AppDatabase db,
    TelegramGateway gateway,
  ) => [
    gateway.authState
        .where((s) => s is AuthReady)
        .listen((_) => unawaited(apply(db, gateway))),
    for (final key in const [
      SettingKeys.cacheKeepSeconds,
      SettingKeys.cacheMaxBytes,
    ])
      // The first value is the one the login applies; after it only a change counts,
      // and the watch also speaks when another setting is written.
      db
          .watchSetting(key)
          .distinct()
          .skip(1)
          .listen((_) => unawaited(apply(db, gateway))),
  ];
}
