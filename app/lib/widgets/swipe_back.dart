import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';

/// Screens slide in from the right and go back with a swipe to the right that may start
/// anywhere on them, as in the official app. The slide is Flutter's Cupertino transition;
/// its own back gesture answers only at the left edge, so the gesture here is made anew
/// over the whole screen.
///
/// Whatever scrolls sideways inside a screen (tabs, a strip of chips, a slider) keeps its
/// own drags: it stands deeper in the tree and takes them first.
class SwipeBackTransitionsBuilder extends PageTransitionsBuilder {
  const SwipeBackTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => CupertinoPageTransition(
    primaryRouteAnimation: animation,
    secondaryRouteAnimation: secondaryAnimation,
    // While the finger moves the screen, it follows the finger and not a curve.
    linearTransition: route.popGestureInProgress,
    child: _BackSwipe<T>(route: route, child: child),
  );
}

class _BackSwipe<T> extends StatefulWidget {
  const _BackSwipe({required this.route, required this.child});
  final PageRoute<T> route;
  final Widget child;

  @override
  State<_BackSwipe<T>> createState() => _BackSwipeState<T>();
}

class _BackSwipeState<T> extends State<_BackSwipe<T>> {
  /// A released screen goes back when it was dragged this far of its width, or flung.
  static const _popAt = 1 / 3;
  static const _flingVelocity = 1.0; // screen widths per second
  static const _settle = Duration(milliseconds: 350);

  late final _recognizer = _RightwardDragRecognizer(debugOwner: this)
    ..onStart = _onStart
    ..onUpdate = _onUpdate
    ..onEnd = _onEnd
    ..onCancel = _onCancel;

  /// The route's own animation, which the finger drives while it drags.
  AnimationController? _dragged;
  NavigatorState? _navigator;

  @override
  void dispose() {
    _recognizer.dispose();
    // A drag that was still running when the screen went must not leave the navigator
    // believing that a gesture is in progress.
    if (_dragged != null) _navigator?.didStopUserGesture();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    if (widget.route.popGestureEnabled) _recognizer.addPointer(event);
  }

  void _onStart(DragStartDetails details) {
    final navigator = widget.route.navigator;
    // ignore: invalid_use_of_protected_member
    final controller = widget.route.controller;
    if (navigator == null || controller == null) return;
    _navigator = navigator;
    _dragged = controller;
    navigator.didStartUserGesture();
  }

  void _onUpdate(DragUpdateDetails details) {
    final width = context.size?.width ?? 0;
    if (_dragged == null || width <= 0) return;
    _dragged!.value -= (details.primaryDelta ?? 0) / width;
  }

  void _onCancel() => _onEnd(DragEndDetails());

  void _onEnd(DragEndDetails details) {
    final controller = _dragged;
    final navigator = _navigator;
    _dragged = null;
    if (controller == null || navigator == null) return;
    final width = context.size?.width ?? 1;
    final velocity = (details.primaryVelocity ?? 0) / width;
    const curve = Curves.fastEaseInToSlowEaseOut;
    final bool stay;
    if (!widget.route.isCurrent) {
      stay = widget.route.isActive;
    } else if (velocity.abs() >= _flingVelocity) {
      stay = velocity <= 0;
    } else {
      stay = controller.value > 1 - _popAt;
    }
    if (stay) {
      controller.animateTo(1, duration: _settle, curve: curve);
    } else {
      if (widget.route.isCurrent) navigator.pop();
      if (controller.isAnimating) {
        controller.animateBack(0, duration: _settle, curve: curve);
      }
    }
    if (controller.isAnimating) {
      late final AnimationStatusListener done;
      done = (status) {
        navigator.didStopUserGesture();
        controller.removeStatusListener(done);
      };
      controller.addStatusListener(done);
    } else {
      navigator.didStopUserGesture();
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _onPointerDown,
    behavior: HitTestBehavior.translucent,
    child: widget.child,
  );
}

/// A drag that counts once the finger has gone 0.4 cm to the right, as the official app
/// starts its own. A drag to the left, and one that goes up or down first, is not its.
class _RightwardDragRecognizer extends HorizontalDragGestureRecognizer {
  _RightwardDragRecognizer({super.debugOwner});

  /// 0.4 cm in logical pixels (160 per inch).
  static const _start = 25.0;

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) => globalDistanceMoved > _start;
}
