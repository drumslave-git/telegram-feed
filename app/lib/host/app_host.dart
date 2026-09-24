import 'package:app_db/app_db.dart';
import 'package:flutter/foundation.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../core_host.dart';
import '../notifications/notification_launch.dart';
import '../service/core_service.dart';
import '../service/reading_now.dart';
import '../sync/sync_controller.dart';

/// What the screens need from the platform: the app database, a gateway to Telegram and
/// a few facts about where the core runs. [CoreHost] implements it on Android; tests
/// inject fakes.
abstract interface class AppHost {
  AppDatabase get db;
  TelegramGateway get gateway;

  /// True when rules keep running while the app is not open (foreground service).
  bool get runningInService;

  /// Google Drive sync of feeds, rules and settings (ARCHITECTURE.md section 5.5).
  SyncController get sync;

  /// The post being read aloud; null while nothing is read (the banner under the header).
  ValueListenable<ReadingNow?> get reading;

  /// Stops the post being read; with [clear], every post waiting as well.
  void stopReading({bool clear = false});

  /// The kill switch: while on, rules notify about nothing and read nothing aloud.
  ValueListenable<bool> get paused;
  Future<void> setPaused(bool paused);

  Future<bool> get isBatteryExempt;
  Future<void> requestBatteryExemption();

  /// Closes the core and starts the app afresh, for a change of background watching.
  Future<void> restart();

  /// Logs out and wipes everything the app stored (ARCHITECTURE section 10).
  Future<void> logOutAndWipe();
  Future<void> dispose();
}

/// Platform setup before `runApp`: registers the foreground task callback.
void platformInit() => initCoreService();

/// Starts the host.
Future<AppHost> startAppHost() => CoreHost.start();

/// Attaches launch-time handlers (notification taps) once the host is up.
Future<void> attachLaunchHandlers(AppHost host) =>
    NotificationLaunch(host).attach();
