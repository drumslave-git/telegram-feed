import 'dart:async';

import 'package:app_db/app_db.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../ai/semantic_gate.dart';
import '../feeds/timeline_screen.dart';
import '../home/channel_list.dart' show ChannelAvatar;
import '../home/log_out.dart';
import '../host/accounts.dart';
import '../l10n/l10n.dart';
import '../sync/sync_controller.dart';
import '../sync/sync_settings_screen.dart';
import 'account_rows.dart';
import 'ai_settings_screen.dart';
import 'chat_settings_screen.dart';
import 'data_storage_screen.dart';
import 'language_screen.dart';
import 'notifications_screen.dart';
import 'privacy_screen.dart';
import 'read_aloud_screen.dart';
import 'settings_tiles.dart';
import '../app_name.dart';

/// The profile and one row per screen of settings, as the official app lays out its
/// Settings: the Telegram groups first, the app's own screens after them, About last.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.db,
    required this.gateway,
    required this.onLogOut,
    this.secrets = const SecureSecretStore(),
    this.sync,
    this.onRestart,
    this.batteryExempt,
    this.onRequestBatteryExemption,
    this.runningInService,
    this.accounts,
  });
  final AppDatabase db;
  final TelegramGateway gateway;
  final Future<void> Function() onLogOut;

  /// Where the AI endpoint's API key is kept; injected in tests.
  final SecretStore secrets;

  /// Drive sync; the entry is hidden when the host has none (tests).
  final SyncController? sync;

  /// Starts the app afresh, which a change of background watching needs.
  final Future<void> Function()? onRestart;

  /// Handed on to Notifications and sounds: whether Android lets the app keep watching
  /// in the background, and where the core runs right now.
  final Future<bool> Function()? batteryExempt;
  final Future<void> Function()? onRequestBatteryExemption;
  final bool Function()? runningInService;

  /// The accounts of this device; the app's own store lives beside the databases, and
  /// tests pass theirs.
  final AccountStore? accounts;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<UserInfo> _me = widget.gateway.me();

  /// "Unofficial Telegram Feed for Android v0.1.0 (1)" under the list, as the official app signs its
  /// Settings; nothing where the platform cannot say (tests).
  final Future<String?> _version = PackageInfo.fromPlatform()
      .then<String?>((i) => 'v${i.version} (${i.buildNumber})')
      .catchError((Object _) => null);

  /// The chat with oneself, read like any channel. A feed cannot hold it: it is not a
  /// channel of the account, it is the account's own notepad.
  Future<void> _openSaved() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final l10n = context.l10n;
    try {
      // Telegram names it in English; the timeline names it in the reader's language.
      final channel = (await widget.gateway.savedMessages()).withTitle(
        l10n.settingsSavedMessages,
      );
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => TimelineScreen(
            db: widget.db,
            gateway: widget.gateway,
            channel: channel,
            savedMessages: true,
          ),
        ),
      );
    } on TelegramException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Telegram: ${e.message}')));
    }
  }

  void _open(Widget screen) => unawaited(openSettingsScreen(context, screen));

  @override
  Widget build(BuildContext context) {
    final db = widget.db;
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.commonSettings),
        actions: [
          PopupMenuButton<String>(
            tooltip: l10n.commonMore,
            onSelected: (v) {
              if (v == 'logout') {
                unawaited(confirmLogOut(context, widget.onLogOut));
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  leading: const Icon(Icons.logout),
                  title: Text(l10n.settingsLogOut),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        children: [
          FutureBuilder<UserInfo>(
            future: _me,
            builder: (context, snap) => AccountHeader(
              user: snap.data,
              failed: snap.hasError,
              gateway: widget.gateway,
              onRefresh: () => setState(() {
                _me = widget.gateway.me();
              }),
            ),
          ),
          AccountRows(store: widget.accounts),
          SettingsLink(
            icon: Icons.bookmark_outline,
            title: l10n.settingsSavedMessages,
            onTap: () => unawaited(_openSaved()),
          ),
          const Divider(),
          SettingsHeader(l10n.commonSettings),
          SettingsLink(
            icon: Icons.chat_bubble_outline,
            title: l10n.chatSettingsTitle,
            onTap: () =>
                _open(ChatSettingsScreen(db: db, gateway: widget.gateway)),
          ),
          SettingsLink(
            icon: Icons.lock_outline,
            title: l10n.settingsPrivacyAndSecurity,
            onTap: () => _open(const PrivacyScreen()),
          ),
          SettingsLink(
            icon: Icons.notifications_none,
            title: l10n.settingsNotificationsAndSounds,
            onTap: () => _open(
              NotificationsScreen(
                db: db,
                onRestart: widget.onRestart,
                batteryExempt: widget.batteryExempt,
                onRequestBatteryExemption: widget.onRequestBatteryExemption,
                runningInService: widget.runningInService,
              ),
            ),
          ),
          SettingsLink(
            icon: Icons.data_usage,
            title: l10n.dataStorageTitle,
            onTap: () =>
                _open(DataStorageScreen(db: db, gateway: widget.gateway)),
          ),
          SettingsLink(
            icon: Icons.language,
            title: l10n.languageTitle,
            // The language in use, under its own name, as the official app's row.
            value: AppLanguage.nameOf(
              Localizations.localeOf(context).languageCode,
            ),
            onTap: () => _open(LanguageScreen(db: db)),
          ),
          const Divider(),
          SettingsLink(
            icon: Icons.record_voice_over_outlined,
            title: l10n.settingsReadAloud,
            onTap: () => _open(ReadAloudScreen(db: db)),
          ),
          StreamBuilder<String?>(
            stream: db.watchSetting(AiKeys.baseUrl),
            builder: (context, snap) => SettingsLink(
              icon: Icons.auto_awesome_outlined,
              title: l10n.aiSettingsTitle,
              value: (snap.data ?? '').isEmpty ? l10n.commonOff : l10n.commonOn,
              onTap: () =>
                  _open(AiSettingsScreen(db: db, secrets: widget.secrets)),
            ),
          ),
          if (widget.sync case final sync?)
            ValueListenableBuilder<SyncStatus>(
              valueListenable: sync.status,
              builder: (context, status, _) => SettingsLink(
                icon: Icons.cloud_sync_outlined,
                title: l10n.syncTitle,
                // Sync still on for this device, but Google wants a new sign-in.
                value: !status.available
                    ? l10n.commonOff
                    : status.isOn
                    ? l10n.commonOn
                    : status.failure != null
                    ? l10n.settingsSyncSignedOut
                    : l10n.commonOff,
                onTap: () => _open(SyncSettingsScreen(controller: sync)),
              ),
            ),
          const Divider(),
          SettingsHeader(l10n.settingsAbout),
          SettingsLink(
            icon: Icons.info_outline,
            title: l10n.settingsAboutApp(appName),
            onTap: () => unawaited(_about(context)),
          ),
          SettingsLink(
            icon: Icons.description_outlined,
            title: l10n.settingsLicenses,
            onTap: () => showLicensePage(
              context: context,
              applicationName: appName,
              applicationLegalese: 'GPL-3.0',
            ),
          ),
          FutureBuilder<String?>(
            future: _version,
            builder: (context, snap) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Text(
                snap.data == null
                    ? l10n.settingsAppForAndroid(appName)
                    : l10n.settingsAppVersion(appName, snap.data!),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _about(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text(appName),
      content: Text(context.l10n.settingsAboutText),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.commonOk),
        ),
      ],
    ),
  );
}

/// The logged-in account as Telegram shows a profile: photo, name, username, phone, bio.
class AccountHeader extends StatelessWidget {
  const AccountHeader({
    super.key,
    required this.user,
    required this.failed,
    required this.gateway,
    required this.onRefresh,
  });
  final UserInfo? user;
  final bool failed;
  final TelegramGateway gateway;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final u = user;
    if (u == null) {
      return ListTile(
        leading: const Icon(Icons.person_outline),
        title: Text(
          failed ? l10n.settingsAccountUnavailable : l10n.commonLoading,
        ),
        trailing: failed
            ? IconButton(
                tooltip: l10n.settingsReloadProfile,
                icon: const Icon(Icons.refresh),
                onPressed: onRefresh,
              )
            : null,
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ChannelAvatar(
            photo: u.photo,
            title: u.displayName,
            gateway: gateway,
            radius: 36,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        u.displayName,
                        style: theme.textTheme.titleLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (u.isPremium)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Icon(
                          Icons.star,
                          size: 18,
                          color: theme.colorScheme.primary,
                          semanticLabel: 'Telegram Premium',
                        ),
                      ),
                  ],
                ),
                if (u.username != null)
                  Text('@${u.username}', style: theme.textTheme.bodyMedium),
                if (u.phoneNumber.isNotEmpty)
                  Text(u.phoneDisplay, style: theme.textTheme.bodyMedium),
                if (u.bio.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(u.bio, style: theme.textTheme.bodySmall),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Telegram ID ${u.id}',
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            // What it refreshes: the bare arrow beside a profile could be anything.
            tooltip: l10n.settingsReloadProfile,
            icon: const Icon(Icons.refresh),
            onPressed: onRefresh,
          ),
        ],
      ),
    );
  }
}
