import 'dart:math' as math;
import 'dart:ui' show Rect, Size;

/// Where the pictures of an album go: Telegram's grouped layout (the mosaic of the official
/// apps), after `Ui::LayoutMediaGroup` of Telegram Desktop. Two to four pictures have
/// hand-made arrangements chosen by their proportions; five and more (or a very wide one)
/// are split into rows so that the whole comes closest to a 3:4 block.
///
/// [sizes] are the pictures' own sizes (only the ratios count), the result has one rectangle
/// per picture inside a block [maxWidth] wide. Pictures are meant to be cropped into their
/// rectangle (`BoxFit.cover`).
List<Rect> layoutAlbum(
  List<Size> sizes, {
  required double maxWidth,
  double spacing = 2,
}) {
  if (sizes.isEmpty) return const [];
  final ratios = [
    for (final s in sizes)
      s.width > 0 && s.height > 0 ? s.width / s.height : 1.0,
  ];
  final rects = _Layouter(
    ratios,
    maxWidth: maxWidth,
    minWidth: maxWidth * 0.23,
    spacing: spacing,
  ).layout();
  // Some arrangements come out narrower than the block (Telegram shrinks the bubble then);
  // here the bubble keeps its width, so the mosaic is stretched sideways to it. Odd mixes of
  // very tall and very wide pictures can also get taller than one and a half widths; those
  // are squeezed to that. Pictures are cropped into their cells anyway.
  final width = rects.fold(0.0, (w, r) => math.max(w, r.right));
  final height = albumHeight(rects);
  if (width <= 0 || height <= 0) return rects;
  final kx = maxWidth / width;
  final ky = math.min(1.0, maxWidth * 1.5 / height);
  if ((kx - 1).abs() < 0.0001 && ky == 1.0) return rects;
  return [
    for (final r in rects)
      Rect.fromLTRB(r.left * kx, r.top * ky, r.right * kx, r.bottom * ky),
  ];
}

/// Height of the block [rects] fill.
double albumHeight(List<Rect> rects) =>
    rects.fold(0, (h, r) => math.max(h, r.bottom));

final class _Layouter {
  _Layouter(
    this.ratios, {
    required this.maxWidth,
    required this.minWidth,
    required this.spacing,
  }) : maxHeight = maxWidth,
       proportions = [
         for (final r in ratios)
           r > 1.2
               ? 'w'
               : r < 0.8
               ? 'n'
               : 'q',
       ].join(),
       averageRatio = ratios.reduce((a, b) => a + b) / ratios.length;

  final List<double> ratios;
  final double maxWidth;
  final double maxHeight;
  final double minWidth;
  final double spacing;

  /// One letter per picture: `w`ide, `n`arrow or s`q`uare-ish.
  final String proportions;
  final double averageRatio;

  int get count => ratios.length;
  static double _round(double v) => v.roundToDouble();

  List<Rect> layout() {
    if (count == 1) {
      final height = _round(
        (maxWidth / ratios[0]).clamp(minWidth, maxHeight * 4 / 3),
      );
      return [Rect.fromLTWH(0, 0, maxWidth, height)];
    }
    if (count >= 5 || ratios.any((r) => r > 2)) return _complex();
    return switch (count) {
      2 => _two(),
      3 => _three(),
      _ => _four(),
    };
  }

