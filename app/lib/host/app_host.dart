import 'package:app_db/app_db.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'app_host_stub.dart'
    if (dart.library.io) 'app_host_native.dart'
    if (dart.library.js_interop) 'app_host_web.dart'
    as platform;

/// What the screens need from the platform: the app database, a gateway to Telegram and
/// a few facts about where the core runs. Android: [CoreHost] talks to the core isolate in
/// the foreground service. Web: [WebHost] runs TDLib (tdweb) and the rules in the page.
abstract interface class AppHost {
  AppDatabase get db;
  TelegramGateway get gateway;

  /// True when rules keep running while the app is not open (Android foreground service).
  bool get runningInService;

  Future<bool> get isBatteryExempt;
  Future<void> requestBatteryExemption();

  /// Logs out and wipes everything the app stored (ARCHITECTURE section 10).
  Future<void> logOutAndWipe();
  Future<void> dispose();
}

/// Platform setup before `runApp` (Android registers the foreground task callback).
void platformInit() => platform.platformInit();

/// Starts the host for this platform.
Future<AppHost> startAppHost() => platform.startAppHost();

/// Attaches launch-time handlers (notification taps) once the host is up.
Future<void> attachLaunchHandlers(AppHost host) =>
    platform.attachLaunchHandlers(host);
