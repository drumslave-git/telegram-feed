import 'package:flutter/material.dart';

import 'auth/login_screens.dart';
import 'core_host.dart';
import 'feeds/feeds_screen.dart';
import 'home/home_placeholder.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TelegramFeedApp());
}

class TelegramFeedApp extends StatelessWidget {
  const TelegramFeedApp({super.key, this.host});

  /// Injected in tests; the real app starts its own.
  final Future<CoreHost>? host;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'telegram-feed',
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      home: _Root(host: host ?? CoreHost.start()),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root({required this.host});
  final Future<CoreHost> host;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CoreHost>(
      future: host,
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
            body: Center(
              child: Text('Could not start the core: ${snap.error}'),
            ),
          );
        }
        final h = snap.data;
        if (h == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return AuthGate(
          gateway: h.gateway,
          child: FeedsScreen(
            db: h.db,
            gateway: h.gateway,
            // P1-9/P1-10 open the editor and the timeline from here.
            onOpenFeed: (_) {},
            actions: [LogOutAction(onLogOut: h.logOutAndWipe)],
          ),
        );
      },
    );
  }
}
