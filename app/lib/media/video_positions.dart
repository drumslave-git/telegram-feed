import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

/// Where each video was left in the viewer, as the official app remembers it: a video of
/// ten seconds or more reopens at that place while the app runs, and one of five minutes
/// or more also after the app was closed. A place at the very start or the very end is
/// no place: the video starts over.
abstract final class VideoPositions {
  /// Shorter videos always start over.
  static const minDuration = Duration(seconds: 10);

  /// From this length on the place is written to [attach]'s file.
  static const keptDuration = Duration(minutes: 5);

  /// How many places the file holds; the ones left longest ago go first.
  static const maxKept = 100;

  /// The share of the video that was watched, by file.
  static final _left = <String, double>{};

  /// Those of [_left] that go to the file, oldest first.
  static final _kept = <String, double>{};
  static File? _file;
  static Future<void> _writing = Future<void>.value();

  static String _key(FileRef file) =>
      file.remoteId.isNotEmpty ? file.remoteId : 'id:${file.id}';

  /// Reads the places kept in [file], the account's own, and writes there from now on.
  static Future<void> attach(File file) async {
    // What the account before this one still writes is written first.
    await _writing;
    _file = file;
    _left.clear();
    _kept.clear();
    try {
      if (!file.existsSync()) return;
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return;
      for (final e in raw.entries) {
        final at = e.value;
        if (e.key is String && at is num) {
          _kept[e.key as String] = at.toDouble();
        }
      }
      _left.addAll(_kept);
    } on Object catch (e) {
      // A file that cannot be read costs the places, nothing else.
      debugPrint('media: saved positions unreadable: $e');
    }
  }

  /// Forgets every place, the file included (a logout, and between tests).
  static Future<void> wipe() async {
    _left.clear();
    _kept.clear();
    final file = _file;
    _file = null;
    await _writing;
    if (file != null && file.existsSync()) await file.delete();
  }

  /// Where [file] was left, if it is long enough to have a place and was left between
  /// its start and its end.
  static Duration? of(FileRef file, Duration duration) {
    if (duration < minDuration) return null;
    final at = _left[_key(file)];
    if (at == null || at <= 0 || at >= 0.999) return null;
    return duration * at;
  }

  /// The viewer let go of [file] at [position], or is still playing it there.
  static void leave(FileRef file, Duration position, Duration duration) {
    if (duration < minDuration) return;
    final key = _key(file);
    final at = (position.inMilliseconds / duration.inMilliseconds).clamp(
      0.0,
      1.0,
    );
    _left[key] = at;
    if (duration < keptDuration) return;
    _kept
      ..remove(key)
      ..[key] = at;
    while (_kept.length > maxKept) {
      _kept.remove(_kept.keys.first);
    }
    _write();
  }

  static void _write() {
    final file = _file;
    if (file == null) return;
    final content = jsonEncode(_kept);
    _writing = _writing.then((_) async {
      try {
        await file.writeAsString(content);
      } on FileSystemException catch (e) {
        debugPrint('media: saved positions not written: ${e.message}');
      }
    });
  }
}
