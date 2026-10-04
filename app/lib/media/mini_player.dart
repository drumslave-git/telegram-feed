import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../l10n/l10n.dart';
import 'audio_session.dart';
import 'media_viewer.dart';
import 'video_sessions.dart';
import 'video_stage.dart';

/// Picture-in-picture inside the app: the video of the viewer goes on playing in a small
/// window that floats over the timeline and every other screen. It is dragged around and
/// rests at the nearer side, resized with a pinch, and thrown off a side to close; a tap
/// shows its buttons (play or pause, back to the viewer, close) and a double tap seeks
/// ten seconds, back on its left half and forwards on its right. One at a time; opening
/// the viewer ends it.
abstract final class MiniPlayer {
  static OverlayEntry? _entry;
  static VideoSession? _session;

  /// The smallest a pinch makes the window.
  static const minWidth = 120.0;

  /// Where the last window was left and how wide a pinch made it: the next one opens
  /// there, for as long as the app runs.
  static Offset? _lastAt;
  static double? _lastWidth;

  /// Forgets the place and the size (tests start from the corner).
  @visibleForTesting
  static void forgetPlace() {
    _lastAt = null;
    _lastWidth = null;
  }

  static bool get isShowing => _entry != null;

  /// Takes [session] over from the viewer, which the caller closes afterwards. [items] and
  /// [index] are what the viewer showed, for the way back.
  static void show(
    BuildContext context, {
    required VideoSession session,
    required List<Media> items,
    required int index,
    required TelegramGateway gateway,
    Future<void> Function(BuildContext context, List<Media> items, int index)?
    reopen,
  }) {
    dismiss();
    final overlay = Navigator.of(context, rootNavigator: true).overlay;
    if (overlay == null) return;
    _session = session..retainForViewer();
    final entry = _entry = OverlayEntry(
      builder: (context) => _MiniPlayerView(
        session: session,
        onClose: dismiss,
        onExpand: () => unawaited(
          // The viewer takes the session over and dismisses this window once it is up.
          reopen != null
              ? reopen(context, items, index)
              : MediaViewerScreen.open(
                  context,
                  items: items,
                  gateway: gateway,
                  initialIndex: index,
                ),
        ),
      ),
    );
    overlay.insert(entry);
  }

  /// Hands the session back: unless the viewer holds it by now, the video ends here.
  static void dismiss() {
    final entry = _entry;
    if (entry == null) return;
    _entry = null;
    // Safe when the overlay itself is gone already (the app was torn down around it).
    entry.remove();
    entry.dispose();
    _session?.releaseFromViewer();
    _session = null;
    // Closed for good, not opened in the viewer again: what the video paused plays on.
    if (MediaViewerScreen.showing.value == 0) {
      unawaited(AudioSessions.instance.resumeAfterVideo());
    }
  }
}

/// A round video message that was playing with its sound when its post scrolled away
/// goes on in a small round window in the top right corner, as in the official app, and
/// goes back into its post when that is on the screen again. A tap pauses and plays it,
/// the cross ends it, and it goes by itself when the message has played to its end.
abstract final class RoundFloat {
  static OverlayEntry? _entry;
  static VideoSession? _session;

  /// How wide the window is.
  static const side = 120.0;

  static bool get isShowing => _entry != null;

  /// Whether the window shows [session].
  static bool shows(VideoSession session) => identical(_session, session);

  /// Takes [session] over while its row is out of sight. The window holds the session,
  /// so it plays on when the row itself is gone.
  static void show(OverlayState overlay, VideoSession session) {
    if (shows(session)) return;
    dismiss();
    _session = session..retain();
    session.addListener(_onSession);
    final entry = _entry = OverlayEntry(
      builder: (context) => _RoundFloatView(
        session: session,
        onClose: () {
          unawaited(session.pause());
          dismiss();
        },
      ),
    );
    // A row that goes while its message plays asks from its `dispose`, where nothing
    // may be built: the window appears with the next frame then.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      overlay.insert(entry);
    } else {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (identical(_entry, entry) && overlay.mounted) overlay.insert(entry);
      });
    }
  }

  /// Played to its end: nothing more to show.
  static void _onSession() {
    final v = _session?.controller?.value;
    if (v == null || !v.isInitialized) return;
    if (v.duration > Duration.zero &&
        v.position >= v.duration &&
        !v.isPlaying) {
      scheduleMicrotask(dismiss);
    }
  }

  /// The window goes; the session lives on if its row holds it.
  static void dismiss() {
    final entry = _entry;
    if (entry == null) return;
    _entry = null;
    // It may not have got as far as the screen.
    if (entry.mounted) entry.remove();
    entry.dispose();
    final session = _session;
    _session = null;
    session?.removeListener(_onSession);
    session?.release();
  }
}

