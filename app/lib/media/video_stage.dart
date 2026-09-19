import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:telegram_gateway/telegram_gateway.dart';
import 'package:video_player/video_player.dart';

import '../feeds/media_view.dart' show formatDuration;
import 'swipe_to_close.dart';
import 'video_downloads.dart';
import 'video_sessions.dart';
import 'zoom.dart';

const _seekStep = Duration(seconds: 10);
const _holdSpeed = 2.0;

/// The session's frames at the video's own aspect ratio.
class VideoPicture extends StatelessWidget {
  const VideoPicture(this.controller, {super.key});
  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) => Center(
    child: AspectRatio(
      aspectRatio: controller.value.aspectRatio,
      child: VideoPlayer(controller),
    ),
  );
}

/// A video that autoplays in its timeline row: the picture without sound and without
/// controls. Watching it properly happens in the viewer, which a tap on the row opens.
class InlineVideo extends StatelessWidget {
  const InlineVideo({super.key, required this.session, required this.poster});
  final VideoSession session;
  final Widget poster;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final c = session.controller;
      final ready = c != null && c.value.isInitialized && session.error == null;
      return Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          if (ready) VideoPicture(c) else poster,
          if (session.error == null && (!ready || c.value.isBuffering))
            const Center(
              child: CircularProgressIndicator(color: Colors.white70),
            ),
          if (ready && session.muted)
            const Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.volume_off, color: Colors.white70, size: 20),
              ),
            ),
        ],
      );
    },
  );
}

/// The picture of a [VideoSession] with its controls, as the viewer shows it: tap shows or
/// hides them, double tap on the left or right third seeks 10 seconds, double tap in the
/// middle zooms in and out. Pinching zooms too, and a drag moves the zoomed picture. A finger
/// held down plays at 2× until it lifts. The stage has no background of its own: the viewer
/// puts the black behind it and fades it while the stage is dragged away.
class VideoStage extends StatefulWidget {
  const VideoStage({
    super.key,
    required this.session,
    this.poster,
    this.actions = const [],
    this.onZoomChanged,
  });
  final VideoSession session;

  /// Buttons at the right end of the top bar (download, picture-in-picture).
  final List<Widget> actions;

  /// Shown until the first frame is ready (the post's thumbnail).
  final Widget? poster;

  /// The viewer stops paging and swipe-to-close while the picture is zoomed in, so that a
  /// drag pans it.
  final ValueChanged<bool>? onZoomChanged;

  @override
  State<VideoStage> createState() => _VideoStageState();
}

class _VideoStageState extends State<VideoStage> {
  bool _controls = true;
  Timer? _hide;

  /// Slider position while the user drags it; the player is asked once on release.
  double? _scrub;

  /// -1 / +1 while the seek hint of that side is visible.
  int _seekHint = 0;
  Timer? _seekHintTimer;

  TapDownDetails? _lastDoubleTap;

  final _transform = TransformationController();
  bool _zoomed = false;

  /// The speed to go back to while a held finger plays at 2×; null when none is held.
  double? _speedBeforeHold;

