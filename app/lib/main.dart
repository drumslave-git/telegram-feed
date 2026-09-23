import 'package:app_db/app_db.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'auth/login_screens.dart';
import 'home/home_screen.dart';
import 'host/accounts.dart';
import 'host/app_host.dart';
import 'feeds/text_scale.dart';
import 'media/audio_bar.dart';
import 'media/auto_download.dart';
import 'media/system_pip.dart';
import 'notifications/open_post.dart';
import 'rules/rules_screen.dart';
import 'settings/app_lock.dart';
import 'settings/settings_screen.dart';
import 'app_name.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  platformInit();
  runApp(const TelegramFeedApp());
}

class TelegramFeedApp extends StatefulWidget {
  const TelegramFeedApp({super.key, this.host});

  /// Injected in tests; the real app starts its own.
  final Future<AppHost>? host;

  @override
  State<TelegramFeedApp> createState() => _TelegramFeedAppState();
}

class _TelegramFeedAppState extends State<TelegramFeedApp> {
  late Future<AppHost> _host = _start(widget.host);

  Future<AppHost> _start(Future<AppHost>? given) =>
      (given ?? startAppHost()).then(
        (h) async {
          if (given == null) await attachLaunchHandlers(h);
          return h;
        },
        onError: (Object e, StackTrace st) {
          debugPrint('host start failed: $e');
          Error.throwWithStackTrace(e, st);
        },
      );

  /// Another account: the host that holds this one's core and database goes down, and a new
  /// one comes up on the other account's paths (H-35). Everything above rebuilds, so an
  /// account with no session of its own lands on the login screen.
  Future<void> _switchAccount() async {
    final old = await _host;
    await old.dispose();
    if (!mounted) return;
    setState(() => _host = _start(null));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppHost>(
      future: _host,
      builder: (context, snap) => StreamBuilder<String?>(
        stream: snap.data?.db.watchSetting(SettingKeys.themeMode),
        builder: (context, mode) => MaterialApp(
          navigatorKey: navigatorKey,
          title: appName,
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
          // Above the navigator, so every route's media sees the download settings, and
          // every route reaches the account switch (the Accounts screen is pushed over
          // the home route, not built inside it).
          builder: (context, child) => AccountSwitch(
            onSwitched: _switchAccount,
            child: PipHost(
              child: snap.data == null
                  ? child!
                  : AutoDownloadScope(
                      db: snap.data!.db,
                      child: PostTextScale(
                        db: snap.data!.db,
                        // Under every screen while a voice message or a song plays.
                        // The lock sits above every screen the navigator builds.
                        child: AudioBarHost(
                          child: LockGate(db: snap.data!.db, child: child!),
                        ),
                      ),
                    ),
            ),
          ),
          home: _Root(host: _host),
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
            onOpenRules: () => _openRules(context, h),
            actions: [
              IconButton(
                tooltip: 'Rules',
                // A bell, not a list: these rules exist to notify.
                icon: const Icon(Icons.notifications_active_outlined),
                onPressed: () => _openRules(context, h),
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
                      onRestart: h.restart,
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

  /// The rules overview, from the app bar and from the first-run card on the Feeds tab.
  void _openRules(BuildContext context, AppHost h) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RulesScreen(
            db: h.db,
            gateway: h.gateway,
            batteryExempt: () => h.isBatteryExempt,
            onRequestBatteryExemption: h.requestBatteryExemption,
          ),
        ),
      );
}
