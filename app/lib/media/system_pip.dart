import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import 'now_playing.dart';
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

  /// What the window's button is called, in the app's language ([PipHost] sets them).
  static String playLabel = 'Play';
  static String pauseLabel = 'Pause';

  /// The video the window showed last: its button plays it again after a pause, when
  /// nothing is in [VideoSessions.foreground] any more.
  static VideoSession? _last;

  static void start() {
    if (_started) return;
    _started = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'pipChanged':
          active.value = call.arguments == true;
        // The window's own button: play or pause.
        case 'pipAction':
          await (VideoSessions.foreground.value ?? _last)?.togglePlay();
      }
    });
    VideoSessions.foreground.addListener(_arm);
  }

  static void _arm() {
    final now = VideoSessions.foreground.value;
    if (now != null) _last = now;
    final size = now?.controller?.value.size;
    unawaited(
      _channel
          .invokeMethod<void>('arm', {
            'enabled': size != null,
            'width': size == null || size.isEmpty ? 16 : size.width.round(),
            'height': size == null || size.isEmpty ? 9 : size.height.round(),
            // The window's button: pause while it plays, play otherwise.
            'playing': size != null,
            'playLabel': playLabel,
            'pauseLabel': pauseLabel,
          })
          .catchError((Object e) {
            // No activity behind the channel (tests, a platform without the window).
          }, test: (e) => e is MissingPluginException),
    );
    // The screen stays on while that video plays, as in the official app: nobody touches
    // the phone through a long video.
    unawaited(
      const MethodChannel('tf/app')
          .invokeMethod<void>('keepScreenOn', size != null)
          .catchError((Object e) {}, test: (e) => e is MissingPluginException),
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
    NowPlaying.start();
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
    // Above the app's strings there are none: the labels stay English there.
    final l10n = Localizations.of<AppLocalizations>(context, AppLocalizations);
    if (l10n != null) {
      SystemPip.playLabel = l10n.playerPlay;
      SystemPip.pauseLabel = l10n.playerPause;
      NowPlaying.words = (
        channel: l10n.nowPlayingChannel,
        play: l10n.playerPlay,
        pause: l10n.playerPause,
        previous: l10n.audioPrevious,
        next: l10n.audioNext,
      );
    }
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
