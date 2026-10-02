import 'dart:async';

import 'package:app_db/app_db.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../rules/rules_screen.dart' show BatteryBanner;
import 'settings_tiles.dart';

/// How rules notify and whether they run with the app closed: the official app's
/// Notifications and Sounds.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    required this.db,
    this.onRestart,
    this.batteryExempt,
    this.onRequestBatteryExemption,
    this.runningInService,
    this.channel = const MethodChannel('tf/notifications'),
  });
  final AppDatabase db;

  /// Starts the app afresh; background watching changes where the core runs, which only
  /// a new start can do. Null where the host cannot (tests).
  final Future<void> Function()? onRestart;

  /// Whether Android lets the app ignore battery optimisation, and the ask for it; the
  /// banner about it belongs here as well as on the rules screens. Null where the
  /// platform has none (tests, desktop).
  final Future<bool> Function()? batteryExempt;
  final Future<void> Function()? onRequestBatteryExemption;

  /// True while the core still runs in the mode the setting had before it was changed:
  /// the switch shows the new value, so the screen says a restart is due.
  final bool Function()? runningInService;

  /// Asks Android whether the app may notify at all; tests hand in their own.
  final MethodChannel channel;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  /// False when the user turned the app's notifications off in Android: no rule notifies.
  bool _enabled = true;
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    // Back from Android's settings, where the user may just have turned them on.
    onResume: () => unawaited(_check()),
  );

  AppDatabase get db => widget.db;

  @override
  void initState() {
    super.initState();
    _lifecycle;
    unawaited(_check());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    bool? enabled;
    try {
      enabled = await widget.channel.invokeMethod<bool>(
        'areNotificationsEnabled',
      );
    } on MissingPluginException {
      enabled = null;
    } on PlatformException {
      enabled = null;
    }
    if (mounted && enabled != null) setState(() => _enabled = enabled!);
  }

  /// Background watching moves the core between the service and the app, which a fresh
  /// start does; the user decides when.
  Future<void> _setBackground(bool on) async {
    await db.setSetting(SettingKeys.backgroundWatching, on ? 'true' : 'false');
    final restart = widget.onRestart;
    if (restart == null || !mounted) return;
    final now = await showDialog<bool>(
      context: context,
      builder: (context) {
        final l10n = context.l10n;
        return AlertDialog(
          title: Text(l10n.notificationSettingsRestartTitle),
          content: Text(
            on
                ? l10n.notificationSettingsRestartStartsWatching
                : l10n.notificationSettingsRestartStopsWatching,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.commonLater),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.notificationSettingsRestartNow),
            ),
          ],
        );
      },
    );
    if (now ?? false) {
      await restart();
    } else if (mounted) {
      // "Later": the setting is saved but the core still runs where it did, and the
      // screen says so instead of leaving the switch to lie about it.
      setState(() => _restartDue = true);
    }
  }

  /// Whether the running mode and the saved setting have drifted apart.
  bool _restartDue = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.notificationSettingsTitle)),
      body: ListView(
        children: [
          if (!_enabled)
            MaterialBanner(
              leading: Icon(
                Icons.notifications_off_outlined,
                color: Theme.of(context).colorScheme.error,
              ),
              content: Text(l10n.notificationSettingsBlocked),
              actions: [
                TextButton(
                  onPressed: () => unawaited(
                    SystemNotificationSettingsRow.openSettings(widget.channel),
                  ),
                  child: Text(l10n.notificationSettingsTurnOn),
                ),
              ],
            ),
          // The same warning the rules screens carry: battery optimisation stops the
          // watching this screen turns on.
          if (widget.batteryExempt != null)
            BatteryBanner(
              exempt: widget.batteryExempt!,
              onRequest: widget.onRequestBatteryExemption,
            ),
          SettingsHeader(l10n.notificationSettingsRuleNotifications),
          NotificationSoundSettings(db: db, channel: widget.channel),
          const Divider(),
          SettingsHeader(l10n.notificationSettingsBadgeCounter),
          StreamBuilder<String?>(
            stream: db.watchSetting(SettingKeys.countUnreadPosts),
            builder: (context, snap) => SwitchListTile(
              title: Text(l10n.notificationSettingsCountUnreadPosts),
              value: snap.data != 'false',
              onChanged: (v) =>
                  db.setSetting(SettingKeys.countUnreadPosts, '$v'),
            ),
          ),
          SettingsFooter(l10n.notificationSettingsCountFooter),
          const Divider(),
          SettingsHeader(l10n.notificationSettingsBackground),
          StreamBuilder<String?>(
            stream: db.watchSetting(SettingKeys.backgroundWatching),
            builder: (context, snap) {
              final on = snap.data != 'false';
              // Either the reader answered "Later", or the core simply runs in the
              // other mode: the switch would otherwise say one thing while the app
              // does another.
              final due =
                  _restartDue ||
                  (widget.runningInService != null &&
                      widget.runningInService!() != on);
              return Column(
                children: [
                  SwitchListTile(
                    title: Text(l10n.notificationSettingsWatchInBackground),
                    subtitle: Text(
                      l10n.notificationSettingsWatchInBackgroundSubtitle,
                    ),
                    value: on,
                    onChanged: (v) => unawaited(_setBackground(v)),
                  ),
                  if (due)
                    MaterialBanner(
                      leading: const Icon(Icons.restart_alt),
                      content: Text(
                        on
                            ? l10n.notificationSettingsRestartStartsWatching
                            : l10n.notificationSettingsRestartDueStopsWatching,
                      ),
                      actions: [
                        TextButton(
                          onPressed: widget.onRestart == null
                              ? null
                              : () => unawaited(widget.onRestart!()),
                          child: Text(l10n.notificationSettingsRestartNow),
                        ),
                      ],
                    ),
                ],
              );
            },
          ),
          const Divider(),
          SystemNotificationSettingsRow(channel: widget.channel),
        ],
      ),
    );
  }
}