class _RoundFloatView extends StatelessWidget {
  const _RoundFloatView({required this.session, required this.onClose});
  final VideoSession session;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final l10n = context.l10n;
    return Positioned(
      // Under the header, out of the way of the newest post.
      top: media.padding.top + kToolbarHeight + 12,
      right: 12 + media.padding.right,
      width: RoundFloat.side,
      height: RoundFloat.side,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Semantics(
              label: l10n.pipFloatingPlayer,
              button: true,
              child: GestureDetector(
                onTap: session.togglePlay,
                child: Material(
                  color: Colors.black,
                  elevation: 8,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InlineVideo(
                    session: session,
                    poster: const SizedBox.expand(),
                    cover: true,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: -6,
            right: -6,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onClose,
                child: Tooltip(
                  message: l10n.commonClose,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 18, color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniPlayerView extends StatefulWidget {
  const _MiniPlayerView({
    required this.session,
    required this.onClose,
    required this.onExpand,
  });
  final VideoSession session;
  final VoidCallback onClose;
  final VoidCallback onExpand;

  @override
  State<_MiniPlayerView> createState() => _MiniPlayerViewState();
}

class _MiniPlayerViewState extends State<_MiniPlayerView> {
  static const _margin = 12.0;

  /// How far a double tap seeks.
  static const _seekStep = Duration(seconds: 10);

  /// How fast a window that is already over an edge has to move to be thrown away.
  static const _throwSpeed = 700.0;

  /// Top left corner; null until the first layout puts the window bottom right, or where
  /// the window before this one was left.
  Offset? _at = MiniPlayer._lastAt;

  /// The width a pinch gave the window; null for the width it has by itself.
  double? _width = MiniPlayer._lastWidth;

  /// A finger moves the window: it may leave the screen sideways, to be thrown away.
  bool _moving = false;
  double _widthAtPinchStart = 0;

  /// The buttons are over the picture: after a tap, and for a moment when it appears.
  bool _controls = true;
  Timer? _hide;
  TapDownDetails? _doubleTapAt;

  VideoSession get _s => widget.session;

  @override
  void initState() {
    super.initState();
    _s.addListener(_onSession);
    _scheduleHide();
  }

  @override
  void dispose() {
    _hide?.cancel();
    _s.removeListener(_onSession);
    super.dispose();
  }

  void _onSession() {
    if (!mounted) return;
    // A video that broke has nothing to show in a window without room for an error.
    if (_s.error != null) return scheduleMicrotask(widget.onClose);
    setState(() {});
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      // A paused video keeps its buttons: there is nothing to watch behind them.
      if (!mounted || !_s.isPlaying) return;
      setState(() => _controls = false);
    });
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    if (_controls) _scheduleHide();
  }

  Future<void> _togglePlay() async {
    await _s.togglePlay();
    _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screen = media.size;
    final c = _s.controller;
    final ready = c != null && c.value.isInitialized;
    final file = _s.file;
    final aspect =
        (ready
                ? c.value.aspectRatio
                : file.width > 0 && file.height > 0
                ? file.width / file.height
                : 16 / 9)
            .clamp(0.6, 1.8);
    final own = (screen.width * (aspect < 1 ? 0.36 : 0.5)).clamp(
      MiniPlayer.minWidth,
      280.0,
    );
    // A pinch makes it anything between the smallest and the width of the screen.
    final widest = screen.width - 2 * _margin - media.padding.horizontal;
    final width = (_width ?? own).clamp(
      MiniPlayer.minWidth,
      widest < MiniPlayer.minWidth ? MiniPlayer.minWidth : widest,
    );
    final size = Size(width, width / aspect);
    final bounds = Rect.fromLTRB(
      _margin + media.padding.left,
      _margin + media.padding.top,
      screen.width - size.width - _margin - media.padding.right,
      screen.height - size.height - _margin - media.padding.bottom,
    );
    final at = _at ?? Offset(bounds.right, bounds.bottom - 72);
    final position = Offset(
      // While a finger moves it the window follows over the side edges.
      _moving ? at.dx : at.dx.clamp(bounds.left, bounds.right),
      at.dy.clamp(bounds.top, bounds.bottom),
    );
    final playing = c?.value.isPlaying ?? false;
    final total = c?.value.duration.inMilliseconds ?? 0;
    final l10n = context.l10n;
    return Positioned(
      left: position.dx,
      top: position.dy,
      width: size.width,
      height: size.height,
      child: Semantics(
        label: l10n.pipFloatingPlayer,
        child: Material(
          color: Colors.black,
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: IconTheme(
            data: const IconThemeData(color: Colors.white, size: 20),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Behind the buttons, not around them: around them every button tap
                // would wait out the double-tap window.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleControls,
                  onDoubleTapDown: (d) => _doubleTapAt = d,
                  // The left half goes back, the right half forwards.
                  onDoubleTap: () => unawaited(
                    _s.seekBy(
                      (_doubleTapAt?.localPosition.dx ?? 0) < size.width / 2
                          ? -_seekStep
                          : _seekStep,
                    ),
                  ),
                  onScaleStart: (_) => setState(() {
                    _moving = true;
                    _at = position;
                    _widthAtPinchStart = size.width;
                  }),
                  onScaleUpdate: (d) => setState(() {
                    if (d.pointerCount >= 2) {
                      // Two fingers resize it around its middle.
                      final next = (_widthAtPinchStart * d.scale).clamp(
                        MiniPlayer.minWidth,
                        widest < MiniPlayer.minWidth
                            ? MiniPlayer.minWidth
                            : widest,
                      );
                      final grown = next - size.width;
                      _width = next;
                      _at = position - Offset(grown / 2, grown / aspect / 2);
                    } else {
                      _at = position + d.focalPointDelta;
                    }
                  }),
                  onScaleEnd: (d) {
                    final speed = d.velocity.pixelsPerSecond.dx;
                    final overLeft = bounds.left - position.dx;
                    final overRight = position.dx - bounds.right;
                    // Thrown off a side: over the edge and still moving out, or most of the
                    // way out already.
                    final thrown =
                        (overLeft > 0 &&
                            (speed < -_throwSpeed ||
                                overLeft > size.width / 2)) ||
                        (overRight > 0 &&
                            (speed > _throwSpeed ||
                                overRight > size.width / 2));
                    if (thrown) return widget.onClose();
                    setState(() {
                      _moving = false;
                      // Rests at the nearer side, as the system's window does.
                      _at = Offset(
                        position.dx + size.width / 2 < screen.width / 2
                            ? bounds.left
                            : bounds.right,
                        position.dy,
                      );
                    });
                    // The next window opens where this one was left, as large as it was.
                    MiniPlayer._lastAt = _at;
                    MiniPlayer._lastWidth = _width;
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (ready)
                        VideoPicture(c)
                      else
                        const Center(
                          child: CircularProgressIndicator(
                            color: Colors.white70,
                          ),
                        ),
                    ],
                  ),
                ),
                if (_controls) ...[
                  const IgnorePointer(child: ColoredBox(color: Colors.black38)),
                  if (ready)
                    Center(
                      child: IconButton(
                        tooltip: playing ? l10n.playerPause : l10n.playerPlay,
                        iconSize: 36,
                        icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                        onPressed: () => unawaited(_togglePlay()),
                      ),
                    ),
                  Align(
                    alignment: Alignment.topCenter,
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: l10n.pipBackToFullScreen,
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.open_in_full),
                          onPressed: widget.onExpand,
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: l10n.commonClose,
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close),
                          onPressed: widget.onClose,
                        ),
                      ],
                    ),
                  ),
                ],
                if (ready && total > 0)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      value: (c.value.position.inMilliseconds / total).clamp(
                        0.0,
                        1.0,
                      ),
                      color: Colors.white,
                      backgroundColor: Colors.white24,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
