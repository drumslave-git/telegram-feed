import 'dart:async';

import 'package:app_db/app_db.dart';
import 'package:flutter/material.dart';

import 'auth/login_screens.dart';
import 'home/home_screen.dart';
import 'host/account_record.dart';
import 'host/accounts.dart';
import 'host/app_host.dart';
import 'feeds/text_scale.dart';
import 'l10n/l10n.dart';
import 'media/audio_session.dart';
import 'media/auto_download.dart';
import 'media/system_pip.dart';
import 'notifications/open_post.dart';
import 'service/push_run.dart';
import 'rules/rules_screen.dart';
import 'settings/app_lock.dart';
import 'settings/settings_screen.dart';
import 'widgets/status_banner.dart';
import 'widgets/swipe_back.dart';
import 'app_name.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TelegramFeedApp());
}

/// The entry point of a run: Android starts it in an engine of its own for a push while
/// the app is closed (`PushWorker`, ARCHITECTURE 6.5).
@pragma('vm:entry-point')
Future<void> pushMain() => runPush();

class TelegramFeedApp extends StatefulWidget {
  const TelegramFeedApp({super.key, this.host});

  /// Injected in tests; the real app starts its own.
  final Future<AppHost>? host;

  @override
  State<TelegramFeedApp> createState() => _TelegramFeedAppState();
}

class _TelegramFeedAppState extends State<TelegramFeedApp> {
  late Future<AppHost> _host = _start(widget.host);

  @override
  void initState() {
    super.initState();
    AccountSwitch.root = _switchAccount;
  }

  @override
  void dispose() {
    if (AccountSwitch.root == _switchAccount) AccountSwitch.root = null;
    super.dispose();
  }

  Future<AppHost> _start(Future<AppHost>? given) =>
      (given ?? startAppHost()).then(
        (h) async {
          if (given == null) {
            await attachLaunchHandlers(h);
            await const AppLock().adoptLegacy(h.db);
          }
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
    // What plays was posted in the account that goes, and its bar leads to that post.
    await AudioSessions.instance.stop();
    // With its core: the core is the account's TDLib and database, and the next host
    // would attach to it if it were still there.
    await old.standDown();
    if (!mounted) return;
    // A block, not an arrow: an arrow would hand setState the future it assigns, which
    // Flutter refuses in debug builds, and the switch would never happen.
    setState(() {
      _host = _start(null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppHost>(
      future: _host,
      builder: (context, snap) => StreamBuilder<String?>(
        stream: snap.data?.db.watchSetting(SettingKeys.themeMode),
        builder: (context, mode) => StreamBuilder<String?>(
          stream: snap.data?.db.watchSetting(SettingKeys.language),
          builder: (context, language) => MaterialApp(
            navigatorKey: navigatorKey,
            title: appName,
            // The Language setting, or the phone's language while it says System (and
            // before the database is open).
            locale: AppLanguage.localeOf(language.data),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
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
            // every route reaches the account switch (Settings is pushed over
            // the home route, not built inside it).
            builder: (context, child) => AccountSwitch(
              onSwitched: _switchAccount,
              child: PipHost(
                // The lock sits above every screen the navigator builds, and stays up
                // through a change of account.
                child: LockGate(
                  child: snap.data == null
                      ? child!
                      : AutoDownloadScope(
                          db: snap.data!.db,
                          child: PostTextScale(
                            db: snap.data!.db,
                            // Under the header of every screen while a post is read
                            // aloud or notifications are paused.
                            child: StatusBannerHost(
                              reading: snap.data!.reading,
                              paused: snap.data!.paused,
                              onStop: ({required clear}) =>
                                  snap.data!.stopReading(clear: clear),
                              onResume: () =>
                                  unawaited(snap.data!.setPaused(false)),
                              // Under every screen while a voice message or a song plays.
                              child: child!,
                            ),
                          ),
                        ),
                ),
              ),
            ),
            home: _Root(host: _host),
          ),
        ),
      ),
    );
  }
}

/// Screens slide in and go back with a swipe to the right from anywhere on them, as
/// everywhere in the official app ([SwipeBackTransitionsBuilder]); the viewer has a route
/// of its own and keeps its swipe down to close.
final appPageTransitions = PageTransitionsTheme(
  builders: {
    for (final platform in TargetPlatform.values)
      platform: const SwipeBackTransitionsBuilder(),
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
              child: Text(context.l10n.appStartFailed('${snap.error}')),
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
          // Built once the account is logged in: the list of accounts learns its profile
          // and follows its unread count.
          child: AccountRecord(
            gateway: h.gateway,
            builder: (context, onUnread) => HomeScreen(
              db: h.db,
              gateway: h.gateway,
              onUnreadChannels: onUnread,
              onOpenRules: () => _openRules(context, h),
              actions: [
                const LockButton(),
                PauseButton(paused: h.paused, onChanged: h.setPaused),
                IconButton(
                  tooltip: context.l10n.commonRules,
                  // A bell, not a list: these rules exist to notify.
                  icon: const Icon(Icons.notifications_active_outlined),
                  onPressed: () => _openRules(context, h),
                ),
                IconButton(
                  tooltip: context.l10n.commonSettings,
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SettingsScreen(
                        db: h.db,
                        gateway: h.gateway,
                        onLogOut: h.logOutAndWipe,
                        sync: h.sync,
                        batteryExempt: () => h.isBatteryExempt,
                        onRequestBatteryExemption: h.requestBatteryExemption,
                        pushAvailable: () => h.pushAvailable,
                      ),
                    ),
                  ),
                ),
              ],
            ),
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
