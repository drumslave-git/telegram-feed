import 'dart:async';
import 'dart:math' as math;

import 'package:app_db/app_db.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../feeds/media_view.dart' show formatBytes;
import '../l10n/l10n.dart';
import '../media/auto_download.dart' show formatLimit;
import '../media/cache_limits.dart';
import '../widgets/destructive_button.dart';
import 'settings_tiles.dart';

/// The colour of a kind of file in the chart and on its checkbox, the same in light and
/// dark, as the official app's chart colours are.
Color storageKindColor(StorageKind kind) => switch (kind) {
  StorageKind.photos => const Color(0xFF4DA9F2),
  StorageKind.videos => const Color(0xFF3478F6),
  StorageKind.files => const Color(0xFF46B963),
  StorageKind.music => const Color(0xFF9B6FE0),
  StorageKind.voice => const Color(0xFF8CC43F),
  StorageKind.stickers => const Color(0xFFF2963A),
  StorageKind.profilePhotos => const Color(0xFF2DBCCB),
  StorageKind.other => const Color(0xFFD6A91B),
};

String storageKindName(StorageKind kind, AppLocalizations l10n) =>
    switch (kind) {
      StorageKind.photos => l10n.dataStoragePhotos,
      StorageKind.videos => l10n.dataStorageVideos,
      StorageKind.files => l10n.tabFiles,
      StorageKind.music => l10n.tabMusic,
      StorageKind.voice => l10n.storageKindVoice,
      StorageKind.stickers => l10n.storageKindStickers,
      StorageKind.profilePhotos => l10n.storageKindProfilePhotos,
      StorageKind.other => l10n.storageKindOther,
    };

/// How long media is kept, as the row and the choices say it.
String keepMediaName(int seconds, AppLocalizations l10n) => switch (seconds) {
  0 => l10n.storageKeepForever,
  CacheLimits.day => l10n.storageKeepDay,
  const (2 * CacheLimits.day) => l10n.storageKeepTwoDays,
  const (7 * CacheLimits.day) => l10n.storageKeepWeek,
  const (30 * CacheLimits.day) => l10n.storageKeepMonth,
  _ => l10n.storageKeepDays((seconds / CacheLimits.day).round()),
};

/// Telegram's cache on this phone, as the official app's Storage Usage shows it: a chart
/// by kind of file, a checkbox per kind and a button that clears the ticked kinds, then
/// how long cached media is kept and how large the cache may grow.
class StorageUsageScreen extends StatefulWidget {
  const StorageUsageScreen({
    super.key,
    required this.gateway,
    required this.db,
  });
  final TelegramGateway gateway;
  final AppDatabase db;

  @override
  State<StorageUsageScreen> createState() => _StorageUsageScreenState();
}

class _StorageUsageScreenState extends State<StorageUsageScreen> {
  late Future<(StorageStats, List<StorageSlice>)> _storage = _load();

  /// The kinds the reader unticked; a kind is ticked until then.
  final _unticked = <StorageKind>{};
  bool _clearing = false;

  Future<(StorageStats, List<StorageSlice>)> _load() async {
    final stats = await widget.gateway.storageStats();
    return (stats, await widget.gateway.storageByKind());
  }

