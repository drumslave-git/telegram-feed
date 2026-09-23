import 'dart:async';
import 'dart:convert';

import 'package:app_db/app_db.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../feeds/media_view.dart' show formatBytes;

/// What the phone is connected to. Metered Wi-Fi counts as [mobile]: the reader who limits
/// mobile data means the bill, not the radio. [roaming] is mobile data on a network abroad.
enum NetworkType { wifi, mobile, roaming, none }

/// Asks Android what the connection is (`tf/network`).
class NetworkWatcher {
  const NetworkWatcher({MethodChannel? channel})
    : _channel = channel ?? _default;
  static const _default = MethodChannel('tf/network');
  final MethodChannel _channel;

  Future<NetworkType> type() async {
    try {
      final said = await _channel.invokeMethod<String>('type');
      return switch (said) {
        'wifi' => NetworkType.wifi,
        'mobile' => NetworkType.mobile,
        'roaming' => NetworkType.roaming,
        _ => NetworkType.none,
      };
    } on PlatformException {
      // Nothing to go on: behave as the most careful case does.
      return NetworkType.roaming;
    } on MissingPluginException {
      return NetworkType.wifi; // tests and desktop
    }
  }
}

/// The three kinds of connection the official app keeps automatic downloads for.
enum Connection {
  mobile(
    SettingKeys.downloadMobile,
    'When using mobile data',
    'Using mobile data',
  ),
  wifi(SettingKeys.downloadWifi, 'When connected on Wi-Fi', 'Using Wi-Fi'),
  roaming(SettingKeys.downloadRoaming, 'When roaming', 'Roaming');

  const Connection(this.settingKey, this.rowTitle, this.screenTitle);
  final String settingKey;
  final String rowTitle;
  final String screenTitle;

  /// Telegram's own choice for a fresh install: medium on mobile data, high on Wi-Fi, low
  /// while roaming.
  DownloadPreset get defaults => switch (this) {
    Connection.mobile => DownloadPreset.medium,
    Connection.wifi => DownloadPreset.high,
    Connection.roaming => DownloadPreset.low,
  };
}

const _mb = 1024 * 1024;

/// A size limit as the official app writes one: "1 MB", "500 KB", "1.5 GB".
String formatLimit(int bytes) {
  final s = formatBytes(bytes);
  return s.replaceFirst('.0 ', ' ');
}

/// What loads by itself on one kind of connection, as the official app's "Automatic media
/// download" has it: a switch for the whole connection, and photos, videos and files, the
/// last two up to a size. Videos include GIFs and round video messages; files include music
/// and voice messages. A video that loads by itself also autoplays ([AutoDownloadPolicy]).
@immutable
final class DownloadPreset {
  const DownloadPreset({
    this.enabled = true,
    this.photos = true,
    this.videos = true,
    this.videoMaxBytes = 10 * _mb,
    this.files = true,
    this.fileMaxBytes = 1 * _mb,
    this.preloadLargeVideos = true,
  });

  /// Telegram's three presets (the official app's `DownloadController`, the same values
  /// TDLib's `getAutoDownloadSettingsPresets` answers with).
  static const low = DownloadPreset(
    videos: false,
    videoMaxBytes: 500 * 1024,
    files: false,
    fileMaxBytes: 500 * 1024,
    preloadLargeVideos: false,
  );
  static const medium = DownloadPreset();
  static const high = DownloadPreset(
    videoMaxBytes: 15 * _mb,
    fileMaxBytes: 3 * _mb,
  );
  static const presets = [low, medium, high];
  static const presetNames = ['Low', 'Medium', 'High'];

  /// The switch of the whole connection; off, nothing loads by itself.
  final bool enabled;
  final bool photos;
  final bool videos;
  final int videoMaxBytes;
  final bool files;
  final int fileMaxBytes;

  /// The first seconds of a video over [videoMaxBytes] are loaded, so a tap plays it at once.
  final bool preloadLargeVideos;

  DownloadPreset copyWith({
    bool? enabled,
    bool? photos,
    bool? videos,
    int? videoMaxBytes,
    bool? files,
    int? fileMaxBytes,
    bool? preloadLargeVideos,
  }) => DownloadPreset(
    enabled: enabled ?? this.enabled,
    photos: photos ?? this.photos,
    videos: videos ?? this.videos,
    videoMaxBytes: videoMaxBytes ?? this.videoMaxBytes,
    files: files ?? this.files,
    fileMaxBytes: fileMaxBytes ?? this.fileMaxBytes,
    preloadLargeVideos: preloadLargeVideos ?? this.preloadLargeVideos,
  );

