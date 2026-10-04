import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

/// The pictures of a channel's notification: the channel's photo, cut round, and the
/// picture of a post as a uri Android's notification shade may read
/// (`NotificationPictures.kt`). Both are downloaded when they are not on the phone yet;
/// what does not come within [patience] is left out, so a slow network does not hold a
/// notification back.
class NotificationPictures {
  NotificationPictures({
    required this.channels,
    required this.download,
    MethodChannel? channel,
    this.patience = const Duration(seconds: 2),
    DateTime Function()? now,
  }) : _channel = channel ?? const MethodChannel('tf/notificationPictures'),
       _now = now ?? DateTime.now;

  /// The account's channels, which carry their photos.
  final Future<List<Channel>> Function() channels;
  final Future<FileRef> Function(FileRef) download;
  final Duration patience;
  final MethodChannel _channel;
  final DateTime Function() _now;

  /// How long the channels' photos are taken as known: a channel that changes its
  /// photo shows the new one after that.
  static const photosKept = Duration(minutes: 10);

  /// The narrowest size of a photo that still fills the notification's width.
  static const pictureWidth = 600;

  final _photos = <int, FileRef?>{};
  DateTime? _photosAt;

  /// The round photo of the post's channel (a file) and the post's picture (a content
  /// uri); null for each that there is none of.
  Future<({String? avatar, String? picture})> of(Post post) async {
    final found = await Future.wait([
      _within(_avatar(post.chatId)),
      _within(_picture(post)),
    ]);
    return (avatar: found[0], picture: found[1]);
  }

  Future<String?> _within(Future<String?> work) =>
      work.timeout(patience, onTimeout: () => null).catchError((Object e) {
        debugPrint('notification picture: $e');
        return null;
      });

  Future<String?> _avatar(int chatId) async {
    final at = _photosAt;
    if (at == null ||
        !_photos.containsKey(chatId) ||
        _now().difference(at) > photosKept) {
      _photosAt = _now();
      for (final c in await channels()) {
        _photos[c.chatId] = c.photo;
      }
    }
    final photo = _photos[chatId];
    if (photo == null) return null;
    final file = photo.isDownloaded ? photo : await download(photo);
    return _channel.invokeMethod<String>('avatar', file.localPath);
  }

  Future<String?> _picture(Post post) async {
    final media = post.media;
    // A picture under a spoiler stays under it.
    if (media is! PhotoMedia ||
        media.sizes.isEmpty ||
        media.cover != MediaCover.none) {
      return null;
    }
    final size = media.sizes.firstWhere(
      (f) => f.width >= pictureWidth,
      orElse: () => media.largest,
    );
    final file = size.isDownloaded ? size : await download(size);
    return _channel.invokeMethod<String>('share', file.localPath);
  }
}
