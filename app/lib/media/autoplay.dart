import 'dart:async';

import 'package:app_db/app_db.dart';
import 'package:flutter/widgets.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

/// Which videos start by themselves, muted, when they scroll into view (Settings > Media).
final class AutoplayPolicy {
  const AutoplayPolicy({
    this.enabled = true,
    this.maxSeconds = defaultMaxSeconds,
    this.maxMegabytes = defaultMaxMegabytes,
  });
  const AutoplayPolicy.off() : this(enabled: false);

  static const defaultMaxSeconds = 60;
  static const defaultMaxMegabytes = 20;

  final bool enabled;
  final int maxSeconds;
  final int maxMegabytes;

  /// GIF-like animations have no length limit of their own; size still counts.
  bool allows(VideoMedia video) =>
      enabled &&
      video.file.size > 0 &&
      video.file.size <= maxMegabytes * 1024 * 1024 &&
      (video.isAnimation || video.durationSeconds <= maxSeconds);

  factory AutoplayPolicy.fromSettings({
    String? enabled,
    String? maxSeconds,
    String? maxMegabytes,
  }) => AutoplayPolicy(
    enabled: enabled != 'false',
    maxSeconds: int.tryParse(maxSeconds ?? '') ?? defaultMaxSeconds,
    maxMegabytes: int.tryParse(maxMegabytes ?? '') ?? defaultMaxMegabytes,
  );

  @override
  bool operator ==(Object other) =>
      other is AutoplayPolicy &&
      other.enabled == enabled &&
      other.maxSeconds == maxSeconds &&
      other.maxMegabytes == maxMegabytes;
  @override
  int get hashCode => Object.hash(enabled, maxSeconds, maxMegabytes);
}

/// Provides the [AutoplayPolicy] from the settings table to the media widgets below.
class AutoplayScope extends StatefulWidget {
  const AutoplayScope({super.key, required this.db, required this.child});
  final AppDatabase db;
  final Widget child;

  /// Off where no scope exists (widget tests of single media views).
  static AutoplayPolicy of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_AutoplayInherited>()
          ?.policy ??
      const AutoplayPolicy.off();

  @override
  State<AutoplayScope> createState() => _AutoplayScopeState();
}

class _AutoplayScopeState extends State<AutoplayScope> {
  final _values = <String, String?>{};
  final _subs = <StreamSubscription<String?>>[];

  @override
  void initState() {
    super.initState();
    for (final key in const [
      SettingKeys.autoplay,
      SettingKeys.autoplayMaxSeconds,
      SettingKeys.autoplayMaxMegabytes,
    ]) {
      _subs.add(
        widget.db.watchSetting(key).listen((v) {
          if (mounted) setState(() => _values[key] = v);
        }),
      );
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _AutoplayInherited(
    policy: AutoplayPolicy.fromSettings(
      enabled: _values[SettingKeys.autoplay],
      maxSeconds: _values[SettingKeys.autoplayMaxSeconds],
      maxMegabytes: _values[SettingKeys.autoplayMaxMegabytes],
    ),
    child: widget.child,
  );
}

class _AutoplayInherited extends InheritedWidget {
  const _AutoplayInherited({required this.policy, required super.child});
  final AutoplayPolicy policy;

  @override
  bool updateShouldNotify(_AutoplayInherited old) => old.policy != policy;
}
