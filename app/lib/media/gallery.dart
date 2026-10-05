import 'package:flutter/services.dart';

/// Copies a file the app has in Telegram's cache to where the phone keeps such files: a
/// picture or a video into the gallery (`Pictures/TG Feed` or `Movies/TG Feed`), a document
/// into `Download/TG Feed`, music into `Music/TG Feed`, which is what the official app's
/// "Save to gallery", "Save to downloads" and "Save to music" do. MediaStore needs no
/// permission for a file the app writes itself.
/// Where a file of a post is copied to on the phone.
enum SaveTo {
  /// `Pictures/TG Feed` or `Movies/TG Feed`, by the kind of file.
  gallery,

  /// `Download/TG Feed`.
  downloads,

  /// `Music/TG Feed`.
  music,
}

class Gallery {
  const Gallery({MethodChannel? channel}) : _channel = channel ?? _default;
  static const _default = MethodChannel('tf/gallery');
  final MethodChannel _channel;

  /// Answers with the uri the gallery gave the copy, or throws [PlatformException].
  Future<String?> save({
    required String path,
    required String name,
    required String mimeType,
    SaveTo to = SaveTo.gallery,
  }) => _channel.invokeMethod<String>('save', {
    'path': path,
    'name': name,
    'mimeType': mimeType,
    'to': to.name,
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
