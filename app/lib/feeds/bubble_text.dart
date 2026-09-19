import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// The text of a chat bubble with its footer (views, time) the way Telegram sets them: the
/// footer sits in the bottom right corner, on the last line of the text when there is room
/// left of it, else on a line of its own.
class BubbleText extends MultiChildRenderObjectWidget {
  BubbleText({
    super.key,
    required Widget text,
    required Widget footer,
    this.gap = 8,
  }) : super(children: [text, footer]);

  /// Least space between the end of the text and the footer.
  final double gap;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBubbleText(gap);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderBubbleText).gap = gap;
  }
}

class _Slot extends ContainerBoxParentData<RenderBox> {}

class _RenderBubbleText extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _Slot>,
        RenderBoxContainerDefaultsMixin<RenderBox, _Slot> {
  _RenderBubbleText(this._gap);

  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  RenderBox get _text => firstChild!;
  RenderBox get _footer => lastChild!;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _Slot) child.parentData = _Slot();
  }

  @override
  double computeMinIntrinsicWidth(double height) => math.max(
    _text.getMinIntrinsicWidth(double.infinity),
    _footer.getMaxIntrinsicWidth(double.infinity),
  );

  /// Everything on one line.
  @override
  double computeMaxIntrinsicWidth(double height) =>
      _text.getMaxIntrinsicWidth(double.infinity) +
      _gap +
      _footer.getMaxIntrinsicWidth(double.infinity);

  @override
  double computeMinIntrinsicHeight(double width) =>
      _text.getMinIntrinsicHeight(width) + _footer.getMinIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      defaultComputeDistanceToFirstActualBaseline(baseline);

  /// Right end of the last line, or null when the footer cannot share that line (the text is
  /// not a paragraph, ends with a line break, or its last line runs right to left).
  double? _lastLineEnd() {
    final text = _text;
    if (text is! RenderParagraph) return null;
    final length = text.text.toPlainText().length;
    if (length == 0) return 0;
    final boxes = text.getBoxesForSelection(
      TextSelection(baseOffset: length - 1, extentOffset: length),
    );
    if (boxes.isEmpty) return null;
    final last = boxes.last;
    if (last.direction == TextDirection.rtl) return null;
    // More than a glyph's height left below the box: it is not on the bottom line, the
    // text ends with an empty one. (Leading alone leaves less than that.)
    if (text.size.height - last.bottom >= last.bottom - last.top) return null;
    return last.right;
  }

  @override
  void performLayout() {
    final loose = constraints.loosen();
    _footer.layout(loose, parentUsesSize: true);
    _text.layout(loose, parentUsesSize: true);
    final footer = _footer.size;
    final text = _text.size;
    final end = _lastLineEnd();
    final double width;
    final double height;
    if (end != null && end + _gap + footer.width <= constraints.maxWidth) {
      width = math.max(text.width, end + _gap + footer.width);
      height = math.max(text.height, footer.height);
    } else {
      width = math.max(text.width, footer.width);
      height = text.height + footer.height;
    }
    size = constraints.constrain(Size(width, height));
    (_text.parentData! as _Slot).offset = Offset.zero;
    (_footer.parentData! as _Slot).offset = Offset(
      size.width - footer.width,
      size.height - footer.height,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
}
