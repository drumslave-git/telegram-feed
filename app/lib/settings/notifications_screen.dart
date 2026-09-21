import 'dart:async';

import 'package:app_db/app_db.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'settings_tiles.dart';

/// How rules notify and whether they run with the app closed: the official app's
/// Notifications and Sounds.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key, required this.db});
  final AppDatabase db;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Notifications and sounds')),
    body: ListView(
      children: [
        const SettingsHeader('Rule notifications'),
        NotificationSoundSettings(db: db),
        const Divider(),
        const SettingsHeader('Badge counter'),
        StreamBuilder<String?>(
          stream: db.watchSetting(SettingKeys.countUnreadPosts),
          builder: (context, snap) => SwitchListTile(
            title: const Text('Count unread posts'),
            value: snap.data != 'false',
            onChanged: (v) => db.setSetting(SettingKeys.countUnreadPosts, '$v'),
          ),
        ),
        const SettingsFooter(
          'The badges of the feeds and of the folder tabs count the unread posts. Off, '
          'they count the channels that have unread posts.',
        ),
        const Divider(),
        const SettingsHeader('Background'),
        StreamBuilder<String?>(
          stream: db.watchSetting(SettingKeys.backgroundWatching),
          builder: (context, snap) => SwitchListTile(
            title: const Text('Watch channels in the background'),
            subtitle: const Text(
              'Rules keep running while the app is closed. Off removes the '
              'permanent notification, and rules then only notify while the app is '
              'open. Takes effect the next time the app starts.',
            ),
            value: snap.data != 'false',
            onChanged: (v) => db.setSetting(
              SettingKeys.backgroundWatching,
              v ? 'true' : 'false',
            ),
          ),
        ),
        const Divider(),
        const SystemNotificationSettingsRow(),
      ],
    ),
  );
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

  Future<void> _open() async {
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
    title: const Text('System notification settings'),
    onTap: () => unawaited(_open()),
  );
}

/// The sound and the vibration of the notifications of normal and urgent rules (H-33).
/// Silent rules stay silent, and Android fixes a channel's sound when it is created, so a
/// change here takes effect when the watcher is next brought up — the same rule as the
/// background switch.
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
    try {
      final picked = await channel.invokeMethod<String>('pickSound', {
        'current': await db.setting(key) ?? '',
      });
      if (picked != null) await db.setSetting(key, picked);
    } on PlatformException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('No sound picker: ${e.message}')),
      );
    } on MissingPluginException {
      messenger.showSnackBar(
        const SnackBar(content: Text('No sound picker on this device.')),
      );
    }
  }

  Widget _rows({
    required String title,
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
            title: Text('$title: sound'),
            subtitle: Text(
              sound.isEmpty ? 'The system default' : _soundName(sound),
            ),
            trailing: sound.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Use the default',
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
          title: Text('$title: vibrate'),
          onChanged: (v) => db.setSetting(vibrateKey, '$v'),
        ),
      ),
    ],
  );

  /// The last part of the uri, which is as much of a name as Android gives us here.
  static String _soundName(String uri) {
    final parts = uri.split('/');
    return parts.isEmpty ? uri : 'Sound ${parts.last}';
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _rows(
        title: 'Normal rules',
        soundKey: SettingKeys.normalSound,
        vibrateKey: SettingKeys.normalVibrate,
      ),
      _rows(
        title: 'Urgent rules',
        soundKey: SettingKeys.urgentSound,
        vibrateKey: SettingKeys.urgentVibrate,
      ),
      const SettingsFooter(
        'Silent rules stay silent. Android fixes a sound when it creates the channel, so a '
        'change here takes effect the next time the app starts.',
      ),
    ],
  );
}
