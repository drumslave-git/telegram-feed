import '../core_host.dart';
import '../notifications/notification_launch.dart';
import '../service/core_service.dart';
import 'app_host.dart';

void platformInit() => initCoreService();

Future<AppHost> startAppHost() => CoreHost.start();

Future<void> attachLaunchHandlers(AppHost host) =>
    NotificationLaunch(host).attach();