  List<Rect> _two() {
    final s = spacing;
    if (proportions == 'ww' &&
        averageRatio > 1.4 * (maxWidth / maxHeight) &&
        ratios[1] - ratios[0] < 0.2) {
      // One above the other.
      final height = _round(
        math.min(
          maxWidth / ratios[0],
          math.min(maxWidth / ratios[1], (maxHeight - s) / 2),
        ),
      );
      return [
        Rect.fromLTWH(0, 0, maxWidth, height),
        Rect.fromLTWH(0, height + s, maxWidth, height),
      ];
    }
    if (proportions == 'ww' || proportions == 'qq') {
      // Side by side, equal widths.
      final width = (maxWidth - s) / 2;
      final height = _round(
        math.min(width / ratios[0], math.min(width / ratios[1], maxHeight)),
      );
      return [
        Rect.fromLTWH(0, 0, width, height),
        Rect.fromLTWH(width + s, 0, maxWidth - width - s, height),
      ];
    }
    // Side by side, widths by proportion.
    final minimal = _round(minWidth * 1.5);
    final second = math.min(
      _round(
        math.max(
          0.4 * (maxWidth - s),
          (maxWidth - s) / ratios[0] / (1 / ratios[0] + 1 / ratios[1]),
        ),
      ),
      maxWidth - s - minimal,
    );
    final first = maxWidth - second - s;
    final height = math.min(
      maxHeight,
      _round(math.min(first / ratios[0], second / ratios[1])),
    );
    return [
      Rect.fromLTWH(0, 0, first, height),
      Rect.fromLTWH(first + s, 0, second, height),
    ];
  }

  List<Rect> _three() {
    final s = spacing;
    if (proportions[0] == 'n') {
      // A tall one on the left, two stacked on the right.
      final firstHeight = maxHeight;
      final thirdHeight = _round(
        math.min(
          (maxHeight - s) / 2,
          ratios[1] * (maxWidth - s) / (ratios[2] + ratios[1]),
        ),
      );
      final secondHeight = firstHeight - thirdHeight - s;
      final rightWidth = math.max(
        minWidth,
        _round(
          math.min(
            (maxWidth - s) / 2,
            math.min(thirdHeight * ratios[2], secondHeight * ratios[1]),
          ),
        ),
      );
      final leftWidth = math.min(
        _round(firstHeight * ratios[0]),
        maxWidth - s - rightWidth,
      );
      return [
        Rect.fromLTWH(0, 0, leftWidth, firstHeight),
        Rect.fromLTWH(leftWidth + s, 0, rightWidth, secondHeight),
        Rect.fromLTWH(leftWidth + s, secondHeight + s, rightWidth, thirdHeight),
      ];
    }
    // One across the top, two below.
    final firstHeight = _round(
      math.min(maxWidth / ratios[0], (maxHeight - s) * 0.66),
    );
    final secondWidth = (maxWidth - s) / 2;
    final secondHeight = math.min(
      maxHeight - firstHeight - s,
      _round(math.min(secondWidth / ratios[1], secondWidth / ratios[2])),
    );
    final thirdWidth = maxWidth - secondWidth - s;
    return [
      Rect.fromLTWH(0, 0, maxWidth, firstHeight),
      Rect.fromLTWH(0, firstHeight + s, secondWidth, secondHeight),
      Rect.fromLTWH(secondWidth + s, firstHeight + s, thirdWidth, secondHeight),
    ];
  }

  List<Rect> _four() {
    final s = spacing;
    if (proportions[0] == 'w') {
      // One across the top, three below.
      final h0 = _round(math.min(maxWidth / ratios[0], (maxHeight - s) * 0.66));
      final h = _round(
        (maxWidth - 2 * s) / (ratios[1] + ratios[2] + ratios[3]),
      );
      final w0 = math.max(
        minWidth,
        _round(math.min((maxWidth - 2 * s) * 0.4, h * ratios[1])),
      );
      final w2 = _round(
        math.max(math.max(minWidth, (maxWidth - 2 * s) * 0.33), h * ratios[3]),
      );
      final w1 = maxWidth - w0 - w2 - 2 * s;
      final h1 = math.min(maxHeight - h0 - s, h);
      return [
        Rect.fromLTWH(0, 0, maxWidth, h0),
        Rect.fromLTWH(0, h0 + s, w0, h1),
        Rect.fromLTWH(w0 + s, h0 + s, w1, h1),
        Rect.fromLTWH(w0 + s + w1 + s, h0 + s, w2, h1),
      ];
    }
    // One on the left, three stacked on the right.
    final h = maxHeight;
    final w0 = _round(math.min(h * ratios[0], (maxWidth - s) * 0.6));
    final w = _round(
      (maxHeight - 2 * s) / (1 / ratios[1] + 1 / ratios[2] + 1 / ratios[3]),
    );
    final h0 = _round(w / ratios[1]);
    final h1 = _round(w / ratios[2]);
    final h2 = h - h0 - h1 - 2 * s;
    final w1 = math.max(minWidth, math.min(maxWidth - w0 - s, w));
    return [
      Rect.fromLTWH(0, 0, w0, h),
      Rect.fromLTWH(w0 + s, 0, w1, h0),
      Rect.fromLTWH(w0 + s, h0 + s, w1, h1),
      Rect.fromLTWH(w0 + s, h0 + h1 + 2 * s, w1, h2),
    ];
  }

