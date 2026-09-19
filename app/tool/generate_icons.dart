// Renders the launcher icon PNGs (for launchers without adaptive icons, Android 7) and a
// 512 px preview. The adaptive icon itself is vector XML in res/drawable with the same
// geometry: three channels on the left merging into one feed.
//
//   cd app && flutter test tool/generate_icons.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// The glyph on the 108 x 108 adaptive-icon grid (safe zone: the 66 px circle in the middle).
void paintGlyph(ui.Canvas canvas, ui.Color color) {
  final stroke = ui.Paint()
    ..color = color
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = 7
    ..strokeCap = ui.StrokeCap.round
    ..strokeJoin = ui.StrokeJoin.round;
  final fill = ui.Paint()..color = color;
  final streams = ui.Path()
    ..moveTo(31, 35)
    ..cubicTo(50, 35, 48, 54, 64, 54)
    ..moveTo(31, 54)
    ..lineTo(78, 54)
    ..moveTo(31, 73)
    ..cubicTo(50, 73, 48, 54, 64, 54);
  final arrow = ui.Path()
    ..moveTo(70, 44)
    ..lineTo(80, 54)
    ..lineTo(70, 64);
  canvas
    ..drawPath(streams, stroke)
    ..drawPath(arrow, stroke);
  for (final y in const [35.0, 54.0, 73.0]) {
    canvas.drawCircle(ui.Offset(31, y), 5.5, fill);
  }
}

const _top = ui.Color(0xFF2F6FE4);
const _bottom = ui.Color(0xFF17B3C4);

/// Legacy icon: the glyph on a gradient squircle, as launchers without masks show it.
Future<ui.Image> renderLegacy(int size) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final s = size / 108;
  canvas.scale(s);
  // The adaptive grid's visible part is the middle 72 px; legacy icons fill their square.
  canvas.translate(54, 54);
  canvas.scale(108 / 76);
  canvas.translate(-54, -54);
  final box = ui.RRect.fromRectAndRadius(
    const ui.Rect.fromLTWH(18, 18, 72, 72),
    const ui.Radius.circular(20),
  );
  canvas.drawRRect(
    box,
    ui.Paint()
      ..shader = ui.Gradient.linear(
        const ui.Offset(18, 18),
        const ui.Offset(90, 90),
        const [_top, _bottom],
      ),
  );
  canvas.save();
  canvas.translate(54, 54);
  canvas.scale(0.8);
  canvas.translate(-55, -54);
  paintGlyph(canvas, const ui.Color(0xFFFFFFFF));
  canvas.restore();
  return recorder.endRecording().toImage(size, size);
}

void main() {
  testWidgets('write launcher PNGs', (tester) async {
    await tester.runAsync(() async {
      const res = 'android/app/src/main/res';
      const sizes = {
        'mipmap-mdpi': 48,
        'mipmap-hdpi': 72,
        'mipmap-xhdpi': 96,
        'mipmap-xxhdpi': 144,
        'mipmap-xxxhdpi': 192,
      };
      Future<void> write(String path, int size) async {
        final image = await renderLegacy(size);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        File(path)
          ..createSync(recursive: true)
          ..writeAsBytesSync(png!.buffer.asUint8List());
      }

      for (final e in sizes.entries) {
        await write('$res/${e.key}/ic_launcher.png', e.value);
      }
      await write('../docs/icon.png', 512);
    });
  });
}
