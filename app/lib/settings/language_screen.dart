import 'dart:async';

import 'package:app_db/app_db.dart';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'settings_tiles.dart';

/// The interface language, as the official app's Language screen: each language under its
/// own name, and System, which follows the phone.
class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key, required this.db});
  final AppDatabase db;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final phone = AppLanguage.ofPhone(
      WidgetsBinding.instance.platformDispatcher.locales,
    );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.languageTitle)),
      body: StreamBuilder<String?>(
        stream: db.watchSetting(SettingKeys.language),
        builder: (context, snap) => ListView(
          children: [
            RadioGroup<String>(
              groupValue: AppLanguage.localeOf(snap.data) == null
                  ? AppLanguage.system
                  : snap.data!,
              onChanged: (v) => unawaited(
                db.setSetting(SettingKeys.language, v ?? AppLanguage.system),
              ),
              child: Column(
                children: [
                  RadioListTile<String>(
                    value: AppLanguage.system,
                    title: Text(l10n.languageSystem),
                    subtitle: Text(AppLanguage.nameOf(phone.languageCode)),
                  ),
                  for (final code in AppLanguage.all)
                    RadioListTile<String>(
                      value: code,
                      title: Text(AppLanguage.nameOf(code)),
                    ),
                ],
              ),
            ),
            SettingsFooter(l10n.languageFooter),
          ],
        ),
      ),
    );
  }
}
