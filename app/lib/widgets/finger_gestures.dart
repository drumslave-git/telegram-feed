import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Two fingers are a pinch, one finger is a swipe. On a phone a swipe recognizer claims a
/// finger once it has moved Android's touch slop of a few pixels, sooner than a quick pinch
/// changes the span of the fingers enough for Flutter's scale recognizer to claim them, so
/// without these a pinch on a grid or a picture between swipeable pages turned into a swipe.

/// A pinch that takes the fingers as soon as the second one is down.
class PinchGestureRecognizer extends ScaleGestureRecognizer {
  PinchGestureRecognizer({super.debugOwner});

  final _down = <int>{};

  @override
  void handleEvent(PointerEvent event) {
    super.handleEvent(event);
    if (event is PointerDownEvent) {
      _down.add(event.pointer);
      if (_down.length == 2) resolve(GestureDisposition.accepted);
    }
  }

  @override
  void stopTrackingPointer(int pointer) {
    _down.remove(pointer);
    super.stopTrackingPointer(pointer);
  }
}

/// A drag that leaves the gesture to others the moment a second finger is down, so that the
/// pinch under it gets both fingers. A drag that was already under way goes on with the first.
mixin OneFingerDrag on OneSequenceGestureRecognizer {
  final _down = <int>{};

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _down.add(event.pointer);
    if (_down.length > 1) resolve(GestureDisposition.rejected);
  }

  @override
  void stopTrackingPointer(int pointer) {
    _down.remove(pointer);
    super.stopTrackingPointer(pointer);
  }
}

class OneFingerHorizontalDrag extends HorizontalDragGestureRecognizer
    with OneFingerDrag {
  OneFingerHorizontalDrag({super.debugOwner});
}

class OneFingerVerticalDrag extends VerticalDragGestureRecognizer
    with OneFingerDrag {
  OneFingerVerticalDrag({super.debugOwner});
}

/// Pages that turn with one finger only: a [PageView] whose own dragging is off, wrapped in a
/// [OneFingerHorizontalDrag] that moves its [controller] the way a [Scrollable] does. The page
/// view in [child] takes [physics], which keep its snapping and its edges.
class OneFingerPages extends StatefulWidget {
  const OneFingerPages({
    super.key,
    required this.controller,
    required this.child,
    this.enabled = true,
  });

  final PageController controller;

  /// Off: the pages do not turn, as while a picture is zoomed in.
  final bool enabled;

  final Widget child;

  /// What the page view scrolls with: no dragging of its own, the platform's edges.
  static const physics = NeverScrollableScrollPhysics(
    parent: ClampingScrollPhysics(),
  );

  @override
  State<OneFingerPages> createState() => _OneFingerPagesState();
}

class _OneFingerPagesState extends State<OneFingerPages> {
  Drag? _drag;
  ScrollHoldController? _hold;

  ScrollPosition? get _position =>
      widget.controller.hasClients ? widget.controller.position : null;

  void _onDown(DragDownDetails details) {
    _hold = _position?.hold(() => _hold = null);
  }

  void _onStart(DragStartDetails details) {
    _drag = _position?.drag(details, () => _drag = null);
  }

  void _onUpdate(DragUpdateDetails details) => _drag?.update(details);

  void _onEnd(DragEndDetails details) => _drag?.end(details);

  void _onCancel() {
    _hold?.cancel();
    _drag?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final behavior = ScrollConfiguration.of(context);
    final physics = behavior.getScrollPhysics(context);
    return RawGestureDetector(
      gestures: {
        if (widget.enabled)
          OneFingerHorizontalDrag:
              GestureRecognizerFactoryWithHandlers<OneFingerHorizontalDrag>(
                () => OneFingerHorizontalDrag(debugOwner: this),
                (drag) {
                  drag
                    ..onDown = _onDown
                    ..onStart = _onStart
                    ..onUpdate = _onUpdate
                    ..onEnd = _onEnd
                    ..onCancel = _onCancel
                    ..minFlingDistance = physics.minFlingDistance
                    ..minFlingVelocity = physics.minFlingVelocity
                    ..maxFlingVelocity = physics.maxFlingVelocity
                    ..velocityTrackerBuilder = behavior.velocityTrackerBuilder(
                      context,
                    )
                    ..gestureSettings = MediaQuery.maybeGestureSettingsOf(
                      context,
                    )
                    ..supportedDevices = behavior.dragDevices;
                },
              ),
      },
      child: widget.child,
    );
  }
}