  VideoSession get _s => widget.session;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransform);
    _s.addListener(_onSession);
    _scheduleHide();
  }

  @override
  void didUpdateWidget(VideoStage old) {
    super.didUpdateWidget(old);
    if (!identical(old.session, widget.session)) {
      old.session.removeListener(_onSession);
      _s.addListener(_onSession);
      _transform.value = Matrix4.identity();
    }
  }

  void _onTransform() {
    final zoomed = _transform.isZoomed;
    if (zoomed == _zoomed) return;
    _zoomed = zoomed;
    widget.onZoomChanged?.call(zoomed);
  }

  @override
  void dispose() {
    _s.removeListener(_onSession);
    _hide?.cancel();
    _seekHintTimer?.cancel();
    _transform.dispose();
    final before = _speedBeforeHold;
    if (before != null) unawaited(_s.controller?.setPlaybackSpeed(before));
    super.dispose();
  }

  void _onSession() {
    if (mounted) setState(() {});
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && (_s.controller?.value.isPlaying ?? false)) {
        setState(() => _controls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    if (_controls) _scheduleHide();
  }

  void _onDoubleTap(TapDownDetails d, double width) {
    final x = d.localPosition.dx;
    if (x < width / 3) {
      _seek(-1);
    } else if (x > width * 2 / 3) {
      _seek(1);
    } else {
      _transform.toggleZoom(d.localPosition);
    }
  }

  void _holdStart() {
    final c = _s.controller;
    if (c == null || !c.value.isPlaying || _speedBeforeHold != null) return;
    setState(() => _speedBeforeHold = c.value.playbackSpeed);
    unawaited(c.setPlaybackSpeed(_holdSpeed));
  }

  void _holdEnd() {
    final before = _speedBeforeHold;
    if (before == null) return;
    setState(() => _speedBeforeHold = null);
    unawaited(_s.controller?.setPlaybackSpeed(before));
  }

  void _seek(int direction) {
    unawaited(_s.seekBy(_seekStep * direction));
    _seekHintTimer?.cancel();
    setState(() => _seekHint = direction);
    _seekHintTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _seekHint = 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = _s.controller;
    final ready = c != null && c.value.isInitialized;
    if (_s.error != null) return _error(_s.error!);
    // The gesture layer sits behind the buttons instead of around them: inside it, every
    // button tap would wait out the double-tap window.
    return LayoutBuilder(
      builder: (context, box) => Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: ready ? _toggleControls : null,
            onDoubleTapDown: ready ? (d) => _lastDoubleTap = d : null,
            onDoubleTap: ready
                ? () => _onDoubleTap(_lastDoubleTap!, box.maxWidth)
                : null,
            onLongPressStart: ready ? (_) => _holdStart() : null,
            onLongPressEnd: ready ? (_) => _holdEnd() : null,
            onLongPressCancel: ready ? _holdEnd : null,
            child: InteractiveViewer(
              transformationController: _transform,
              minScale: 1,
              maxScale: 6,
              panEnabled: ready,
              scaleEnabled: ready,
              child: ready
                  ? VideoPicture(c)
                  : widget.poster ?? const SizedBox.expand(),
            ),
          ),
          if (ready && _controls) const IgnorePointer(child: _Scrim()),
          if (!ready || c.value.isBuffering)
            const IgnorePointer(
              child: Center(
                child: CircularProgressIndicator(color: Colors.white70),
              ),
            ),
          if (_seekHint != 0)
            IgnorePointer(child: _SeekHint(direction: _seekHint)),
          if (_speedBeforeHold != null) const IgnorePointer(child: _HoldHint()),
          if (ready && _controls) SafeArea(child: _overlay(c)),
          // Leaving must work while the video still loads, too.
          if (!ready || _controls) _TopBar(actions: widget.actions),
        ],
      ),
    );
  }

  Widget _error(String message) => SizedBox.expand(
    child: Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Cannot play this video: $message',
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
              TextButton(onPressed: _s.retry, child: const Text('Try again')),
            ],
          ),
        ),
        _TopBar(actions: widget.actions),
      ],
    ),
  );

  Widget _overlay(VideoPlayerController c) {
    final v = c.value;
    final total = v.duration.inMilliseconds.toDouble();
    final position = (_scrub ?? v.position.inMilliseconds.toDouble()).clamp(
      0.0,
      total <= 0 ? 0.0 : total,
    );
    final buffered = v.buffered.isEmpty
        ? 0.0
        : v.buffered.last.end.inMilliseconds.toDouble().clamp(0.0, total);
    final ended = total > 0 && v.position >= v.duration && !v.isPlaying;
    return IconTheme(
      data: const IconThemeData(color: Colors.white),
      child: Stack(
        children: [
          Center(
            child: IconButton(
              iconSize: 56,
              tooltip: v.isPlaying ? 'Pause' : 'Play',
              icon: Icon(
                ended
                    ? Icons.replay_circle_filled
                    : v.isPlaying
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_fill,
              ),
              onPressed: () async {
                if (ended) await c.seekTo(Duration.zero);
                await _s.togglePlay();
                _scheduleHide();
              },
            ),
          ),
          Positioned(
            left: 8,
            right: 0,
            bottom: 0,
            child: Row(
              children: [
                Text(
                  '${formatDuration(position ~/ 1000)} / ${formatDuration(v.duration.inSeconds)}',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      activeTrackColor: Colors.white,
                      secondaryActiveTrackColor: Colors.white54,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 14,
                      ),
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                    ),
                    child: Slider(
                      max: total <= 0 ? 1 : total,
                      value: position,
                      secondaryTrackValue: buffered,
                      onChangeStart: (_) => _hide?.cancel(),
                      onChanged: (x) => setState(() => _scrub = x),
                      onChangeEnd: (x) async {
                        await c.seekTo(Duration(milliseconds: x.round()));
                        if (mounted) setState(() => _scrub = null);
                        _scheduleHide();
                      },
                    ),
                  ),
                ),
                PopupMenuButton<double>(
                  tooltip: 'Speed',
                  icon: const Icon(Icons.speed, color: Colors.white),
                  initialValue: v.playbackSpeed,
                  onSelected: c.setPlaybackSpeed,
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 0.5, child: Text('0.5×')),
                    PopupMenuItem(value: 1.0, child: Text('1×')),
                    PopupMenuItem(value: 1.5, child: Text('1.5×')),
                    PopupMenuItem(value: 2.0, child: Text('2×')),
                  ],
                ),
                IconButton(
                  tooltip: _s.muted ? 'Sound on' : 'Sound off',
                  icon: Icon(_s.muted ? Icons.volume_off : Icons.volume_up),
                  onPressed: () => _s.setMuted(!_s.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Back arrow in the top left corner, where the official viewer has it.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.actions});
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
        child: Row(
          children: [
            const BackButton(color: Colors.white),
            const Spacer(),
            ...actions,
          ],
        ),
      ),
    ),
  );
}

