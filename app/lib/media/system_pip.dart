import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'video_sessions.dart';
import 'video_stage.dart';

/// Android's picture-in-picture window. The activity is armed while a video plays in the
/// viewer or the mini player ([VideoSessions.foreground]); leaving the app then shrinks it to
/// a floating window instead of stopping it (`MainActivity`: auto-enter from Android 12,
/// `onUserLeaveHint` before).
abstract final class SystemPip {
  static const _channel = MethodChannel('tf/pip');

  /// The activity is the floating window right now.
  static final active = ValueNotifier<bool>(false);
  static bool _started = false;

  static void start() {
    if (_started) return;
    _started = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'pipChanged') active.value = call.arguments == true;
    });
    VideoSessions.foreground.addListener(_arm);
  }

  static void _arm() {
    final size = VideoSessions.foreground.value?.controller?.value.size;
    unawaited(
      _channel
          .invokeMethod<void>('arm', {
            'enabled': size != null,
            'width': size == null || size.isEmpty ? 16 : size.width.round(),
            'height': size == null || size.isEmpty ? 9 : size.height.round(),
          })
          .catchError((Object e) {
            // No activity behind the channel (tests, a platform without the window).
          }, test: (e) => e is MissingPluginException),
    );
  }
}

/// Sits above the navigator. While the activity is the picture-in-picture window it shows
/// nothing but the video; the screens stay alive below, laid out but not painted, since they
/// were not made for a window that small.
class PipHost extends StatefulWidget {
  const PipHost({super.key, required this.child});
  final Widget child;

  @override
  State<PipHost> createState() => _PipHostState();
}

class _PipHostState extends State<PipHost> with WidgetsBindingObserver {
  /// What the window shows; kept when the video pauses or ends inside the window.
  VideoSession? _shown;

  @override
  void initState() {
    super.initState();
    SystemPip.start();
    SystemPip.active.addListener(_changed);
    VideoSessions.foreground.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemPip.active.removeListener(_changed);
    VideoSessions.foreground.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {
      _shown = SystemPip.active.value
          ? VideoSessions.foreground.value ?? _shown
          : null;
    });
  }

  /// The activity was stopped without becoming (or after being) the floating window: the
  /// user closed that window, or the device has none. Sound must not go on in the background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      unawaited(VideoSessions.foreground.value?.pause());
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(offstage: shown != null, child: widget.child),
        if (shown != null)
          ColoredBox(
            color: Colors.black,
            child: ListenableBuilder(
              listenable: shown,
              builder: (context, _) {
                final c = shown.controller;
                return c != null && c.value.isInitialized
                    ? VideoPicture(c)
                    : const SizedBox.expand();
              },
            ),
          ),
      ],
    );
  }
}