  Future<void> _clear(List<StorageSlice> ticked, {required bool all}) async {
    final l10n = context.l10n;
    final bytes = ticked.fold(0, (sum, s) => sum + s.bytes);
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
      await widget.gateway.clearCache(
        kinds: all ? null : {for (final s in ticked) s.kind},
      );
      final fresh = await _load();
      if (!mounted) return;
      setState(() {
        _storage = Future.value(fresh);
        _unticked.clear();
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

  Future<void> _pickKeep(int current) async {
    final l10n = context.l10n;
    final chosen = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n.storageKeepMedia),
        children: [
          RadioGroup<int>(
            groupValue: current,
            onChanged: (v) => Navigator.pop(context, v),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final seconds in CacheLimits.keepChoices)
                  RadioListTile<int>(
                    value: seconds,
                    title: Text(keepMediaName(seconds, l10n)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (chosen == null || chosen == current) return;
    await widget.db.setSetting(SettingKeys.cacheKeepSeconds, '$chosen');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.dataStorageStorageUsage)),
      body: FutureBuilder<(StorageStats, List<StorageSlice>)>(
        future: _storage,
        builder: (context, snap) {
          final loaded = snap.data;
          if (loaded == null) {
            return Center(
              child: snap.hasError
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(l10n.dataStorageStatsFailed),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => setState(() => _storage = _load()),
                          child: Text(l10n.commonTryAgain),
                        ),
                      ],
                    )
                  : const CircularProgressIndicator(),
            );
          }
          final (stats, slices) = loaded;
          final ticked = [
            for (final s in slices)
              if (!_unticked.contains(s.kind)) s,
          ];
          final all = slices.fold(0, (sum, s) => sum + s.bytes);
          final chosen = ticked.fold(0, (sum, s) => sum + s.bytes);
          final percent = NumberFormat.decimalPercentPattern(
            locale: Localizations.localeOf(context).toLanguageTag(),
            decimalDigits: 1,
          );
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                child: Center(
                  child: StorageChart(
                    slices: ticked,
                    label: formatBytes(chosen),
                  ),
                ),
              ),
              if (slices.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    l10n.storageEmpty,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              for (final s in slices)
                CheckboxListTile(
                  key: ValueKey('kind-${s.kind.name}'),
                  value: !_unticked.contains(s.kind),
                  activeColor: storageKindColor(s.kind),
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  title: Text(
                    '${storageKindName(s.kind, l10n)}  '
                    '${percent.format(all == 0 ? 0 : s.bytes / all)}',
                  ),
                  secondary: Text(formatBytes(s.bytes)),
                  onChanged: _clearing
                      ? null
                      : (v) => setState(() {
                          if (v ?? false) {
                            _unticked.remove(s.kind);
                          } else {
                            _unticked.add(s.kind);
                          }
                        }),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: FilledButton.tonal(
                  onPressed: _clearing || ticked.isEmpty
                      ? null
                      : () => unawaited(
                          _clear(ticked, all: ticked.length == slices.length),
                        ),
                  child: Text(
                    _clearing
                        ? l10n.dataStorageClearing
                        : l10n.dataStorageClearCache(formatBytes(chosen)),
                  ),
                ),
              ),
              SettingsFooter(l10n.dataStorageClearFooter),
              ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: Text(l10n.dataStorageDatabase),
                trailing: Text(formatBytes(stats.databaseBytes)),
              ),
              const Divider(),
              SettingsHeader(l10n.storageAutoRemove),
              StreamBuilder<String?>(
                stream: widget.db.watchSetting(SettingKeys.cacheKeepSeconds),
                builder: (context, snap) {
                  final keep = CacheLimits.keepOf(snap.data);
                  return SettingsLink(
                    icon: Icons.auto_delete_outlined,
                    title: l10n.storageKeepMedia,
                    value: keepMediaName(keep, l10n),
                    onTap: () => unawaited(_pickKeep(keep)),
                  );
                },
              ),
              SettingsFooter(l10n.storageKeepFooter),
              SettingsHeader(l10n.storageMaxSize),
              StreamBuilder<String?>(
                stream: widget.db.watchSetting(SettingKeys.cacheMaxBytes),
                builder: (context, snap) {
                  final max = CacheLimits.maxBytesOf(snap.data);
                  final at = CacheLimits.sizeChoices.indexOf(max);
                  return StopSlider(
                    labels: [
                      for (final bytes in CacheLimits.sizeChoices)
                        bytes == 0 ? l10n.storageNoLimit : formatLimit(bytes),
                    ],
                    // A size no stop stands for (none can be chosen here) is no limit.
                    index: at < 0 ? CacheLimits.sizeChoices.length - 1 : at,
                    onChanged: (i) => unawaited(
                      widget.db.setSetting(
                        SettingKeys.cacheMaxBytes,
                        '${CacheLimits.sizeChoices[i]}',
                      ),
                    ),
                  );
                },
              ),
              SettingsFooter(l10n.storageMaxSizeFooter),
            ],
          );
        },
      ),
    );
  }
}

/// A ring with one arc per kind of file, as large as its share, and [label] (the size
/// of what is ticked) in the middle.
class StorageChart extends StatelessWidget {
  const StorageChart({
    super.key,
    required this.slices,
    required this.label,
    this.size = 176,
  });
  final List<StorageSlice> slices;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: CustomPaint(
            painter: _ChartPainter(
              slices: slices,
              track: theme.colorScheme.surfaceContainerHighest,
            ),
            child: Center(
              child: Text(label, style: theme.textTheme.headlineSmall),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({required this.slices, required this.track});
  final List<StorageSlice> slices;
  final Color track;

  static const _stroke = 20.0;

  /// The gap between two arcs, in radians.
  static const _gap = 0.04;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(_stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke;
    final total = slices.fold(0, (sum, s) => sum + s.bytes);
    if (total == 0) {
      canvas.drawArc(rect, 0, 2 * math.pi, false, paint..color = track);
      return;
    }
    // From the top, clockwise.
    var from = -math.pi / 2;
    for (final s in slices) {
      final sweep = 2 * math.pi * s.bytes / total;
      // A kind too small for the gap is still a mark.
      final drawn = slices.length == 1 ? sweep : math.max(sweep - _gap, 0.01);
      canvas.drawArc(
        rect,
        from + (sweep - drawn) / 2,
        drawn,
        false,
        paint..color = storageKindColor(s.kind),
      );
      from += sweep;
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.track != track || !_same(old.slices, slices);

  static bool _same(List<StorageSlice> a, List<StorageSlice> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// A slider that rests on named stops, each name under its own stop, as the official
/// app's choice between a few values.
class StopSlider extends StatelessWidget {
  const StopSlider({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
  });
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          Slider(
            value: index.toDouble(),
            max: (labels.length - 1).toDouble(),
            divisions: labels.length - 1,
            semanticFormatterCallback: (v) => labels[v.round()],
            onChanged: (v) {
              if (v.round() != index) onChanged(v.round());
            },
          ),
          // Each name under its own stop: the track runs 24 px in from both ends.
          LayoutBuilder(
            builder: (context, box) {
              final step = (box.maxWidth - 48) / (labels.length - 1);
              return SizedBox(
                height: 20,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (var i = 0; i < labels.length; i++)
                      Positioned(
                        left: 24 + i * step,
                        top: 0,
                        child: FractionalTranslation(
                          // The names at the ends stay inside the screen.
                          translation: Offset(
                            i == 0
                                ? -0.25
                                : i == labels.length - 1
                                ? -0.75
                                : -0.5,
                            0,
                          ),
                          child: Text(
                            labels[i],
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: i == index
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant,
                              fontWeight: i == index ? FontWeight.w600 : null,
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