  /// The kinds and limits of [preset], this connection's switch kept.
  DownloadPreset adopt(DownloadPreset preset) =>
      preset.copyWith(enabled: enabled);

  /// Same kinds and limits; the connection's switch is not part of a preset.
  bool sameKindsAs(DownloadPreset o) =>
      photos == o.photos &&
      videos == o.videos &&
      videoMaxBytes == o.videoMaxBytes &&
      files == o.files &&
      fileMaxBytes == o.fileMaxBytes &&
      preloadLargeVideos == o.preloadLargeVideos;

  /// Index into [presets], or -1 for a choice of the reader's own.
  int get presetIndex => presets.indexWhere(sameKindsAs);

  /// How much this spends, to place a choice of one's own between the presets on the
  /// data-usage slider, as the official app does.
  int get weight =>
      (photos ? 1 : 0) +
      (videos ? videoMaxBytes : 0) +
      (files ? fileMaxBytes : 0);

  /// The line under the connection's row: "Photos, Videos (10 MB), Files (1 MB)".
  String get summary {
    if (!enabled) return 'Disabled';
    final kinds = [
      if (photos) 'Photos',
      if (videos) 'Videos (${formatLimit(videoMaxBytes)})',
      if (files) 'Files (${formatLimit(fileMaxBytes)})',
    ];
    return kinds.isEmpty ? 'Nothing' : kinds.join(', ');
  }

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'photos': photos,
    'videos': videos,
    'videoMaxBytes': videoMaxBytes,
    'files': files,
    'fileMaxBytes': fileMaxBytes,
    'preloadLargeVideos': preloadLargeVideos,
  };

  String encode() => jsonEncode(toJson());

  /// [fallback] where nothing was stored or the value cannot be read.
  static DownloadPreset decode(String? value, DownloadPreset fallback) {
    if (value == null || value.isEmpty) return fallback;
    try {
      final m = jsonDecode(value) as Map<String, Object?>;
      return DownloadPreset(
        enabled: m['enabled'] as bool? ?? fallback.enabled,
        photos: m['photos'] as bool? ?? fallback.photos,
        videos: m['videos'] as bool? ?? fallback.videos,
        videoMaxBytes: m['videoMaxBytes'] as int? ?? fallback.videoMaxBytes,
        files: m['files'] as bool? ?? fallback.files,
        fileMaxBytes: m['fileMaxBytes'] as int? ?? fallback.fileMaxBytes,
        preloadLargeVideos:
            m['preloadLargeVideos'] as bool? ?? fallback.preloadLargeVideos,
      );
    } on Object {
      return fallback;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is DownloadPreset && other.enabled == enabled && sameKindsAs(other);
  @override
  int get hashCode => Object.hash(
    enabled,
    photos,
    videos,
    videoMaxBytes,
    files,
    fileMaxBytes,
    preloadLargeVideos,
  );
}

/// Whether a picture, a video or a file loads by itself, and whether a video autoplays:
/// the preset of the connection the phone is on, and the two Autoplay switches. A video
/// autoplays only when it loads by itself, as in the official app.
@immutable
final class AutoDownloadPolicy {
  const AutoDownloadPolicy({
    required this.network,
    this.mobile = DownloadPreset.medium,
    this.wifi = DownloadPreset.high,
    this.roaming = DownloadPreset.low,
    this.autoplayVideos = true,
    this.autoplayGifs = true,
    this.ready = true,
  });

  /// Pictures load and nothing else does: what a screen without a scope does (widget tests
  /// of single media views).
  const AutoDownloadPolicy.picturesOnly()
    : this(network: NetworkType.wifi, wifi: DownloadPreset.low);

  /// Nothing is known yet: the settings have not been read. A row waits rather than
  /// download something the reader may have asked it not to.
  const AutoDownloadPolicy.unknown()
    : this(network: NetworkType.none, ready: false);

  final NetworkType network;
  final DownloadPreset mobile;
  final DownloadPreset wifi;
  final DownloadPreset roaming;
  final bool autoplayVideos;
  final bool autoplayGifs;

  /// False until the settings and the connection are known.
  final bool ready;

  /// How many bytes of a larger video are loaded ahead: a few seconds of it.
  static const preloadBytes = 2 * _mb;

  /// The preset of the connection the phone is on, if it is on one and it is switched on.
  DownloadPreset? get _current {
    if (!ready) return null;
    final p = switch (network) {
      NetworkType.wifi => wifi,
      NetworkType.mobile => mobile,
      NetworkType.roaming => roaming,
      NetworkType.none => null,
    };
    return p != null && p.enabled ? p : null;
  }

  /// Photos have no size limit, as in the official app: Telegram keeps them small.
  bool get photos => _current?.photos ?? false;

  /// A video (a GIF, a round video message) within the limit; an unknown size waits.
  bool video(VideoMedia v) {
    final p = _current;
    return p != null &&
        p.videos &&
        v.file.size > 0 &&
        v.file.size <= p.videoMaxBytes;
  }

  /// A document, a song or a voice message within the limit; an unknown size waits.
  bool file(int sizeBytes) {
    final p = _current;
    return p != null && p.files && sizeBytes > 0 && sizeBytes <= p.fileMaxBytes;
  }

  /// Plays muted in its row: it loads by itself and its Autoplay switch is on.
  bool autoplay(VideoMedia v) =>
      video(v) && (v.isAnimation ? autoplayGifs : autoplayVideos);

  /// Too large to load by itself, but its first seconds are loaded ahead.
  bool preload(VideoMedia v) {
    final p = _current;
    return p != null &&
        p.videos &&
        p.preloadLargeVideos &&
        v.file.size > p.videoMaxBytes;
  }

  @override
  bool operator ==(Object other) =>
      other is AutoDownloadPolicy &&
      other.network == network &&
      other.mobile == mobile &&
      other.wifi == wifi &&
      other.roaming == roaming &&
      other.autoplayVideos == autoplayVideos &&
      other.autoplayGifs == autoplayGifs &&
      other.ready == ready;
  @override
  int get hashCode => Object.hash(
    network,
    mobile,
    wifi,
    roaming,
    autoplayVideos,
    autoplayGifs,
    ready,
  );
}

/// Hands the policy to the media in the rows, and follows the settings and the connection
/// as they change (on resume, since a walk out of the house changes both).
class AutoDownloadScope extends StatefulWidget {
  const AutoDownloadScope({
    super.key,
    required this.db,
    required this.child,
    this.watcher = const NetworkWatcher(),
  });
  final AppDatabase db;
  final Widget child;
  final NetworkWatcher watcher;

  /// Pictures only where no scope exists, as before the settings.
  static AutoDownloadPolicy of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_AutoDownloadInherited>()
          ?.policy ??
      const AutoDownloadPolicy.picturesOnly();

  @override
  State<AutoDownloadScope> createState() => _AutoDownloadScopeState();
}

class _AutoDownloadScopeState extends State<AutoDownloadScope>
    with WidgetsBindingObserver {
  final _values = <String, String?>{};
  final _seen = <String>{};
  final _subs = <StreamSubscription<String?>>[];
  NetworkType? _network;

  static const _keys = [
    SettingKeys.downloadMobile,
    SettingKeys.downloadWifi,
    SettingKeys.downloadRoaming,
    SettingKeys.autoplay,
    SettingKeys.autoplayGifs,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    for (final key in _keys) {
      _subs.add(
        widget.db.watchSetting(key).listen((v) {
          if (!mounted) return;
          setState(() {
            _values[key] = v;
            _seen.add(key);
          });
        }),
      );
    }
    unawaited(_readNetwork());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_readNetwork());
  }

  Future<void> _readNetwork() async {
    final type = await widget.watcher.type();
    if (!mounted || type == _network) return;
    debugPrint('media: connection is ${type.name}');
    setState(() => _network = type);
  }

  /// Everything read: the settings and the connection.
  bool get _ready => _network != null && _seen.length == _keys.length;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  DownloadPreset _preset(Connection c) =>
      DownloadPreset.decode(_values[c.settingKey], c.defaults);

  @override
  Widget build(BuildContext context) => _AutoDownloadInherited(
    policy: AutoDownloadPolicy(
      ready: _ready,
      network: _network ?? NetworkType.none,
      mobile: _preset(Connection.mobile),
      wifi: _preset(Connection.wifi),
      roaming: _preset(Connection.roaming),
      autoplayVideos: _values[SettingKeys.autoplay] != 'false',
      autoplayGifs: _values[SettingKeys.autoplayGifs] != 'false',
    ),
    child: widget.child,
  );
}

class _AutoDownloadInherited extends InheritedWidget {
  const _AutoDownloadInherited({required this.policy, required super.child});
  final AutoDownloadPolicy policy;

  @override
  bool updateShouldNotify(_AutoDownloadInherited old) => old.policy != policy;
}
