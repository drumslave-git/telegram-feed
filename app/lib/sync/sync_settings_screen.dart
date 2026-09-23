import 'package:flutter/material.dart';

import 'sync_controller.dart';

/// Google Drive sync: what it does, on/off, state of the last run.
class SyncSettingsScreen extends StatelessWidget {
  const SyncSettingsScreen({super.key, required this.controller});
  final SyncController controller;

  /// When the last sync ran, with the day unless it was today: "at 14:32",
  /// "yesterday at 14:32", "Sep 20 at 14:32".
  static String syncedAt(DateTime t, BuildContext context, {DateTime? now}) {
    final today = DateUtils.dateOnly(now ?? DateTime.now());
    final day = DateUtils.dateOnly(t);
    final time = TimeOfDay.fromDateTime(t).format(context);
    if (day == today) return 'at $time';
    if (day == today.subtract(const Duration(days: 1))) {
      return 'yesterday at $time';
    }
    return '${MaterialLocalizations.of(context).formatShortMonthDay(t)} at $time';
  }

  static String describe(SyncStatus s, BuildContext context) {
    if (!s.available) return 'Not available in this build';
    if (!s.isOn) return 'Off';
    final last = s.lastSyncedAt;
    if (s.error != null) return 'Problem: ${s.error}';
    if (last == null) return 'On, ${s.account}';
    return 'On, ${s.account} · last synced ${syncedAt(last, context)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Google Drive sync')),
      body: ValueListenableBuilder<SyncStatus>(
        valueListenable: controller.status,
        builder: (context, s, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Keeps your feeds with their channels, your rules and your settings the same on '
              'all your devices through a hidden app file in your own Google Drive. There is no '
              'server of ours. Read positions, the AI API key and your Telegram session stay '
              'on each device.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            if (!s.available)
              Text(
                'This build was made without a Google client id, so sync cannot be turned on.',
                style: TextStyle(color: theme.colorScheme.error),
              )
            else if (!s.isOn)
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: controller.turnOn,
                  icon: const Icon(Icons.cloud_sync_outlined),
                  label: const Text('Sign in with Google and sync'),
                ),
              )
            else ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.account_circle_outlined),
                title: Text(s.account!),
                subtitle: Text(
                  s.syncing
                      ? 'Syncing…'
                      : s.lastSyncedAt == null
                      ? 'Not synced yet'
                      : 'Last synced ${syncedAt(s.lastSyncedAt!, context)}',
                ),
              ),
              Wrap(
                spacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: s.syncing ? null : controller.syncNow,
                    icon: const Icon(Icons.sync),
                    label: const Text('Sync now'),
                  ),
                  TextButton(
                    onPressed: s.syncing ? null : controller.turnOff,
                    child: const Text('Turn off on this device'),
                  ),
                ],
              ),
            ],
            if (s.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  s.error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
