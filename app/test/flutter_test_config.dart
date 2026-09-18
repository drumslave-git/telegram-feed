import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// Golden comparison with a tolerance. The golden images are rendered on Linux, the
/// platform CI runs on (`tool/update_goldens.sh` regenerates them in Docker). Other
/// platforms rasterise text and shadows a little differently (Windows: up to 0.9% of the
/// pixels), so there the check is looser and only catches layout regressions.
class _TolerantComparator extends LocalFileComparator {
  _TolerantComparator(super.testFile);

  /// Percentage of differing pixels tolerated.
  static final double maxDiffPercent = Platform.isLinux ? 0.3 : 1.5;

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
  // Its default 500 ms debounce leaves a timer pending at the end of widget tests.
  VisibilityDetectorController.instance.updateInterval = Duration.zero;
  await testMain();
}
