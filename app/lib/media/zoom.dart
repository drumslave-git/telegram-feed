import 'package:flutter/widgets.dart';

/// Zoom state of an [InteractiveViewer], shared by the photo and the video pages of the viewer.
extension Zoom on TransformationController {
  bool get isZoomed => value.getMaxScaleOnAxis() > 1.01;

  /// Double tap: zooms to [scale] with the tapped point [at] staying under the finger, or
  /// back to the fitted picture.
  void toggleZoom(Offset at, {double scale = 2.5}) {
    if (isZoomed) {
      value = Matrix4.identity();
      return;
    }
    value = Matrix4.identity()
      ..translateByDouble(-at.dx * (scale - 1), -at.dy * (scale - 1), 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }
}
