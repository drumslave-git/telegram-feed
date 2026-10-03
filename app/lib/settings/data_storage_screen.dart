import 'dart:async';

import 'package:app_db/app_db.dart';
import 'package:flutter/material.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../media/auto_download.dart';
import '../feeds/media_view.dart' show formatBytes;
import '../l10n/l10n.dart';
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
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.dataStorageResetTitle),
        content: Text(l10n.dataStorageResetText),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.commonReset),
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
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.dataStorageTitle)),
      body: ListView(
        children: [
          SettingsHeader(l10n.dataStorageDiskAndNetwork),
          FutureBuilder<StorageStats>(
            future: _storage,
            builder: (context, snap) => SettingsLink(
              icon: Icons.storage_outlined,
              title: l10n.dataStorageStorageUsage,
              value: snap.data == null
                  ? null
                  : formatBytes(snap.data!.totalBytes),
              onTap: _openStorage,
            ),
          ),
          const Divider(),
          SettingsHeader(l10n.dataStorageAutoDownload),
          for (final c in Connection.values)
            _PresetStream(
              db: db,
              connection: c,
              builder: (context, preset) => SplitSwitchTile(
                title: c.rowTitleIn(l10n),
                subtitle: preset.summaryIn(l10n),
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
                title: Text(l10n.dataStorageReset),
                onTap: () => unawaited(_reset(context)),
              );
            },
          ),
          const Divider(),
          SettingsHeader(l10n.dataStorageAutoplay),
          _SettingSwitch(
            db: db,
            settingKey: SettingKeys.autoplayGifs,
            title: l10n.dataStorageGifs,
          ),
          _SettingSwitch(
            db: db,
            settingKey: SettingKeys.autoplay,
            title: l10n.dataStorageVideos,
          ),
          SettingsFooter(l10n.dataStorageAutoplayFooter),
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
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(connection.screenTitleIn(l10n))),
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
              SettingsHeader(l10n.dataStorageDataUsage),
              DataUsageSlider(
                preset: p,
                enabled: on,
                onChanged: (chosen) => _write(p.adopt(chosen)),
              ),
              const Divider(),
              SettingsHeader(l10n.dataStorageMediaTypes),
              SplitSwitchTile(
                title: l10n.dataStoragePhotos,
                subtitle: p.photos
                    ? l10n.dataStorageEveryPhoto
                    : l10n.commonOff,
                value: p.photos,
                enabled: on,
                onTap: () => _write(p.copyWith(photos: !p.photos)),
                onChanged: (v) => _write(p.copyWith(photos: v)),
              ),
              SplitSwitchTile(
                title: l10n.dataStorageVideos,
                subtitle: p.videos
                    ? l10n.dataStorageUpTo(formatLimit(p.videoMaxBytes))
                    : l10n.commonOff,
                value: p.videos,
                enabled: on,
                onTap: () => _sizeSheet(context, p, videos: true),
                onChanged: (v) => _write(p.copyWith(videos: v)),
              ),
              SplitSwitchTile(
                title: l10n.tabFiles,
                subtitle: p.files
                    ? l10n.dataStorageUpTo(formatLimit(p.fileMaxBytes))
                    : l10n.commonOff,
                value: p.files,
                enabled: on,
                onTap: () => _sizeSheet(context, p, videos: false),
                onChanged: (v) => _write(p.copyWith(files: v)),
              ),
              SettingsFooter(l10n.dataStorageTypesFooter),
            ],
          );
        },
      ),
    );
  }

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
    final l10n = context.l10n;
    final names = DownloadPreset.presetNamesIn(l10n);
    final stops = <(String, DownloadPreset)>[
      for (var i = 0; i < DownloadPreset.presets.length; i++)
        (names[i], DownloadPreset.presets[i]),
    ];
    var at = preset.presetIndex;
    if (at < 0) {
      at = stops.indexWhere((s) => s.$2.weight > preset.weight);
      if (at < 0) at = stops.length;
      stops.insert(at, (l10n.dataStoragePresetCustom, preset));
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

/// The largest video or file that loads by itself, in fixed steps over the range of the
/// official app's slider (which moves without steps), and for videos whether the first seconds of larger ones are loaded ahead.
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
    final l10n = context.l10n;
    final size = downloadSizeSteps[_step];
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              widget.videos ? l10n.dataStorageVideos : l10n.tabFiles,
              style: theme.textTheme.titleMedium,
            ),
          ),
          ListTile(
            title: Text(
              widget.videos
                  ? l10n.dataStorageMaxVideoSize
                  : l10n.dataStorageMaxFileSize,
            ),
            trailing: Text(
              l10n.dataStorageUpTo(formatLimit(size)),
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
              title: Text(l10n.dataStoragePreload),
              value: _preload,
              onChanged: (v) => setState(() => _preload = v),
            ),
            SettingsFooter(l10n.dataStoragePreloadFooter(formatLimit(size))),
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
              child: Text(l10n.commonSave),
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
          title: Text(context.l10n.dataStorageAutoDownloadMedia),
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
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.dataStorageClearTitle(formatBytes(bytes))),
        content: Text(l10n.dataStorageClearText),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.commonCancel),
          ),
          DestructiveButton(
            onPressed: () => Navigator.pop(context, true),
            label: l10n.commonClear,
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
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.dataStorageStorageUsage)),
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
                        Text(l10n.dataStorageStatsFailed),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => setState(
                            () => _storage = widget.gateway.storageStats(),
                          ),
                          child: Text(l10n.commonTryAgain),
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
              SettingsHeader(l10n.dataStorageTelegramCache),
              ListTile(
                leading: const Icon(Icons.perm_media_outlined),
                title: Text(l10n.dataStorageCachedFiles),
                subtitle: Text(l10n.dataStorageFileCount(s.fileCount)),
                trailing: Text(formatBytes(s.filesBytes)),
              ),
              ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: Text(l10n.dataStorageDatabase),
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
                        ? l10n.dataStorageClearing
                        : l10n.dataStorageClearCache(formatBytes(s.filesBytes)),
                  ),
                ),
              ),
              SettingsFooter(l10n.dataStorageClearFooter),
            ],
          );
        },
      ),
    );
  }
}
