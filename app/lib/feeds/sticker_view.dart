import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'media_view.dart';
import 'players.dart';

/// A sticker in a post, drawn the way the official app draws one: no bubble decoration of
/// its own, about two thumbs wide, its proportions kept. A `webp` sticker is a picture, a
/// `tgs` one is Lottie inside gzip, a `webm` one is a small silent video that loops. The
/// still thumbnail stands in until the file is downloaded.
class StickerView extends StatelessWidget {
  const StickerView({
    super.key,
    required this.sticker,
    required this.gateway,
    this.side = 180,
  });
  final StickerMedia sticker;
  final TelegramGateway gateway;

  /// Longest side of the sticker as it is drawn.
  final double side;

  Size get _size {
    final w = sticker.width, h = sticker.height;
    if (w <= 0 || h <= 0) return Size(side, side);
    return w >= h ? Size(side, side * h / w) : Size(side * w / h, side);
  }

  @override
  Widget build(BuildContext context) {
    final size = _size;
    final thumbnail = sticker.thumbnail;
    final placeholder = thumbnail == null
        ? const SizedBox.shrink()
        : PhotoView(file: thumbnail, gateway: gateway, radius: 0, fill: true);
    return SizedBox(
      width: size.width,
      height: size.height,
      child: Downloaded(
        file: sticker.file,
        gateway: gateway,
        placeholder: placeholder,
        builder: (context, path) => switch (sticker.format) {
          // A custom emoji is a 512 px sticker drawn a line high: decoded at that height.
          StickerFormat.webp => Image(
            image: fileImageFor(
              path,
              width: sticker.file.width,
              height: sticker.file.height,
              box: size,
              pixelRatio: MediaQuery.devicePixelRatioOf(context),
              cover: false,
            ),
            width: size.width,
            height: size.height,
            fit: BoxFit.contain,
            gaplessPlayback: true,
          ),
          // Telegram's animated stickers are gzipped Lottie: the decoder unpacks them.
          StickerFormat.tgs => Lottie.file(
            File(path),
            width: size.width,
            height: size.height,
            fit: BoxFit.contain,
            decoder: LottieComposition.decodeGZip,
            errorBuilder: (context, error, stack) => placeholder,
          ),
          StickerFormat.webm => LoopingVideo(
            path: path,
            width: size.width,
            height: size.height,
          ),
        },
      ),
    );
  }
}
