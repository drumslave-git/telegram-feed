import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'drive_sync_store.dart';
import 'sync_controller.dart';

/// Google Drive sync: what it does, on/off, state of the last run.
class SyncSettingsScreen extends StatelessWidget {
  const SyncSettingsScreen({super.key, required this.controller});
  final SyncController controller;

  /// When the last sync ran, with the day unless it was today: "at 14:32",
  /// "yesterday at 14:32", "Sep 20 at 14:32".
  static String syncedAt(DateTime t, BuildContext context, {DateTime? now}) {
    final l10n = context.l10n;
    final today = DateUtils.dateOnly(now ?? DateTime.now());
    final day = DateUtils.dateOnly(t);
    final time = TimeOfDay.fromDateTime(t).format(context);
    if (day == today) return l10n.syncAtTime(time);
    if (day == today.subtract(const Duration(days: 1))) {
      return l10n.syncYesterdayAt(time);
    }
    return l10n.syncDateAtTime(
      MaterialLocalizations.of(context).formatShortMonthDay(t),
      time,
    );
  }

  /// [failure] in the words of [l10n].
  static String failureText(SyncFailure failure, AppLocalizations l10n) =>
      switch (failure) {
        SyncSignedOut() => l10n.syncSignedOutError,
        SyncFailed(:final error) => l10n.sync(error),
        SyncDriveFailed(:final error) => switch (error.failure) {
          DriveFailure.noClientId => l10n.syncNoClientIdError,
          DriveFailure.cancelled => l10n.syncSignInCancelled,
          DriveFailure.signInFailed => l10n.syncSignInFailed(error.detail),
          DriveFailure.notSignedIn => l10n.syncNotSignedIn,
          DriveFailure.unreachable => l10n.syncDriveUnreachable(error.detail),
          DriveFailure.refused => l10n.syncDriveRefused(
            (error.request ?? DriveRequest.update).name,
            '${error.status}',
            error.detail.isEmpty ? '' : ': ${error.detail}',
          ),
        },
      };

  static String describe(SyncStatus s, BuildContext context) {
    final l10n = context.l10n;
    if (!s.available) return l10n.syncUnavailable;
    if (!s.isOn) return l10n.commonOff;
    final last = s.lastSyncedAt;
    if (s.failure case final f?) return l10n.syncProblem(failureText(f, l10n));
    if (last == null) return l10n.syncOnAccount(s.account!);
    return l10n.syncOnAccountLastSynced(s.account!, syncedAt(last, context));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.syncTitle)),
      body: ValueListenableBuilder<SyncStatus>(
        valueListenable: controller.status,
        builder: (context, s, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(l10n.syncIntro, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            if (!s.available)
              Text(
                l10n.syncNoClientIdBuild,
                style: TextStyle(color: theme.colorScheme.error),
              )
            else if (!s.isOn)
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: controller.turnOn,
                  icon: const Icon(Icons.cloud_sync_outlined),
                  label: Text(l10n.syncSignIn),
                ),
              )
            else ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.account_circle_outlined),
                title: Text(s.account!),
                subtitle: Text(
                  s.syncing
                      ? l10n.syncSyncing
                      : s.lastSyncedAt == null
                      ? l10n.syncNotSyncedYet
                      : l10n.syncLastSynced(syncedAt(s.lastSyncedAt!, context)),
                ),
              ),
              Wrap(
                spacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: s.syncing ? null : controller.syncNow,
                    icon: const Icon(Icons.sync),
                    label: Text(l10n.syncNow),
                  ),
                  TextButton(
                    onPressed: s.syncing ? null : controller.turnOff,
                    child: Text(l10n.syncTurnOff),
                  ),
                ],
              ),
            ],
            if (s.failure case final failure?)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  failureText(failure, l10n),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
