import 'dart:async';

import 'package:app_db/app_db.dart';
import 'package:flutter/material.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../media/auto_download.dart';
import '../feeds/media_view.dart' show formatBytes;
import 'settings_tiles.dart';
import '../widgets/destructive_button.dart';

/// What the app keeps on the phone and what it loads by itself: the official app's Data
/// and Storage, with the automatic downloads per connection and the Autoplay switches
/// under them, as the official app had them before Power Saving.
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

  Future<void> _reset(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset auto-download settings?'),
        content: const Text(
          'Mobile data goes back to Medium, Wi-Fi to High and roaming to Low.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (!(ok ?? false)) return;
    for (final c in Connection.values) {
      await widget.db.setSetting(c.settingKey, c.defaults.encode());
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = widget.db;
    return Scaffold(
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
          const SettingsHeader('Automatic media download'),
          for (final c in Connection.values)
            _PresetStream(
              db: db,
              connection: c,
              builder: (context, preset) => SplitSwitchTile(
                title: c.rowTitle,
                subtitle: preset.summary,
                value: preset.enabled,
                onTap: () => openSettingsScreen(
                  context,
                  AutoDownloadScreen(db: db, connection: c),
                ),
                onChanged: (v) => db.setSetting(
                  c.settingKey,
                  preset.copyWith(enabled: v).encode(),
                ),
              ),
            ),
          _AllPresets(
            db: db,
            builder: (context, presets) {
              final changed = [
                for (final c in Connection.values)
                  if (presets[c] != c.defaults) c,
              ].isNotEmpty;
              return ListTile(
                enabled: changed,
                title: const Text('Reset auto-download settings'),
                onTap: () => unawaited(_reset(context)),
              );
            },
          ),
          const Divider(),
          const SettingsHeader('Autoplay media'),
          _SettingSwitch(
            db: db,
            settingKey: SettingKeys.autoplayGifs,
            title: 'GIFs',
          ),
          _SettingSwitch(
            db: db,
            settingKey: SettingKeys.autoplay,
            title: 'Videos',
          ),
          const SettingsFooter(
            'A video that loads by itself on the connection the phone is on plays muted '
            'in its post; a tap opens it with sound.',
          ),
        ],
      ),
    );
  }
}

/// One connection's automatic downloads, as the official app's "Using mobile data" screen:
/// the switch of the whole connection, the data-usage slider over Telegram's presets, and
/// the kinds of media with their limits.
class AutoDownloadScreen extends StatelessWidget {
  const AutoDownloadScreen({
    super.key,
    required this.db,
    required this.connection,
  });
  final AppDatabase db;
  final Connection connection;

  Future<void> _write(DownloadPreset p) =>
      db.setSetting(connection.settingKey, p.encode());

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(connection.screenTitle)),
    body: _PresetStream(
      db: db,
      connection: connection,
      builder: (context, p) {
        final on = p.enabled;
        return ListView(
          children: [
            _MasterSwitch(
              value: on,
              onChanged: (v) => _write(p.copyWith(enabled: v)),
            ),
            const SettingsHeader('Data usage'),
            DataUsageSlider(
              preset: p,
              enabled: on,
              onChanged: (chosen) => _write(p.adopt(chosen)),
            ),
            const Divider(),
            const SettingsHeader('Types of media'),
            SplitSwitchTile(
              title: 'Photos',
              subtitle: p.photos ? 'Every photo' : 'Off',
              value: p.photos,
              enabled: on,
              onTap: () => _write(p.copyWith(photos: !p.photos)),
              onChanged: (v) => _write(p.copyWith(photos: v)),
            ),
            SplitSwitchTile(
              title: 'Videos',
              subtitle: p.videos
                  ? 'Up to ${formatLimit(p.videoMaxBytes)}'
                  : 'Off',
              value: p.videos,
              enabled: on,
              onTap: () => _sizeSheet(context, p, videos: true),
              onChanged: (v) => _write(p.copyWith(videos: v)),
            ),
            SplitSwitchTile(
              title: 'Files',
              subtitle: p.files
                  ? 'Up to ${formatLimit(p.fileMaxBytes)}'
                  : 'Off',
              value: p.files,
              enabled: on,
              onTap: () => _sizeSheet(context, p, videos: false),
              onChanged: (v) => _write(p.copyWith(files: v)),
            ),
            const SettingsFooter(
              'GIFs and round video messages count as videos, music and voice messages as '
              'files. A video within the limit also autoplays, if Autoplay is on for it '
              'in Data and storage.',
            ),
          ],
        );
      },
    ),
  );

  Future<void> _sizeSheet(
    BuildContext context,
    DownloadPreset p, {
    required bool videos,
  }) async {
    final chosen = await showModalBottomSheet<DownloadPreset>(
      context: context,
      showDragHandle: true,
      builder: (context) => _SizeSheet(preset: p, videos: videos),
    );
    if (chosen != null) await _write(chosen);
  }
}

