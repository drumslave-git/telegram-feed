import 'package:app_db/app_db.dart';
import 'package:flutter/material.dart';

import 'auth/login_screens.dart';
import 'core_host.dart';
import 'feeds/feeds_screen.dart';
import 'feeds/timeline_screen.dart';
import 'notifications/notification_launch.dart';
import 'service/core_service.dart';
import 'settings/settings_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  initCoreService();
  runApp(const TelegramFeedApp());
}

class TelegramFeedApp extends StatelessWidget {
  const TelegramFeedApp({super.key, this.host});

  /// Injected in tests; the real app starts its own.
  final Future<CoreHost>? host;

  @override
  Widget build(BuildContext context) {
    final h = (host ?? CoreHost.start()).then((h) async {
      if (host == null) await NotificationLaunch(h).attach();
      return h;
    });
    return FutureBuilder<CoreHost>(
      future: h,
      builder: (context, snap) => StreamBuilder<String?>(
        stream: snap.data?.db.watchSetting(SettingKeys.themeMode),
        builder: (context, mode) => MaterialApp(
          navigatorKey: navigatorKey,
          title: 'telegram-feed',
          theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
          darkTheme: ThemeData(
            colorSchemeSeed: Colors.blue,
            brightness: Brightness.dark,
            useMaterial3: true,
          ),
          themeMode: themeModeFrom(mode.data),
          home: _Root(host: h),
        ),
      ),
    );
  }
}

ThemeMode themeModeFrom(String? value) => switch (value) {
  'light' => ThemeMode.light,
  'dark' => ThemeMode.dark,
  _ => ThemeMode.system,
};

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
            onOpenFeed: (feed) => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    TimelineScreen(db: h.db, gateway: h.gateway, feed: feed),
              ),
            ),
            actions: [
              IconButton(
                tooltip: 'Settings',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SettingsScreen(
                      db: h.db,
                      gateway: h.gateway,
                      onLogOut: h.logOutAndWipe,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
