import 'app_host.dart';

void platformInit() {}

Future<AppHost> startAppHost() =>
    throw UnsupportedError('no host for this platform');

Future<void> attachLaunchHandlers(AppHost host) async {}
