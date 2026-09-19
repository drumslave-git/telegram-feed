import 'package:flutter/material.dart';

/// Lets a full-screen viewer be dragged away, as in the official app: the content follows a
/// vertical drag of one finger while the black behind it fades, and past a distance or with
/// a flick the viewer closes. The route has to be non-opaque for the screen below to show.
class SwipeToClose extends StatefulWidget {
  const SwipeToClose({
    super.key,
    required this.child,
    required this.onClose,
    this.enabled = true,
  });
  final Widget child;
  final VoidCallback onClose;

  /// Off while the picture is zoomed in: a drag pans it then.
  final bool enabled;

  @override
  State<SwipeToClose> createState() => _SwipeToCloseState();
}

class _SwipeToCloseState extends State<SwipeToClose>
    with SingleTickerProviderStateMixin {
  static const _closeDistance = 120.0;
  static const _closeVelocity = 900.0;
  static const _fadeDistance = 400.0;

  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..addListener(() => setState(() => _dy = _from * (1 - _settle.value)));

  double _dy = 0;
  double _from = 0;

  /// Fingers on the screen. A second one means a pinch; the drag recognizer leaves the arena
  /// so that it cannot take the gesture from the zoom.
  int _pointers = 0;

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  void _setPointers(int n) {
    final before = _pointers > 1;
    _pointers = n < 0 ? 0 : n;
    if (before == _pointers > 1) return;
    setState(() {});
    // The recognizer goes away without reporting an end; a drag that had begun swings back.
    if (_pointers > 1 && _dy != 0) {
      _from = _dy;
      _settle.forward(from: 0);
    }
  }

  void _onEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    // A flick counts only in the direction the content was dragged.
    if (_dy.abs() > _closeDistance ||
        (v.abs() > _closeVelocity && v.sign == _dy.sign)) {
      widget.onClose();
      return;
    }
    _from = _dy;
    _settle.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && _pointers <= 1;
    final fade = (1 - _dy.abs() / _fadeDistance).clamp(0.0, 1.0);
    return Listener(
      onPointerDown: (_) => _setPointers(_pointers + 1),
      onPointerUp: (_) => _setPointers(_pointers - 1),
      onPointerCancel: (_) => _setPointers(_pointers - 1),
      child: GestureDetector(
        onVerticalDragStart: active ? (_) => _settle.stop() : null,
        onVerticalDragUpdate: active
            ? (d) => setState(() => _dy += d.delta.dy)
            : null,
        onVerticalDragEnd: active ? _onEnd : null,
        onVerticalDragCancel: active
            ? () {
                _from = _dy;
                _settle.forward(from: 0);
              }
            : null,
        child: ColoredBox(
          color: Colors.black.withValues(alpha: fade),
          child: Transform.translate(
            offset: Offset(0, _dy),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