  /// Rows of one to four pictures; of all splits the one whose height comes closest to a 3:4
  /// block wins. Rows that get too flat, or that have more pictures than the row below, count
  /// as worse.
  List<Rect> _complex() {
    final s = spacing;
    final cropped = [
      for (final r in ratios)
        averageRatio > 1.1 ? r.clamp(1.0, 2.75) : r.clamp(0.6667, 1.0),
    ];
    final targetHeight = maxWidth * 4 / 3;

    double rowHeight(int offset, int n) {
      var sum = 0.0;
      for (var i = offset; i < offset + n; i++) {
        sum += cropped[i];
      }
      return (maxWidth - (n - 1) * s) / sum;
    }

    final attempts = <(List<int>, List<double>)>[];
    void attempt(List<int> counts) {
      final heights = <double>[];
      var offset = 0;
      for (final n in counts) {
        heights.add(rowHeight(offset, n));
        offset += n;
      }
      attempts.add((counts, heights));
    }

    for (var first = 1; first != count; first++) {
      final second = count - first;
      if (first > 3 || second > 3) continue;
      attempt([first, second]);
    }
    for (var first = 1; first != count - 1; first++) {
      for (var second = 1; second != count - first; second++) {
        final third = count - first - second;
        if (first > 3 || second > (averageRatio < 0.85 ? 4 : 3) || third > 3) {
          continue;
        }
        attempt([first, second, third]);
      }
    }
    for (var first = 1; first != count - 1; first++) {
      for (var second = 1; second != count - first; second++) {
        for (var third = 1; third != count - first - second; third++) {
          final fourth = count - first - second - third;
          if (first > 3 || second > 3 || third > 3 || fourth > 3) continue;
          attempt([first, second, third, fourth]);
        }
      }
    }
    // Two very wide pictures: no split above fits, one row each.
    if (attempts.isEmpty) attempt(List.filled(count, 1));

    var best = attempts.first;
    var bestDiff = double.infinity;
    for (final a in attempts) {
      final (counts, heights) = a;
      final total = heights.reduce((x, y) => x + y) + s * (counts.length - 1);
      final flat = heights.reduce(math.min) < minWidth ? 1.5 : 1.0;
      var topHeavy = 1.0;
      for (var line = 1; line < counts.length; line++) {
        if (counts[line - 1] > counts[line]) topHeavy = 1.5;
      }
      final diff = (total - targetHeight).abs() * flat * topHeavy;
      if (diff < bestDiff) {
        best = a;
        bestDiff = diff;
      }
    }

    final (counts, heights) = best;
    final out = <Rect>[];
    var index = 0;
    var y = 0.0;
    for (var row = 0; row < counts.length; row++) {
      final height = _round(heights[row]);
      var x = 0.0;
      for (var col = 0; col < counts[row]; col++) {
        final width = col == counts[row] - 1
            ? maxWidth - x
            : _round(cropped[index] * heights[row]);
        out.add(Rect.fromLTWH(x, y, width, height));
        x += width + s;
        index++;
      }
      y += height + s;
    }
    return out;
  }
}