/// Opens Android's settings page of the app's notifications, where each kind of them, the
/// permanent "Watching N channels" one included, is turned off or changed.
class SystemNotificationSettingsRow extends StatelessWidget {
  const SystemNotificationSettingsRow({
    super.key,
    this.channel = const MethodChannel('tf/notifications'),
  });

  /// The platform channel; tests hand in their own.
  final MethodChannel channel;

  static Future<void> openSettings(MethodChannel channel) async {
    try {
      await channel.invokeMethod<void>('openAppSettings');
    } on MissingPluginException {
      // No platform side (tests, desktop): nothing to open.
    } on PlatformException {
      // Android refused the page; the row stays as it is.
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.settings_outlined),
    title: Text(context.l10n.notificationSettingsSystemSettings),
    onTap: () => unawaited(openSettings(channel)),
  );
}

/// The sound and the vibration of the notifications of normal and urgent rules. Silent
/// rules stay silent. A change reaches the watcher at once, which makes its notification
/// channels again (Android fixes a channel's sound when it is created).
class NotificationSoundSettings extends StatelessWidget {
  const NotificationSoundSettings({
    super.key,
    required this.db,
    this.channel = const MethodChannel('tf/notifications'),
  });
  final AppDatabase db;

  /// The channel that opens Android's own sound picker; tests hand in their own.
  final MethodChannel channel;

  Future<void> _pick(BuildContext context, String key) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      final picked = await channel.invokeMethod<String>('pickSound', {
        'current': await db.setting(key) ?? '',
      });
      if (picked != null) await db.setSetting(key, picked);
    } on PlatformException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.notificationSettingsNoSoundPicker('${e.message}')),
        ),
      );
    } on MissingPluginException {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.notificationSettingsNoSoundPickerOnDevice)),
      );
    }
  }

  Widget _rows(
    AppLocalizations l10n, {
    required String soundTitle,
    required String vibrateTitle,
    required String soundKey,
    required String vibrateKey,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      StreamBuilder<String?>(
        stream: db.watchSetting(soundKey),
        builder: (context, snap) {
          final sound = snap.data ?? '';
          return ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: Text(soundTitle),
            subtitle: sound.isEmpty
                ? Text(l10n.notificationSettingsSystemDefaultSound)
                : FutureBuilder<String?>(
                    future: _soundTitle(sound),
                    builder: (context, title) => Text(
                      title.data ?? l10n.notificationSettingsChosenSound,
                    ),
                  ),
            trailing: sound.isEmpty
                ? null
                : IconButton(
                    tooltip: l10n.notificationSettingsUseDefaultSound,
                    icon: const Icon(Icons.restart_alt),
                    onPressed: () => db.setSetting(soundKey, ''),
                  ),
            onTap: () => unawaited(_pick(context, soundKey)),
          );
        },
      ),
      StreamBuilder<String?>(
        stream: db.watchSetting(vibrateKey),
        builder: (context, snap) => SwitchListTile(
          value: snap.data != 'false',
          title: Text(vibrateTitle),
          onChanged: (v) => db.setSetting(vibrateKey, '$v'),
        ),
      ),
    ],
  );

  /// Android's own name of the sound, as its picker lists it; null when it has none.
  Future<String?> _soundTitle(String uri) async {
    try {
      return await channel.invokeMethod<String>('soundTitle', {'uri': uri});
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _rows(
          l10n,
          soundTitle: l10n.notificationSettingsNormalSound,
          vibrateTitle: l10n.notificationSettingsNormalVibrate,
          soundKey: SettingKeys.normalSound,
          vibrateKey: SettingKeys.normalVibrate,
        ),
        _rows(
          l10n,
          soundTitle: l10n.notificationSettingsUrgentSound,
          vibrateTitle: l10n.notificationSettingsUrgentVibrate,
          soundKey: SettingKeys.urgentSound,
          vibrateKey: SettingKeys.urgentVibrate,
        ),
        SettingsFooter(l10n.notificationSettingsSilentRulesFooter),
      ],
    );
  }
}
