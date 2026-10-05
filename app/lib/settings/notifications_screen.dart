import 'dart:async';

import 'package:app_db/app_db.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../rules/rules_screen.dart' show BatteryBanner;
import 'settings_tiles.dart';

/// How rules notify, and whether they can while the app is closed: the official app's
/// Notifications and Sounds.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    required this.db,
    this.pushAvailable,
    this.batteryExempt,
    this.onRequestBatteryExemption,
    this.channel = const MethodChannel('tf/notifications'),
  });
  final AppDatabase db;

  /// Whether Telegram's push reaches this install (`AppHost.pushAvailable`). Null where
  /// there is no host to ask (tests): the screen then says nothing of it.
  final Future<bool> Function()? pushAvailable;

  /// Whether Android lets the app ignore battery optimisation, and the ask for it; the
  /// banner about it belongs here as well as on the rules screens. Null where the
  /// platform has none (tests, desktop).
  final Future<bool> Function()? batteryExempt;
  final Future<void> Function()? onRequestBatteryExemption;

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

  late final Future<bool>? _push = widget.pushAvailable?.call();

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
          // The same warning the rules screens carry: battery optimisation holds back
          // what a push starts.
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
            stream: db.watchSetting(SettingKeys.badgeEnabled),
            builder: (context, snap) => SwitchListTile(
              title: Text(l10n.notificationSettingsBadgeShow),
              value: snap.data != 'false',
              onChanged: (v) => db.setSetting(SettingKeys.badgeEnabled, '$v'),
            ),
          ),
          StreamBuilder<String?>(
            stream: db.watchSetting(SettingKeys.badgeMuted),
            builder: (context, snap) => SwitchListTile(
              title: Text(l10n.notificationSettingsBadgeMuted),
              value: snap.data == 'true',
              onChanged: (v) => db.setSetting(SettingKeys.badgeMuted, '$v'),
            ),
          ),
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
          if (_push case final push?)
            FutureBuilder<bool>(
              future: push,
              builder: (context, snap) => switch (snap.data) {
                null => const SizedBox.shrink(),
                final on => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Divider(),
                    SettingsHeader(l10n.notificationSettingsBackground),
                    ListTile(
                      title: Text(l10n.notificationSettingsPush),
                      subtitle: Text(
                        on
                            ? l10n.notificationSettingsPushOn
                            : l10n.notificationSettingsPushOff,
                      ),
                    ),
                  ],
                ),
              },
            ),
          const Divider(),
          SystemNotificationSettingsRow(channel: widget.channel),
        ],
      ),
    );
  }
}

/// Opens Android's settings page of the app's notifications, where each kind of them is
/// turned off or changed.
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
