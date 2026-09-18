import 'package:app_db/app_db.dart';
import 'package:flutter/material.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../ai/semantic_gate.dart';
import '../home/home_placeholder.dart';
import 'ai_settings_screen.dart';
import 'read_aloud_screen.dart';

/// Account, reading, appearance, storage and licenses (SPEC screen list).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.db,
    required this.gateway,
    required this.onLogOut,
    this.secrets = const SecureSecretStore(),
  });
  final AppDatabase db;
  final TelegramGateway gateway;
  final Future<void> Function() onLogOut;

  /// Where the AI endpoint's API key is kept; injected in tests.
  final SecretStore secrets;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<UserInfo> _me = widget.gateway.me();
  late Future<StorageStats> _storage = widget.gateway.storageStats();
  bool _clearing = false;

  Future<void> _clearCache() async {
    setState(() => _clearing = true);
    try {
      final stats = await widget.gateway.clearCache();
      setState(() {
        _storage = Future.value(stats);
      });
    } on TelegramException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Telegram: ${e.message}')));
      }
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _Header('Account'),
          FutureBuilder<UserInfo>(
            future: _me,
            builder: (context, snap) {
              final u = snap.data;
              return ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(
                  u == null
                      ? (snap.hasError ? 'Account unavailable' : 'Loading…')
                      : u.displayName,
                ),
                subtitle: u == null
                    ? null
                    : Text(
                        [
                          if (u.username != null) '@${u.username}',
                          u.phoneNumber,
                        ].where((s) => s.isNotEmpty).join(' · '),
                      ),
                trailing: IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => setState(() {
                    _me = widget.gateway.me();
                  }),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Log out'),
            subtitle: const Text(
              'Deletes feeds, read positions and settings on this device',
            ),
            trailing: LogOutAction(onLogOut: widget.onLogOut),
          ),
          const Divider(),
          const _Header('Reading'),
          StreamBuilder<String?>(
            stream: widget.db.watchSetting(SettingKeys.syncReadToTelegram),
            builder: (context, snap) => SwitchListTile(
              secondary: const Icon(Icons.done_all),
              title: const Text('Mark posts read in Telegram'),
              subtitle: const Text(
                'What you scroll past here counts as read in the official app',
              ),
              value: snap.data != 'false',
              onChanged: (v) => widget.db.setSetting(
                SettingKeys.syncReadToTelegram,
                v ? 'true' : 'false',
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.record_voice_over_outlined),
            title: const Text('Read aloud'),
            subtitle: const Text('Speed, voices per language, length'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ReadAloudScreen(db: widget.db),
              ),
            ),
          ),
          const Divider(),
          const _Header('Rules'),
          StreamBuilder<String?>(
            stream: widget.db.watchSetting(AiKeys.baseUrl),
            builder: (context, snap) => ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('AI rules'),
              subtitle: Text(
                (snap.data ?? '').isEmpty
                    ? 'Not set up. Rules that describe a topic in your own words'
                    : 'Endpoint: ${snap.data}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      AiSettingsScreen(db: widget.db, secrets: widget.secrets),
                ),
              ),
            ),
          ),
          const Divider(),
          const _Header('Appearance'),
          StreamBuilder<String?>(
            stream: widget.db.watchSetting(SettingKeys.themeMode),
            builder: (context, snap) {
              final current = snap.data ?? 'system';
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'system',
                      label: Text('System'),
                      icon: Icon(Icons.brightness_auto),
                    ),
                    ButtonSegment(
                      value: 'light',
                      label: Text('Light'),
                      icon: Icon(Icons.light_mode),
                    ),
                    ButtonSegment(
                      value: 'dark',
                      label: Text('Dark'),
                      icon: Icon(Icons.dark_mode),
                    ),
                  ],
                  selected: {current},
                  onSelectionChanged: (s) =>
                      widget.db.setSetting(SettingKeys.themeMode, s.first),
                ),
              );
            },
          ),
          const Divider(),
          const _Header('Storage'),
          FutureBuilder<StorageStats>(
            future: _storage,
            builder: (context, snap) {
              final s = snap.data;
              return ListTile(
                leading: const Icon(Icons.storage_outlined),
                title: Text(
                  s == null
                      ? (snap.hasError ? 'Storage unavailable' : 'Measuring…')
                      : formatBytes(s.totalBytes),
                ),
                subtitle: s == null
                    ? null
                    : Text(
                        '${s.fileCount} cached files (${formatBytes(s.filesBytes)}), database ${formatBytes(s.databaseBytes)}',
                      ),
                trailing: FilledButton.tonal(
                  onPressed: _clearing || s == null ? null : _clearCache,
                  child: Text(_clearing ? 'Clearing…' : 'Clear cache'),
                ),
              );
            },
          ),
          const Divider(),
          const _Header('About'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('telegram-feed'),
            subtitle: Text(
              'Free software under the GNU GPL v3. Reads your joined channels; nothing leaves the device except Telegram traffic and, if you create AI rules, the posts those rules check, sent to the endpoint you chose.',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Open-source licenses'),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'telegram-feed',
              applicationLegalese: 'GPL-3.0',
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}

String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return i == 0
      ? '$bytes B'
      : '${v.toStringAsFixed(v >= 10 ? 0 : 1)} ${units[i]}';
}