/// Darkens the top and bottom so the white controls stay readable on bright video.
class _Scrim extends StatelessWidget {
  const _Scrim();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.black38, Colors.transparent, Colors.black54],
        stops: [0, 0.4, 1],
      ),
    ),
  );
}

/// Shown at the top while a held finger plays the video faster.
class _HoldHint extends StatelessWidget {
  const _HoldHint();

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Align(
      alignment: Alignment.topCenter,
      child: Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('2×', style: TextStyle(color: Colors.white)),
            SizedBox(width: 4),
            Icon(Icons.fast_forward, color: Colors.white, size: 18),
          ],
        ),
      ),
    ),
  );
}

class _SeekHint extends StatelessWidget {
  const _SeekHint({required this.direction});
  final int direction;

  @override
  Widget build(BuildContext context) => Align(
    alignment: direction < 0 ? Alignment.centerLeft : Alignment.centerRight,
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            direction < 0 ? Icons.fast_rewind : Icons.fast_forward,
            color: Colors.white,
            size: 20,
          ),
          const SizedBox(width: 6),
          Text(
            '${_seekStep.inSeconds} s',
            style: const TextStyle(color: Colors.white),
          ),
        ],
      ),
    ),
  );
}

/// One video on the whole screen, in whatever orientation the device has. Opening it starts
/// (or takes over) the file's session with sound; leaving hands the session back, which ends
/// playback and streaming unless the video autoplays in its row.
class FullscreenVideoScreen extends StatefulWidget {
  const FullscreenVideoScreen({
    super.key,
    required this.video,
    required this.gateway,
    this.poster,
  });
  final VideoMedia video;
  final TelegramGateway gateway;
  final Widget? poster;

  static Future<void> open(
    BuildContext context, {
    required VideoMedia video,
    required TelegramGateway gateway,
    Widget? poster,
  }) => Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      // The timeline shows through while the video is dragged away.
      opaque: false,
      pageBuilder: (_, _, _) =>
          FullscreenVideoScreen(video: video, gateway: gateway, poster: poster),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );

  @override
  State<FullscreenVideoScreen> createState() => _FullscreenVideoScreenState();
}

class _FullscreenVideoScreenState extends State<FullscreenVideoScreen> {
  late final VideoSession _session;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _session = VideoSessions.of(widget.gateway).open(
      widget.video.file,
      loop: widget.video.isAnimation,
    )..retainForViewer();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _session.releaseFromViewer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: SwipeToClose(
      enabled: !_zoomed,
      onClose: () => Navigator.of(context).maybePop(),
      child: VideoStage(
        session: _session,
        poster: widget.poster,
        onZoomChanged: (z) => setState(() => _zoomed = z),
        actions: [
          VideoDownloadButton(file: widget.video.file, gateway: widget.gateway),
        ],
      ),
    ),
  );
}
