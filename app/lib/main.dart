import 'dart:io';
import 'dart:ui';

import 'package:core/core.dart';
import 'package:core/native_isolate.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

/// Telegram API credentials come from `--dart-define`; never committed (SPEC section 7).
const int tgApiId = int.fromEnvironment('TG_API_ID');
const String tgApiHash = String.fromEnvironment('TG_API_HASH');
const bool tgTestDc = bool.fromEnvironment('TG_TEST_DC');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TelegramFeedApp());
}

/// Finds the core (already running, e.g. under the phase-2 service) or spawns it.
Future<CoreClient> connectCore() async {
  var port = IsolateNameServer.lookupPortByName(corePortName);
  if (port == null) {
    final support = await getApplicationSupportDirectory();
    port = await spawnCoreIsolate(
      CoreBootstrap(
        apiId: tgApiId,
        apiHash: tgApiHash,
        databaseDirectory: '${support.path}/tdlib',
        filesDirectory: '${support.path}/tdlib/files',
        useTestDc: tgTestDc,
        deviceModel: Platform.isAndroid ? 'Android' : Platform.operatingSystem,
        systemVersion: Platform.operatingSystemVersion,
      ),
    );
    IsolateNameServer.removePortNameMapping(corePortName);
    IsolateNameServer.registerPortWithName(port, corePortName);
  }
  return CoreClient.connect(port);
}

class TelegramFeedApp extends StatelessWidget {
  const TelegramFeedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'telegram-feed',
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      home: const CoreStatusScreen(),
    );
  }
}

/// Placeholder home until P1-7/P1-8: shows the core's auth state.
class CoreStatusScreen extends StatefulWidget {
  const CoreStatusScreen({super.key});

  @override
  State<CoreStatusScreen> createState() => _CoreStatusScreenState();
}

class _CoreStatusScreenState extends State<CoreStatusScreen> {
  late final Future<CoreClient> _core = connectCore();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('telegram-feed')),
      body: Center(
        child: FutureBuilder<CoreClient>(
          future: _core,
          builder: (context, snap) {
            if (snap.hasError) return Text('core failed: ${snap.error}');
            final core = snap.data;
            if (core == null) return const CircularProgressIndicator();
            return StreamBuilder<AuthState>(
              stream: core.authState,
              builder: (context, s) {
                final state = s.data ?? core.currentAuthState;
                debugPrint('auth: ${state.runtimeType}');
                return Text('Auth: ${state.runtimeType}');
              },
            );
          },
        ),
      ),
    );
  }
}
