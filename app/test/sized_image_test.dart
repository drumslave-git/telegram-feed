import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/media_view.dart';

void main() {
  int? decodedWidth(ImageProvider image) =>
      image is ResizeImage ? image.width : null;

  test('a picture filling a box decodes at the box, cropped side first', () {
    // 1280 x 960 in a 100 x 200 cell at 2x: the height runs out first (400 px of 960).
    final cell = fileImageFor(
      '/p.jpg',
      width: 1280,
      height: 960,
      box: const Size(100, 200),
      pixelRatio: 2,
    );
    expect(decodedWidth(cell), (1280 * 400 / 960).ceil());
  });

  test('a picture fitted into a box decodes at its longer side', () {
    final emoji = fileImageFor(
      '/s.webp',
      width: 512,
      height: 512,
      box: const Size(20, 20),
      pixelRatio: 3,
      cover: false,
    );
    expect(decodedWidth(emoji), 60);
  });

  test(
    'a box that needs every pixel, or unknown sizes, decode the file whole',
    () {
      expect(
        fileImageFor(
          '/p.jpg',
          width: 320,
          height: 240,
          box: const Size(400, 300),
          pixelRatio: 2,
        ),
        isA<FileImage>(),
      );
      expect(
        fileImageFor(
          '/p.jpg',
          width: 0,
          height: 0,
          box: const Size(100, 100),
          pixelRatio: 2,
        ),
        isA<FileImage>(),
      );
    },
  );
}
