import 'package:app_db/app_db.dart';
import 'package:flutter/material.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../media/auto_download.dart';
import '../media/autoplay.dart';
import 'settings_screen.dart' show formatBytes;
import 'settings_tiles.dart';

/// What the app keeps on the phone and what it loads by itself: the official app's Data
/// and Storage.
class DataStorageScreen extends StatefulWidget {
  const DataStorageScreen({super.key, required this.db, required this.gateway});
  final AppDatabase db;
  final TelegramGateway gateway;

  @override
  State<DataStorageScreen> createState() => _DataStorageScreenState();
}

class _DataStorageScreenState extends State<DataStorageScreen> {
  late Future<StorageStats> _storage = widget.gateway.storageStats();

  Future<void> _openStorage() async {
    await openSettingsScreen(
      context,
      StorageUsageScreen(gateway: widget.gateway),
    );
    // The cache may have been cleared there.
    if (mounted) {
      setState(() {
        _storage = widget.gateway.storageStats();
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Data and storage')),
    body: ListView(
      children: [
        const SettingsHeader('Disk and network usage'),
        FutureBuilder<StorageStats>(
          future: _storage,
          builder: (context, snap) => SettingsLink(
            icon: Icons.storage_outlined,
            title: 'Storage usage',
            value: snap.data == null
                ? null
                : formatBytes(snap.data!.totalBytes),
            onTap: _openStorage,
          ),
        ),
        const Divider(),
        const SettingsHeader('Automatic downloads'),
        AutoDownloadSettings(db: widget.db),
        const Divider(),
        const SettingsHeader('Video autoplay'),
        AutoplaySettings(db: widget.db),
      ],
    ),
  );
}

/// Telegram's cache on this phone and the button that empties it.
class StorageUsageScreen extends StatefulWidget {
  const StorageUsageScreen({super.key, required this.gateway});
  final TelegramGateway gateway;

  @override
  State<StorageUsageScreen> createState() => _StorageUsageScreenState();
}

class _StorageUsageScreenState extends State<StorageUsageScreen> {
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Storage usage')),
    body: FutureBuilder<StorageStats>(
      future: _storage,
      builder: (context, snap) {
        final s = snap.data;
        if (s == null) {
          return Center(
            child: snap.hasError
                ? const Text('Storage unavailable')
                : const CircularProgressIndicator(),
          );
        }
        return ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Text(
                formatBytes(s.totalBytes),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            const SettingsHeader("Telegram's cache"),
            ListTile(
              leading: const Icon(Icons.perm_media_outlined),
              title: const Text('Cached files'),
              subtitle: Text('${s.fileCount} files'),
              trailing: Text(formatBytes(s.filesBytes)),
            ),
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: const Text('Database'),
              trailing: Text(formatBytes(s.databaseBytes)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: FilledButton.tonal(
                onPressed: _clearing ? null : _clearCache,
                child: Text(
                  _clearing
                      ? 'Clearing…'
                      : 'Clear cache (${formatBytes(s.filesBytes)})',
                ),
              ),
            ),
            const SettingsFooter(
              'Pictures, videos and files are loaded again from Telegram when you open '
              'them. Your feeds, rules and read positions stay.',
            ),
          ],
        );
      },
    ),
  );
}

/// Autoplay switch with its two limits (SettingKeys.autoplay*). In Data and storage, and in
/// a sheet the menu of a video post opens ([showAutoplaySettings]).
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
      const SettingsFooter(
        'Videos follow the autoplay limits below; files and voice messages always wait '
        'for a tap.',
      ),
    ],
  );
}
