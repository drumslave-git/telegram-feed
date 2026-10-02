import 'package:app_db/app_db.dart';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'app_lock.dart';
import 'settings_tiles.dart';

/// Who can read the app on this phone: the app lock, where the official app keeps its
/// passcode.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key, required this.db});
  final AppDatabase db;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.privacyTitle)),
      body: ListView(
        children: [
          SettingsHeader(l10n.privacySecurity),
          StreamBuilder<String?>(
            stream: db.watchSetting(SettingKeys.lockEnabled),
            builder: (context, snap) => SettingsLink(
              icon: Icons.lock_outline,
              title: l10n.appLockTitle,
              value: snap.data == 'true' ? l10n.commonOn : l10n.commonOff,
              onTap: () => openSettingsScreen(context, AppLockScreen(db: db)),
            ),
          ),
          SettingsFooter(l10n.privacyAppLockFooter),
        ],
      ),
    );
  }
}