/// The slider under "Data usage": Low, Medium, High, and the reader's own choice placed
/// between them by how much it spends, as the official app shows it.
class DataUsageSlider extends StatelessWidget {
  const DataUsageSlider({
    super.key,
    required this.preset,
    required this.enabled,
    required this.onChanged,
  });
  final DownloadPreset preset;
  final bool enabled;
  final ValueChanged<DownloadPreset> onChanged;

  @override
  Widget build(BuildContext context) {
    final stops = <(String, DownloadPreset)>[
      for (var i = 0; i < DownloadPreset.presets.length; i++)
        (DownloadPreset.presetNames[i], DownloadPreset.presets[i]),
    ];
    var at = preset.presetIndex;
    if (at < 0) {
      at = stops.indexWhere((s) => s.$2.weight > preset.weight);
      if (at < 0) at = stops.length;
      stops.insert(at, ('Custom', preset));
    }
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          Slider(
            value: at.toDouble(),
            max: (stops.length - 1).toDouble(),
            divisions: stops.length - 1,
            onChanged: enabled
                ? (v) {
                    final chosen = stops[v.round()].$2;
                    if (!identical(chosen, preset)) onChanged(chosen);
                  }
                : null,
          ),
          // Each name under its own stop: the track runs 24 px in from both ends.
          LayoutBuilder(
            builder: (context, box) {
              final step = (box.maxWidth - 48) / (stops.length - 1);
              return SizedBox(
                height: 20,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (var i = 0; i < stops.length; i++)
                      Positioned(
                        left: 24 + i * step,
                        top: 0,
                        child: FractionalTranslation(
                          translation: const Offset(-0.5, 0),
                          child: Text(
                            stops[i].$1,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: i == at
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant,
                              fontWeight: i == at ? FontWeight.w600 : null,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// The largest video or file that loads by itself, in the steps the official app's slider
/// has, and for videos whether the first seconds of larger ones are loaded ahead.
class _SizeSheet extends StatefulWidget {
  const _SizeSheet({required this.preset, required this.videos});
  final DownloadPreset preset;
  final bool videos;

  @override
  State<_SizeSheet> createState() => _SizeSheetState();
}

/// From 500 KB to 2 GB, finer where the choices matter.
const downloadSizeSteps = [
  500 * 1024,
  1 * 1024 * 1024,
  2 * 1024 * 1024,
  3 * 1024 * 1024,
  5 * 1024 * 1024,
  10 * 1024 * 1024,
  15 * 1024 * 1024,
  20 * 1024 * 1024,
  30 * 1024 * 1024,
  50 * 1024 * 1024,
  100 * 1024 * 1024,
  200 * 1024 * 1024,
  300 * 1024 * 1024,
  500 * 1024 * 1024,
  1000 * 1024 * 1024,
  1500 * 1024 * 1024,
  2000 * 1024 * 1024,
];

/// The step nearest to [bytes].
int downloadSizeStep(int bytes) {
  var best = 0;
  for (var i = 1; i < downloadSizeSteps.length; i++) {
    if ((downloadSizeSteps[i] - bytes).abs() <
        (downloadSizeSteps[best] - bytes).abs()) {
      best = i;
    }
  }
  return best;
}

class _SizeSheetState extends State<_SizeSheet> {
  late int _step = downloadSizeStep(
    widget.videos ? widget.preset.videoMaxBytes : widget.preset.fileMaxBytes,
  );
  late bool _preload = widget.preset.preloadLargeVideos;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = downloadSizeSteps[_step];
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              widget.videos ? 'Videos' : 'Files',
              style: theme.textTheme.titleMedium,
            ),
          ),
          ListTile(
            title: Text(
              widget.videos ? 'Maximum video size' : 'Maximum file size',
            ),
            trailing: Text(
              'Up to ${formatLimit(size)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Slider(
              value: _step.toDouble(),
              max: (downloadSizeSteps.length - 1).toDouble(),
              divisions: downloadSizeSteps.length - 1,
              label: formatLimit(size),
              onChanged: (v) => setState(() => _step = v.round()),
            ),
          ),
          if (widget.videos) ...[
            SwitchListTile(
              title: const Text('Preload larger videos'),
              value: _preload,
              onChanged: (v) => setState(() => _preload = v),
            ),
            SettingsFooter(
              'The first seconds of videos larger than ${formatLimit(size)} are loaded '
              'ahead, so that they start at once.',
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: FilledButton(
              onPressed: () => Navigator.pop(
                context,
                widget.videos
                    ? widget.preset.copyWith(
                        videos: true,
                        videoMaxBytes: size,
                        preloadLargeVideos: _preload,
                      )
                    : widget.preset.copyWith(files: true, fileMaxBytes: size),
              ),
              child: const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }
}

/// A row whose text opens something and whose switch, behind a thin divider, only
/// switches: the official app's cell for a connection or a kind of media.
class SplitSwitchTile extends StatelessWidget {
  const SplitSwitchTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onTap,
    required this.onChanged,
    this.enabled = true,
  });
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final VoidCallback onTap;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: ListTile(
            enabled: enabled,
            title: Text(title),
            subtitle: Text(subtitle),
            onTap: onTap,
          ),
        ),
        SizedBox(
          height: 32,
          child: VerticalDivider(width: 1, color: theme.dividerColor),
        ),
        // The same right edge as the switches of a SwitchListTile.
        Padding(
          padding: const EdgeInsets.only(left: 12, right: 24),
          child: Switch(value: value, onChanged: enabled ? onChanged : null),
        ),
      ],
    );
  }
}

/// The switch of the whole connection, on a tinted band at the top as in the official app.
class _MasterSwitch extends StatelessWidget {
  const _MasterSwitch({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Material(
        color: value ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: SwitchListTile(
          title: const Text('Auto-download media'),
          value: value,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _SettingSwitch extends StatelessWidget {
  const _SettingSwitch({
    required this.db,
    required this.settingKey,
    required this.title,
  });
  final AppDatabase db;
  final String settingKey;
  final String title;

  @override
  Widget build(BuildContext context) => StreamBuilder<String?>(
    stream: db.watchSetting(settingKey),
    builder: (context, snap) => SwitchListTile(
      title: Text(title),
      value: snap.data != 'false',
      onChanged: (v) => db.setSetting(settingKey, '$v'),
    ),
  );
}

/// One connection's preset as it is stored, its default until then.
class _PresetStream extends StatelessWidget {
  const _PresetStream({
    required this.db,
    required this.connection,
    required this.builder,
  });
  final AppDatabase db;
  final Connection connection;
  final Widget Function(BuildContext, DownloadPreset) builder;

  @override
  Widget build(BuildContext context) => StreamBuilder<String?>(
    stream: db.watchSetting(connection.settingKey),
    builder: (context, snap) =>
        builder(context, DownloadPreset.decode(snap.data, connection.defaults)),
  );
}

/// The presets of all three connections, for the reset row.
class _AllPresets extends StatelessWidget {
  const _AllPresets({required this.db, required this.builder});
  final AppDatabase db;
  final Widget Function(BuildContext, Map<Connection, DownloadPreset>) builder;

  @override
  Widget build(BuildContext context) => _PresetStream(
    db: db,
    connection: Connection.mobile,
    builder: (context, mobile) => _PresetStream(
      db: db,
      connection: Connection.wifi,
      builder: (context, wifi) => _PresetStream(
        db: db,
        connection: Connection.roaming,
        builder: (context, roaming) => builder(context, {
          Connection.mobile: mobile,
          Connection.wifi: wifi,
          Connection.roaming: roaming,
        }),
      ),
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

  Future<void> _clearCache(int bytes) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Clear ${formatBytes(bytes)} of cache?'),
        content: const Text(
          'Pictures, videos and files load again from Telegram when you open them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          DestructiveButton(
            onPressed: () => Navigator.pop(context, true),
            label: 'Clear',
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
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
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Telegram did not say how much it stores.'),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => setState(
                          () => _storage = widget.gateway.storageStats(),
                        ),
                        child: const Text('Try again'),
                      ),
                    ],
                  )
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
                onPressed: _clearing
                    ? null
                    : () => unawaited(_clearCache(s.filesBytes)),
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
