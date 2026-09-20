import 'package:app_db/app_db.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'auth/login_screens.dart';
import 'home/home_screen.dart';
import 'host/app_host.dart';
import 'feeds/text_scale.dart';
import 'media/audio_bar.dart';
import 'media/auto_download.dart';
import 'media/autoplay.dart';
import 'media/system_pip.dart';
import 'notifications/open_post.dart';
import 'rules/rules_screen.dart';
import 'settings/settings_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  platformInit();
  runApp(const TelegramFeedApp());
}

class TelegramFeedApp extends StatelessWidget {
  const TelegramFeedApp({super.key, this.host});

  /// Injected in tests; the real app starts its own.
  final Future<AppHost>? host;

  @override
  Widget build(BuildContext context) {
    final h = (host ?? startAppHost()).then(
      (h) async {
        if (host == null) await attachLaunchHandlers(h);
        return h;
      },
      onError: (Object e, StackTrace st) {
        debugPrint('host start failed: $e\n$st');
        Error.throwWithStackTrace(e, st);
      },
    );
    return FutureBuilder<AppHost>(
      future: h,
      builder: (context, snap) => StreamBuilder<String?>(
        stream: snap.data?.db.watchSetting(SettingKeys.themeMode),
        builder: (context, mode) => MaterialApp(
          navigatorKey: navigatorKey,
          title: 'telegram-feed',
          theme: ThemeData(
            colorSchemeSeed: Colors.blue,
            useMaterial3: true,
            pageTransitionsTheme: appPageTransitions,
          ),
          darkTheme: ThemeData(
            colorSchemeSeed: Colors.blue,
            brightness: Brightness.dark,
            useMaterial3: true,
            pageTransitionsTheme: appPageTransitions,
          ),
          themeMode: themeModeFrom(mode.data),
          // Above the navigator, so every route's media sees the autoplay settings.
          builder: (context, child) => PipHost(
            child: snap.data == null
                ? child!
                : AutoplayScope(
                    db: snap.data!.db,
                    child: AutoDownloadScope(
                      db: snap.data!.db,
                      child: PostTextScale(
                        db: snap.data!.db,
                        // Under every screen while a voice message or a song plays.
                        child: AudioBarHost(child: child!),
                      ),
                    ),
                  ),
          ),
          home: _Root(host: h),
        ),
      ),
    );
  }
}

/// Screens slide in and can be dragged back from the left edge, as everywhere in the
/// official app. Flutter's Cupertino transition carries that gesture; the viewer has a
/// route of its own and keeps its swipe down to close.
final appPageTransitions = PageTransitionsTheme(
  builders: {
    for (final platform in TargetPlatform.values)
      platform: const CupertinoPageTransitionsBuilder(),
  },
);

ThemeMode themeModeFrom(String? value) => switch (value) {
  'light' => ThemeMode.light,
  'dark' => ThemeMode.dark,
  _ => ThemeMode.system,
};

class _Root extends StatelessWidget {
  const _Root({required this.host});
  final Future<AppHost> host;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppHost>(
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
          child: HomeScreen(
            db: h.db,
            gateway: h.gateway,
            actions: [
              IconButton(
                tooltip: 'Rules',
                icon: const Icon(Icons.rule),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RulesScreen(
                      db: h.db,
                      gateway: h.gateway,
                      batteryExempt: () => h.isBatteryExempt,
                      onRequestBatteryExemption: h.requestBatteryExemption,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Settings',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SettingsScreen(
                      db: h.db,
                      gateway: h.gateway,
                      onLogOut: h.logOutAndWipe,
                      sync: h.sync,
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
