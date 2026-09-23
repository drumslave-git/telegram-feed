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
import '../service/core_service.dart' show appPaths;
import '../sync/sync_controller.dart';
import '../sync/sync_settings_screen.dart';
import 'accounts_screen.dart';
import 'ai_settings_screen.dart';
import 'chat_settings_screen.dart';
import 'data_storage_screen.dart';
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

  /// The accounts of this device (H-35). The store lives beside the databases, since it
  /// says which of them to open.
  Future<void> _openAccounts() async {
    final switched = AccountSwitch.of(context)?.onSwitched;
    final paths = await appPaths();
    final store = AccountStore(paths.support);
    // The account in use is named after its profile, so the list tells them apart.
    try {
      final me = await _me;
      final name = '${me.firstName} ${me.lastName}'.trim();
      final phone = me.phoneNumber.isEmpty ? '' : me.phoneDisplay;
      final label = [name, phone].where((s) => s.isNotEmpty).join(' · ');
      if (label.isNotEmpty) {
        await store.rename((await store.load()).active, label);
      }
    } on Object {
      // Without the profile the list keeps the names it has.
    }
    if (!mounted) return;
    await openSettingsScreen(
      context,
      AccountsScreen(store: store, onSwitched: switched),
    );
  }

  /// The chat with oneself, read like any channel. A feed cannot hold it: it is not a
  /// channel of the account, it is the account's own notepad.
  Future<void> _openSaved() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final channel = await widget.gateway.savedMessages();
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => TimelineScreen(
            db: widget.db,
            gateway: widget.gateway,
            channel: channel,
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) {
              if (v == 'logout') {
                unawaited(confirmLogOut(context, widget.onLogOut));
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  leading: Icon(Icons.logout),
                  title: Text('Log out'),
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
          SettingsLink(
            icon: Icons.switch_account_outlined,
            title: 'Accounts',
            onTap: () => unawaited(_openAccounts()),
          ),
          SettingsLink(
            icon: Icons.bookmark_outline,
            title: 'Saved Messages',
            onTap: () => unawaited(_openSaved()),
          ),
          const Divider(),
          const SettingsHeader('Settings'),
          SettingsLink(
            icon: Icons.chat_bubble_outline,
            title: 'Chat settings',
            onTap: () => _open(ChatSettingsScreen(db: db)),
          ),
          SettingsLink(
            icon: Icons.lock_outline,
            title: 'Privacy and security',
            onTap: () => _open(PrivacyScreen(db: db)),
          ),
          SettingsLink(
            icon: Icons.notifications_none,
            title: 'Notifications and sounds',
            onTap: () =>
                _open(NotificationsScreen(db: db, onRestart: widget.onRestart)),
          ),
          SettingsLink(
            icon: Icons.data_usage,
            title: 'Data and storage',
            onTap: () =>
                _open(DataStorageScreen(db: db, gateway: widget.gateway)),
          ),
          const Divider(),
          SettingsLink(
            icon: Icons.record_voice_over_outlined,
            title: 'Read aloud',
            onTap: () => _open(ReadAloudScreen(db: db)),
          ),
          StreamBuilder<String?>(
            stream: db.watchSetting(AiKeys.baseUrl),
            builder: (context, snap) => SettingsLink(
              icon: Icons.auto_awesome_outlined,
              title: 'AI rules',
              value: (snap.data ?? '').isEmpty ? 'Off' : 'On',
              onTap: () =>
                  _open(AiSettingsScreen(db: db, secrets: widget.secrets)),
            ),
          ),
          if (widget.sync case final sync?)
            ValueListenableBuilder<SyncStatus>(
              valueListenable: sync.status,
              builder: (context, status, _) => SettingsLink(
                icon: Icons.cloud_sync_outlined,
                title: 'Google Drive sync',
                // Sync still on for this device, but Google wants a new sign-in.
                value: !status.available
                    ? 'Off'
                    : status.isOn
                    ? 'On'
                    : status.error != null
                    ? 'Signed out'
                    : 'Off',
                onTap: () => _open(SyncSettingsScreen(controller: sync)),
              ),
            ),
          const Divider(),
          const SettingsHeader('About'),
          SettingsLink(
            icon: Icons.info_outline,
            title: 'About $appName',
            onTap: () => unawaited(_about(context)),
          ),
          SettingsLink(
            icon: Icons.description_outlined,
            title: 'Open-source licenses',
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
                    ? '$appName for Android'
                    : '$appName for Android ${snap.data}',
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
      content: const Text(
        'Free software under the GNU GPL v3. Reads your joined channels; nothing leaves the '
        'device except Telegram traffic and, if you create AI rules, the posts those rules '
        'check, sent to the endpoint you chose.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
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
    final u = user;
    if (u == null) {
      return ListTile(
        leading: const Icon(Icons.person_outline),
        title: Text(failed ? 'Account unavailable' : 'Loading…'),
        trailing: failed
            ? IconButton(
                tooltip: 'Refresh',
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
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: onRefresh,
          ),
        ],
      ),
    );
  }
}
