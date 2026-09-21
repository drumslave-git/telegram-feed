import 'package:app_db/app_db.dart';
import 'package:flutter/material.dart';

import 'app_lock.dart';
import 'settings_tiles.dart';

/// Who can read the app on this phone, and what Telegram learns of the reading: the app
/// lock and read sync, where the official app keeps its passcode and its read times.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key, required this.db});
  final AppDatabase db;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Privacy and security')),
    body: ListView(
      children: [
        const SettingsHeader('Security'),
        StreamBuilder<String?>(
          stream: db.watchSetting(SettingKeys.lockEnabled),
          builder: (context, snap) => SettingsLink(
            icon: Icons.lock_outline,
            title: 'App lock',
            value: snap.data == 'true' ? 'On' : 'Off',
            onTap: () => openSettingsScreen(context, AppLockScreen(db: db)),
          ),
        ),
        const SettingsFooter(
          'A PIN, or the phone\'s own fingerprint or face, is asked for when the app has '
          'rested. Without it anyone holding the unlocked phone can read your channels.',
        ),
        const Divider(),
        const SettingsHeader('Reading'),
        StreamBuilder<String?>(
          stream: db.watchSetting(SettingKeys.syncReadToTelegram),
          builder: (context, snap) => SwitchListTile(
            title: const Text('Mark posts read in Telegram'),
            value: snap.data != 'false',
            onChanged: (v) => db.setSetting(
              SettingKeys.syncReadToTelegram,
              v ? 'true' : 'false',
            ),
          ),
        ),
        const SettingsFooter(
          'What you scroll past here counts as read in the official app too. Off, Telegram '
          'does not learn what you read here, and the official app keeps its own unread '
          'counters.',
        ),
      ],
    ),
  );
}
