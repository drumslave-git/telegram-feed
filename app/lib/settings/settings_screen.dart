import 'package:app_db/app_db.dart';
import 'package:flutter/material.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../ai/semantic_gate.dart';
import '../feeds/text_scale.dart';
import '../home/channel_list.dart' show ChannelAvatar;
import '../home/home_placeholder.dart';
import '../media/auto_download.dart';
import '../media/autoplay.dart';
import 'ai_settings_screen.dart';
import '../sync/sync_controller.dart';
import '../sync/sync_settings_screen.dart';
import 'read_aloud_screen.dart';

/// Account, reading, appearance, storage and licenses (SPEC screen list).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.db,
    required this.gateway,
    required this.onLogOut,
    this.secrets = const SecureSecretStore(),
    this.sync,
  });
  final AppDatabase db;
  final TelegramGateway gateway;
  final Future<void> Function() onLogOut;

  /// Where the AI endpoint's API key is kept; injected in tests.
  final SecretStore secrets;

  /// Drive sync; the entry is hidden when the host has none (tests).
  final SyncController? sync;

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
            builder: (context, snap) => AccountHeader(
              user: snap.data,
              failed: snap.hasError,
              gateway: widget.gateway,
              onRefresh: () => setState(() {
                _me = widget.gateway.me();
              }),
            ),
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
          const _Header('Video autoplay'),
          AutoplaySettings(db: widget.db),
          const Divider(),
          const _Header('Automatic downloads'),
          AutoDownloadSettings(db: widget.db),
          const Divider(),
          const _Header('Background'),
          StreamBuilder<String?>(
            stream: widget.db.watchSetting(SettingKeys.backgroundWatching),
            builder: (context, snap) => SwitchListTile(
              secondary: const Icon(Icons.radar_outlined),
              title: const Text('Watch channels in the background'),
              subtitle: const Text(
                'Rules keep running while the app is closed. Off removes the permanent notification, and rules then only notify while the app is open. Takes effect the next time the app starts.',
              ),
              value: snap.data != 'false',
              onChanged: (v) => widget.db.setSetting(
                SettingKeys.backgroundWatching,
                v ? 'true' : 'false',
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'Android shows "Watching channels" as long as the watcher runs and does not '
              'let it be quieter than this: it stays silent and at the bottom of the '
              'shade, without a status bar icon.',
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
          if (widget.sync case final sync?) ...[
            const Divider(),
            const _Header('Sync'),
            ValueListenableBuilder<SyncStatus>(
              valueListenable: sync.status,
              builder: (context, status, _) => ListTile(
                leading: const Icon(Icons.cloud_sync_outlined),
                title: const Text('Google Drive sync'),
                subtitle: Text(
                  SyncSettingsScreen.describe(status, context),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SyncSettingsScreen(controller: sync),
                  ),
                ),
              ),
            ),
          ],
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
          StreamBuilder<String?>(
            stream: widget.db.watchSetting(SettingKeys.postTextScale),
            builder: (context, snap) {
              final factor = PostTextScale.parse(snap.data);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    leading: const Icon(Icons.format_size),
                    title: const Text('Text size in posts'),
                    subtitle: Text('${(factor * 100).round()} %'),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Slider(
                      value: factor,
                      min: PostTextScale.min,
                      max: PostTextScale.max,
                      // 5 % steps: the slider lands on round numbers.
                      divisions:
                          ((PostTextScale.max - PostTextScale.min) / 0.05)
                              .round(),
                      label: '${(factor * 100).round()} %',
                      onChanged: (v) => widget.db.setSetting(
                        SettingKeys.postTextScale,
                        v.toStringAsFixed(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(textScaler: TextScaler.linear(factor)),
                      child: Text(
                        'A post is drawn at this size.',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                  ),
                ],
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

/// Autoplay switch with its two limits (SettingKeys.autoplay*). In Settings, and in a sheet
/// the menu of a video post opens ([showAutoplaySettings]).
class AutoplaySettings extends StatelessWidget {
  const AutoplaySettings({super.key, required this.db});
  final AppDatabase db;

  static const _seconds = [15, 30, 60, 120, 300];
  static const _megabytes = [5, 10, 20, 50, 100];

  Widget _limit({
    required String settingKey,
    required String title,
    required List<int> choices,
    required int fallback,
    required String Function(int) label,
    required bool enabled,
  }) => StreamBuilder<String?>(
    stream: db.watchSetting(settingKey),
    builder: (context, snap) {
      final value = int.tryParse(snap.data ?? '') ?? fallback;
      return ListTile(
        enabled: enabled,
        contentPadding: const EdgeInsets.only(left: 72, right: 16),
        title: Text(title),
        trailing: DropdownButton<int>(
          value: choices.contains(value) ? value : fallback,
          onChanged: enabled
              ? (v) => db.setSetting(settingKey, '${v ?? fallback}')
              : null,
          items: [
            for (final c in choices)
              DropdownMenuItem(value: c, child: Text(label(c))),
          ],
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) => StreamBuilder<String?>(
    stream: db.watchSetting(SettingKeys.autoplay),
    builder: (context, snap) {
      final on = snap.data != 'false';
      return Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.play_circle_outline),
            title: const Text('Autoplay short videos'),
            subtitle: const Text(
              'Muted, when they scroll into view; tap one for sound',
            ),
            value: on,
            onChanged: (v) =>
                db.setSetting(SettingKeys.autoplay, v ? 'true' : 'false'),
          ),
          _limit(
            settingKey: SettingKeys.autoplayMaxSeconds,
            title: 'No longer than',
            choices: _seconds,
            fallback: AutoplayPolicy.defaultMaxSeconds,
            label: (s) => s < 60 ? '$s s' : '${s ~/ 60} min',
            enabled: on,
          ),
          _limit(
            settingKey: SettingKeys.autoplayMaxMegabytes,
            title: 'No larger than',
            choices: _megabytes,
            fallback: AutoplayPolicy.defaultMaxMegabytes,
            label: (m) => '$m MB',
            enabled: on,
          ),
        ],
      );
    },
  );
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

/// The autoplay settings right where videos play: a sheet over the timeline.
Future<void> showAutoplaySettings(BuildContext context, AppDatabase db) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Video autoplay',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            AutoplaySettings(db: db),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

/// Whether pictures load by themselves, per kind of connection, with a size limit each —
/// the official app's automatic downloads, kept to what this app fetches on its own.
class AutoDownloadSettings extends StatelessWidget {
  const AutoDownloadSettings({super.key, required this.db});
  final AppDatabase db;

  Widget _row({
    required String title,
    required String subtitle,
    required String flagKey,
    required String limitKey,
    required int defaultMb,
  }) => StreamBuilder<String?>(
    stream: db.watchSetting(flagKey),
    builder: (context, flag) {
      final on = flag.data != 'false';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            value: on,
            title: Text(title),
            subtitle: Text(subtitle),
            onChanged: (v) => db.setSetting(flagKey, '$v'),
          ),
          if (on)
            StreamBuilder<String?>(
              stream: db.watchSetting(limitKey),
              builder: (context, limit) {
                final mb = int.tryParse(limit.data ?? '') ?? defaultMb;
                return ListTile(
                  title: const Text('Largest picture'),
                  subtitle: Text('$mb MB'),
                  trailing: SizedBox(
                    width: 180,
                    child: Slider(
                      value: mb.clamp(1, 50).toDouble(),
                      min: 1,
                      max: 50,
                      divisions: 49,
                      label: '$mb MB',
                      onChanged: (v) => db.setSetting(limitKey, '${v.round()}'),
                    ),
                  ),
                );
              },
            ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _row(
        title: 'Pictures on Wi-Fi',
        subtitle: 'Load pictures without asking on an unmetered connection',
        flagKey: SettingKeys.autoDownloadWifi,
        limitKey: SettingKeys.autoDownloadWifiMaxMb,
        defaultMb: AutoDownloadPolicy.defaultWifiMaxMb,
      ),
      _row(
        title: 'Pictures on mobile data',
        subtitle: 'Metered Wi-Fi counts as mobile data',
        flagKey: SettingKeys.autoDownloadMobile,
        limitKey: SettingKeys.autoDownloadMobileMaxMb,
        defaultMb: AutoDownloadPolicy.defaultMobileMaxMb,
      ),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Text(
          'Videos follow the autoplay limits above; files and voice messages always wait '
          'for a tap.',
        ),
      ),
    ],
  );
}
