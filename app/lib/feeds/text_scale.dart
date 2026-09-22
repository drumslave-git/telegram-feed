import 'dart:async';

import 'package:app_db/app_db.dart';
import 'package:flutter/material.dart';

/// How large the text of posts and comments is drawn, from the reader's own setting
/// ([SettingKeys.postTextScale]). It sits above the navigator, so every screen with posts
/// on it sees the same factor, and only the posts follow it: the rest of the app keeps the
/// system's own text size.
class PostTextScale extends StatefulWidget {
  const PostTextScale({super.key, required this.db, required this.child});
  final AppDatabase db;
  final Widget child;

  /// Smallest and largest the slider offers.
  static const min = 0.8;
  static const max = 1.6;

  /// 1.0 where no scope exists (widget tests of single cards).
  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ScaleInherited>()?.factor ??
      1.0;

  /// Wraps [child] so every bit of text in it follows the reader's factor.
  static Widget wrap(BuildContext context, Widget child) {
    final factor = of(context);
    if (factor == 1.0) return child;
    final media = MediaQuery.of(context);
    // On top of the phone's own text size, never instead of it: a reader who needs large
    // text keeps it, and the setting makes posts larger or smaller than the rest.
    return MediaQuery(
      data: media.copyWith(textScaler: _ScaledBy(media.textScaler, factor)),
      child: child,
    );
  }

  static double parse(String? value) =>
      (double.tryParse(value ?? '') ?? 1.0).clamp(min, max);

  @override
  State<PostTextScale> createState() => _PostTextScaleState();
}

class _PostTextScaleState extends State<PostTextScale> {
  double _factor = 1.0;
  StreamSubscription<String?>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.db.watchSetting(SettingKeys.postTextScale).listen((v) {
      final factor = PostTextScale.parse(v);
      if (mounted && factor != _factor) setState(() => _factor = factor);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _ScaleInherited(factor: _factor, child: widget.child);
}

class _ScaleInherited extends InheritedWidget {
  const _ScaleInherited({required this.factor, required super.child});
  final double factor;

  @override
  bool updateShouldNotify(_ScaleInherited old) => old.factor != factor;
}

/// The phone's text scaling times the reader's post factor.
class _ScaledBy extends TextScaler {
  const _ScaledBy(this.base, this.factor);
  final TextScaler base;
  final double factor;

  @override
  double scale(double fontSize) => base.scale(fontSize) * factor;

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => base.textScaleFactor * factor;

  @override
  bool operator ==(Object other) =>
      other is _ScaledBy && other.base == base && other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);
}
