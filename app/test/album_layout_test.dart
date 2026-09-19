import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/album_layout.dart';

const _wide = Size(1600, 900);
const _tall = Size(900, 1600);
const _square = Size(1000, 1000);

void main() {
  const width = 300.0;

  List<Rect> lay(List<Size> sizes) => layoutAlbum(sizes, maxWidth: width);

  test('every album size fills the width without overlaps or gaps at the edges', () {
    final random = math.Random(7);
    for (var count = 1; count <= 10; count++) {
      for (var round = 0; round < 40; round++) {
        final sizes = [
          for (var i = 0; i < count; i++)
            Size(
              300 + random.nextDouble() * 1700,
              300 + random.nextDouble() * 1700,
            ),
        ];
        final rects = lay(sizes);
        final why = '$count pictures: $sizes -> $rects';
        expect(rects, hasLength(count), reason: why);
        for (final r in rects) {
          expect(r.left, greaterThanOrEqualTo(0), reason: why);
          expect(r.top, greaterThanOrEqualTo(0), reason: why);
          expect(r.right, lessThanOrEqualTo(width + 0.01), reason: why);
          expect(r.width, greaterThan(20), reason: why);
          expect(r.height, greaterThan(20), reason: why);
        }
        for (var a = 0; a < count; a++) {
          for (var b = a + 1; b < count; b++) {
            expect(
              rects[a].deflate(0.5).overlaps(rects[b].deflate(0.5)),
              isFalse,
              reason: why,
            );
          }
        }
        // Something reaches the right edge, and the block is not absurdly tall.
        expect(
          rects.map((r) => r.right).reduce(math.max),
          closeTo(width, 0.01),
        );
        expect(
          albumHeight(rects),
          lessThanOrEqualTo(width * 1.5 + 0.01),
          reason: why,
        );
      }
    }
  });

  test(
    'two landscape pictures sit side by side, two 16:9 or wider ones stack',
    () {
      final pair = lay([const Size(1300, 1000), const Size(1300, 1000)]);
      expect(pair[0].top, pair[1].top);
      expect(pair[0].width, closeTo(pair[1].width, 1));

      for (final size in [_wide, const Size(3000, 1000)]) {
        final stacked = lay([size, size]);
        expect(stacked[1].top, greaterThan(stacked[0].bottom));
        expect(stacked[0].width, width);
      }
    },
  );

  test(
    'three: a tall first picture takes the left side, a wide one the top',
    () {
      final left = lay([_tall, _square, _square]);
      expect(left[0].height, albumHeight(left));
      expect(left[1].left, greaterThan(left[0].right));
      expect(left[2].top, greaterThan(left[1].bottom));

      final top = lay([_wide, _square, _square]);
      expect(top[0].width, width);
      expect(top[1].top, greaterThan(top[0].bottom));
      expect(top[1].top, top[2].top);
    },
  );

  test('four: wide first picture on top with three below', () {
    final rects = lay([_wide, _square, _square, _square]);
    expect(rects[0].width, width);
    expect({rects[1].top, rects[2].top, rects[3].top}, hasLength(1));
  });

  test('ten pictures come in rows of at most three', () {
    final rects = lay(List.filled(10, _square));
    final rows = <double, int>{};
    for (final r in rects) {
      rows[r.top] = (rows[r.top] ?? 0) + 1;
    }
    expect(rows.values.every((n) => n <= 3), isTrue);
    expect(rows.length, 4);
  });

  test('a picture without a known size counts as square', () {
    expect(lay([Size.zero, Size.zero]), hasLength(2));
  });
}
