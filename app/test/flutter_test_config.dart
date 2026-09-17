import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Golden comparison with a small tolerance: goldens are generated on Windows and checked on
/// Linux CI, where anti-aliasing can differ by a few pixels.
class _TolerantComparator extends LocalFileComparator {
  _TolerantComparator(super.testFile);

  /// Percentage of differing pixels tolerated.
  static const maxDiffPercent = 0.3;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed) return true;
    final percent = result.diffPercent * 100;
    if (percent <= maxDiffPercent) return true;
    final error = await generateFailureOutput(result, golden, basedir);
    throw FlutterError(
      '$error\n(${percent.toStringAsFixed(3)}% differs, tolerance $maxDiffPercent%)',
    );
  }
}

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final current = goldenFileComparator;
  if (current is LocalFileComparator) {
    goldenFileComparator = _TolerantComparator(
      Uri.parse('${current.basedir}dummy_test.dart'),
    );
  }
  await testMain();
}
