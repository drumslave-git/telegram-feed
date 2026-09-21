import 'package:flutter/services.dart';

/// Copies a picture or a video the app has in Telegram's cache into the phone's own gallery
/// (`Pictures/TG Feed` or `Movies/TG Feed`), which is what the official app's
/// "Save to gallery" does. MediaStore needs no permission for a file the app writes itself
/// on Android 10 and later, the oldest version this app runs on.
class Gallery {
  const Gallery({MethodChannel? channel}) : _channel = channel ?? _default;
  static const _default = MethodChannel('tf/gallery');
  final MethodChannel _channel;

  /// Answers with the uri the gallery gave the copy, or throws [PlatformException].
  Future<String?> save({
    required String path,
    required String name,
    required String mimeType,
  }) => _channel.invokeMethod<String>('save', {
    'path': path,
    'name': name,
    'mimeType': mimeType,
  });

  /// A name for the copy: the app, the day and the file's own id, so two pictures of one
  /// post do not land on each other.
  static String nameFor({
    required int fileId,
    required bool video,
    DateTime? now,
  }) {
    final d = now ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${d.year}${two(d.month)}${two(d.day)}';
    return 'telegram-feed-$stamp-$fileId.${video ? 'mp4' : 'jpg'}';
  }
}
