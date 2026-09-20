import 'dart:async';

import 'package:app_db/app_db.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// What the phone is connected to. Metered Wi-Fi counts as [mobile]: the reader who limits
/// mobile data means the bill, not the radio.
enum NetworkType { wifi, mobile, none }

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
        _ => NetworkType.none,
      };
    } on PlatformException {
      // Nothing to go on: behave as the most careful case does.
      return NetworkType.mobile;
    } on MissingPluginException {
      return NetworkType.wifi; // tests and desktop
    }
  }
}

/// Whether a picture may load by itself, from the reader's settings and the connection:
/// one switch and one size limit per kind of connection, as the official app has.
class AutoDownloadPolicy {
  const AutoDownloadPolicy({
    required this.network,
    this.onWifi = true,
    this.onMobile = true,
    this.wifiMaxMb = 20,
    this.mobileMaxMb = 5,
    this.ready = true,
  });

  /// Everything loads by itself: what a screen without a scope does (widget tests).
  const AutoDownloadPolicy.always() : this(network: NetworkType.wifi);

  /// Nothing is known yet: the settings have not been read. A row waits rather than
  /// download something the reader may have asked it not to.
  const AutoDownloadPolicy.unknown()
    : this(network: NetworkType.none, ready: false);
  final NetworkType network;
  final bool onWifi;
  final bool onMobile;
  final int wifiMaxMb;
  final int mobileMaxMb;

  static const defaultWifiMaxMb = 20;
  static const defaultMobileMaxMb = 5;

  /// False until the settings and the connection are known.
  final bool ready;

  bool allows(int sizeBytes) {
    if (!ready) return false;
    final (allowed, maxMb) = switch (network) {
      NetworkType.wifi => (onWifi, wifiMaxMb),
      NetworkType.mobile => (onMobile, mobileMaxMb),
      // Nothing to download over.
      NetworkType.none => (false, 0),
    };
    if (!allowed) return false;
    // A file of unknown size (TDLib has not said yet) is let through.
    if (sizeBytes <= 0) return true;
    return sizeBytes <= maxMb * 1024 * 1024;
  }
}

/// Hands the policy to the pictures in the rows, and follows the settings and the
/// connection as they change (on resume, since a walk out of the house changes both).
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

  /// Everything loads where no scope exists, as it did before the setting.
  static AutoDownloadPolicy of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_AutoDownloadInherited>()
          ?.policy ??
      const AutoDownloadPolicy.always();

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
    SettingKeys.autoDownloadWifi,
    SettingKeys.autoDownloadMobile,
    SettingKeys.autoDownloadWifiMaxMb,
    SettingKeys.autoDownloadMobileMaxMb,
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
    if (mounted && type != _network) setState(() => _network = type);
  }

  /// Everything read: the four settings and the connection.
  bool get _ready => _network != null && _seen.length == _keys.length;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  bool _flag(String key) => _values[key] != 'false';

  int _limit(String key, int fallback) =>
      int.tryParse(_values[key] ?? '') ?? fallback;

  @override
  Widget build(BuildContext context) => _AutoDownloadInherited(
    policy: AutoDownloadPolicy(
      ready: _ready,
      network: _network ?? NetworkType.none,
      onWifi: _flag(SettingKeys.autoDownloadWifi),
      onMobile: _flag(SettingKeys.autoDownloadMobile),
      wifiMaxMb: _limit(
        SettingKeys.autoDownloadWifiMaxMb,
        AutoDownloadPolicy.defaultWifiMaxMb,
      ),
      mobileMaxMb: _limit(
        SettingKeys.autoDownloadMobileMaxMb,
        AutoDownloadPolicy.defaultMobileMaxMb,
      ),
    ),
    child: widget.child,
  );
}

class _AutoDownloadInherited extends InheritedWidget {
  const _AutoDownloadInherited({required this.policy, required super.child});
  final AutoDownloadPolicy policy;

  @override
  bool updateShouldNotify(_AutoDownloadInherited old) =>
      old.policy.network != policy.network ||
      old.policy.onWifi != policy.onWifi ||
      old.policy.onMobile != policy.onMobile ||
      old.policy.wifiMaxMb != policy.wifiMaxMb ||
      old.policy.mobileMaxMb != policy.mobileMaxMb ||
      old.policy.ready != policy.ready;
}
