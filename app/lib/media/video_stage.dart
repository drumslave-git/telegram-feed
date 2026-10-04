import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../feeds/formatted_text.dart';
import '../feeds/open_links.dart';

import 'package:video_player/video_player.dart';

import '../feeds/media_view.dart' show formatDuration;
import '../l10n/l10n.dart';
import 'video_sessions.dart';
import 'zoom.dart';

const _seekStep = Duration(seconds: 10);

/// How long after a seek's last tap the next one still adds a step.
const _streakWindow = Duration(milliseconds: 700);

/// A speed as the player says it: "2×", "0.5×", "1.3×".
String speedLabel(double speed) {
  final rounded = (speed * 10).round() / 10;
  return rounded == rounded.roundToDouble()
      ? '${rounded.round()}×'
      : '${rounded.toStringAsFixed(1)}×';
}

/// What a held finger does to the video, as in the official app (`VideoPlayerRewinder`
/// and, for a video of more than three minutes, `OldVideoPlayerRewinder`).
///
/// Up to three minutes: the hold starts at 2×, or rewinds at 2× when it begins on the
/// left third, and a slide to the side changes the speed, 40 px for one whole step;
/// under 0.4× the video turns round and runs backwards, from 1.5× back to 6×, and
/// forwards it goes up to 10×.
///
/// Over three minutes: the right third runs forwards at 4×, then 7×, then 13×, a step
/// every two seconds, the left third rewinds at 3×, 6× and 12×, and the middle does
/// nothing.
class HoldSeek {
  HoldSeek.short({required double x, required double width})
    : long = false,
      forward = x > width / 3,
      _x = x {
    _value = forward ? 2.0 : _valueOf(-2.0);
  }

  HoldSeek.long({required this.forward}) : long = true, _x = 0;

  /// Too short to seek in by holding.
  static const minDuration = Duration(seconds: 8);

  /// From here on a video is sought in steps.
  static const longDuration = Duration(minutes: 3);

  /// How far the finger slides for one whole step of speed.
  static const slidePerStep = 40.0;

  /// How long a step of a long video lasts.
  static const stepEvery = Duration(seconds: 2);

  static const _forwardSteps = [4.0, 7.0, 13.0];
  static const _rewindSteps = [3.0, 6.0, 12.0];

  final bool long;

  /// Which way it began; a short video's slide can turn it round.
  final bool forward;
  double _x;
  double _value = 0;
  int _step = 0;

  static double _valueOf(double speed) => speed < -1.5 ? speed + 1.9 : speed;

  /// The finger moved to [x]: only a short video follows it.
  void slideTo(double x) {
    if (long) return;
    _value += (x - _x) / slidePerStep;
    _x = x;
  }

  /// The next step of a long video; false when it is at its last.
  bool nextStep() {
    if (!long || _step >= _forwardSteps.length - 1) return false;
    _step++;
    return true;
  }

  /// How fast the video runs, negative when it runs backwards.
  double get speed {
    if (long) return forward ? _forwardSteps[_step] : -_rewindSteps[_step];
    final v = _value < 0.4 ? _value - 1.9 : _value;
    return v.clamp(-6.0, 10.0);
  }
}

/// The height of the row with the scrubber, which the caption stays above.
const _barHeight = 48.0;

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
  const InlineVideo({
    super.key,
    required this.session,
    required this.poster,
    this.cover = false,
  });
  final VideoSession session;
  final Widget poster;

  /// Crops the picture into the box (a cell of an album) instead of fitting it inside.
  final bool cover;

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
          if (!ready)
            poster
          else if (cover)
            FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox.fromSize(
                size: c.value.size,
                child: VideoPlayer(c),
              ),
            )
          else
            VideoPicture(c),
          if (session.error == null && (!ready || c.value.isBuffering))
            const Center(
              child: CircularProgressIndicator(color: Colors.white70),
            ),
          if (ready && session.muted)
            // Bottom left: the views and the time sit in the other corner.
            const Align(
              alignment: Alignment.bottomLeft,
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
/// hides them, double tap on the left or right third seeks 10 seconds and every further tap
/// there 10 more, double tap in the middle zooms in and out. Pinching zooms too, and a drag moves the zoomed picture. A finger
/// held down plays at 2× until it lifts. The stage has no background of its own: the viewer
/// puts the black behind it and fades it while the stage is dragged away.
class VideoStage extends StatefulWidget {
  const VideoStage({
    super.key,
    required this.session,
    this.caption = '',
    this.entities = const [],
    this.onOpenLink,
    this.onEdgeTap,
    this.poster,
    this.title,
    this.actions = const [],
    this.onZoomChanged,
  });
  final VideoSession session;

  /// The formatting of [caption] and what a link in it opens ([ViewerCaption]).
  final List<TextEntity> entities;
  final void Function(String url)? onOpenLink;

  /// Asked first about a single tap, with where on the screen it was: true when the tap
  /// turned the viewer's page and is no tap on the video.
  final bool Function(Offset at)? onEdgeTap;

  /// Beside the back arrow: the position in the album.
  final Widget? title;

  /// Buttons at the right end of the top bar (download, picture-in-picture).
  final List<Widget> actions;

  /// Shown until the first frame is ready (the post's thumbnail).
  final Widget? poster;

  /// What the post said, over the bottom of the picture.
  final String caption;

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

  /// The seek that double taps on one side add up to: every further tap on that side while
  /// it lasts goes another step, so two taps go 10 s, three 20 s, four 30 s. Null when no
  /// seek is going on.
  _SeekStreak? _streak;
  Timer? _streakEnd;

  TapDownDetails? _lastDoubleTap;
  TapUpDetails? _lastTapUp;

  final _transform = TransformationController();
  bool _zoomed = false;

  /// The seek of a held finger; null when none is held.
  HoldSeek? _hold;

  /// The speed to go back to when the finger lifts, and whether the video played.
  double _speedBeforeHold = 1;
  bool _playedBeforeHold = false;

  /// Where a hold that rewinds stands; null while it runs forwards.
  Duration? _holdBack;
  Timer? _holdTicker;
  int _holdTicks = 0;

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
    _streakEnd?.cancel();
    _transform.dispose();
    _holdTicker?.cancel();
    if (_hold != null) {
      unawaited(_s.controller?.setPlaybackSpeed(_speedBeforeHold));
    }
    if (_turned) {
      _turned = false;
      // The device decides again.
      unawaited(SystemChrome.setPreferredOrientations(const []));
    }
    super.dispose();
  }

  /// The seek back to the start is under way.
  bool _returning = false;

  void _onSession() {
    if (!mounted) return;
    _returnFromEnd();
    setState(() {});
  }

  /// A video that does not loop goes back to its start when it has played to its end,
  /// and waits there with the controls shown, as in the official app. The player has
  /// paused itself and stands on its last frame by then.
  void _returnFromEnd() {
    final c = _s.controller;
    if (c == null || _returning) return;
    final v = c.value;
    final ended =
        v.isInitialized &&
        v.duration > Duration.zero &&
        v.position >= v.duration &&
        !v.isPlaying &&
        !v.isLooping;
    if (!ended) return;
    _returning = true;
    _hide?.cancel();
    _controls = true;
    unawaited(c.seekTo(Duration.zero).whenComplete(() => _returning = false));
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (!mounted || !(_s.controller?.value.isPlaying ?? false)) return;
      // Someone who works the screen through a screen reader (or a test through the
      // same service) needs longer than three seconds to reach a control: for them the
      // controls stay until they are tapped away, as a snack bar with an action does.
      if (MediaQuery.accessibleNavigationOf(context)) return;
      setState(() => _controls = false);
    });
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    if (_controls) _scheduleHide();
  }

  /// A single tap on the picture: near a side edge it turns the viewer's page, anywhere
  /// else it shows or hides the controls.
  void _onTap() {
    final at = _lastTapUp;
    if (at != null && (widget.onEdgeTap?.call(at.globalPosition) ?? false)) {
      return;
    }
    _toggleControls();
  }

  /// While the seek bar is dragged the picture follows it, where the player already
  /// has that part of the video: a part that is still to be downloaded waits for the
  /// finger to lift, so a drag does not send the download from place to place.
  void _showFrameAt(VideoPlayerController c, double milliseconds) {
    final watch = _frameWatch;
    if (watch != null && watch.elapsed < _frameEvery) return;
    final at = Duration(milliseconds: milliseconds.round());
    final v = c.value;
    final local = c.dataSourceType == DataSourceType.file;
    if (!local && !v.buffered.any((r) => r.start <= at && at <= r.end)) return;
    _frameWatch = Stopwatch()..start();
    unawaited(c.seekTo(at));
  }

  static const _frameEvery = Duration(milliseconds: 150);

  /// Since the picture last followed the drag; null before it ever did.
  Stopwatch? _frameWatch;

  /// The orientation the rotate button asked for was set: it is given back to the
  /// device when the stage goes.
  static bool _turned = false;

  /// Lays the screen on its side, or stands it up again, whatever way the phone is held.
  void _rotate() {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    _turned = true;
    unawaited(
      SystemChrome.setPreferredOrientations(
        landscape
            ? const [DeviceOrientation.portraitUp]
            : const [
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ],
      ),
    );
    _scheduleHide();
  }

  /// -1 on the left third, +1 on the right third, 0 in the middle.
  static int _sideOf(Offset at, double width) => at.dx < width / 3
      ? -1
      : at.dx > width * 2 / 3
      ? 1
      : 0;

  void _onDoubleTap(TapDownDetails d, double width) {
    final side = _sideOf(d.localPosition, width);
    if (side == 0) {
      _transform.toggleZoom(d.localPosition);
    } else {
      _seek(side);
    }
  }

  /// A tap while a seek is going on: on its side it goes one step further; on the other
  /// side it is the first tap of a count that way, which seeks from the second tap on, as
  /// a double tap does; in the middle it ends the seek and shows or hides the controls as
  /// a tap does.
  void _onStreakTap(TapUpDetails d, double width) {
    final side = _sideOf(d.localPosition, width);
    if (side == 0) {
      _endStreak();
      _toggleControls();
    } else if (side == _streak?.direction) {
      _seek(side);
    } else {
      _countFrom(side);
    }
  }

  /// A finger is held on the picture at [x] of [width]: the video runs faster, or
  /// backwards, until it lifts ([HoldSeek]). Not while the picture is zoomed, where a
  /// held finger is about to drag it, and not on a video too short to seek in.
  void _holdStart(double x, double width) {
    final c = _s.controller;
    if (c == null || !c.value.isInitialized || _hold != null || _zoomed) return;
    final duration = c.value.duration;
    if (duration < HoldSeek.minDuration) return;
    final HoldSeek hold;
    if (duration > HoldSeek.longDuration) {
      final side = _sideOf(Offset(x, 0), width);
      if (side == 0) return;
      hold = HoldSeek.long(forward: side > 0);
    } else {
      hold = HoldSeek.short(x: x, width: width);
    }
    _speedBeforeHold = c.value.playbackSpeed;
    _playedBeforeHold = c.value.isPlaying;
    _holdBack = null;
    _holdTicks = 0;
    setState(() => _hold = hold);
    _applyHold(c);
    _holdTicker = Timer.periodic(_holdTick, (_) => _onHoldTick());
  }

  static const _holdTick = Duration(milliseconds: 100);

  void _holdMove(double x) {
    final hold = _hold;
    final c = _s.controller;
    if (hold == null || c == null || hold.long) return;
    final before = hold.speed;
    hold.slideTo(x);
    if (hold.speed == before) return;
    setState(() {});
    _applyHold(c);
  }

  /// Makes the player do what the hold says: run at its speed, or stand still while the
  /// stage walks it backwards.
  void _applyHold(VideoPlayerController c) {
    final speed = _hold!.speed;
    if (speed > 0) {
      final back = _holdBack;
      _holdBack = null;
      if (back != null) unawaited(c.seekTo(back));
      unawaited(c.setPlaybackSpeed(speed * _speedBeforeHold));
      if (!c.value.isPlaying) unawaited(_s.play());
    } else if (_holdBack == null) {
      _holdBack = c.value.position;
      unawaited(c.setPlaybackSpeed(_speedBeforeHold));
      unawaited(_s.pause());
    }
  }

  void _onHoldTick() {
    final hold = _hold;
    final c = _s.controller;
    if (hold == null || c == null || !mounted) return;
    _holdTicks++;
    // A long video goes a step faster every two seconds.
    final perStep =
        HoldSeek.stepEvery.inMilliseconds ~/ _holdTick.inMilliseconds;
    if (hold.long && _holdTicks % perStep == 0 && hold.nextStep()) {
      setState(() {});
      if (hold.speed > 0) _applyHold(c);
    }
    final back = _holdBack;
    if (back == null) return;
    // Backwards: the place moves, and the player is sent after it every few ticks, as
    // often as it can keep up with.
    var to = back - _holdTick * (-hold.speed * _speedBeforeHold);
    if (to < Duration.zero) to = Duration.zero;
    _holdBack = to;
    if (to == Duration.zero) {
      _holdEnd();
    } else if (_holdTicks % (hold.long ? 4 : 2) == 0) {
      unawaited(c.seekTo(to));
    }
  }

  void _holdEnd() {
    if (_hold == null) return;
    _holdTicker?.cancel();
    _holdTicker = null;
    final c = _s.controller;
    final back = _holdBack;
    _holdBack = null;
    setState(() => _hold = null);
    if (c == null) return;
    if (back != null) unawaited(c.seekTo(back));
    // The video goes on as it was before the finger came down. Last, the speed: it is
    // what the hold changed first.
    if (_playedBeforeHold != c.value.isPlaying) {
      unawaited(_playedBeforeHold ? _s.play() : _s.pause());
    }
    unawaited(c.setPlaybackSpeed(_speedBeforeHold));
  }

  /// One more step towards [direction]. A seek counts from where it began, not from the
  /// player's position, which lags behind while the player is still seeking.
  void _seek(int direction) {
    final c = _s.controller;
    if (c == null || !c.value.isInitialized) return;
    final streak = _streak;
    final next = streak != null && streak.direction == direction
        ? streak.next()
        : _SeekStreak(direction: direction, from: _start(c.value));
    unawaited(c.seekTo(next.target(c.value.duration)));
    _keep(next);
  }

  /// The first tap of a count towards [direction] while a seek the other way goes on.
  void _countFrom(int direction) {
    final c = _s.controller;
    if (c == null || !c.value.isInitialized) return;
    _keep(_SeekStreak(direction: direction, from: _start(c.value), steps: 0));
  }

  /// Where a new seek begins: where the running one is going, otherwise the position.
  Duration _start(VideoPlayerValue v) =>
      _streak?.target(v.duration) ?? v.position;

  void _keep(_SeekStreak streak) {
    _streakEnd?.cancel();
    setState(() => _streak = streak);
    _streakEnd = Timer(_streakWindow, _endStreak);
  }

  void _endStreak() {
    _streakEnd?.cancel();
    if (mounted && _streak != null) setState(() => _streak = null);
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
            onTapUp: ready ? (d) => _lastTapUp = d : null,
            onTap: ready ? _onTap : null,
            onDoubleTapDown: ready ? (d) => _lastDoubleTap = d : null,
            onDoubleTap: ready
                ? () => _onDoubleTap(_lastDoubleTap!, box.maxWidth)
                : null,
            onLongPressStart: ready
                ? (d) => _holdStart(d.localPosition.dx, box.maxWidth)
                : null,
            onLongPressMoveUpdate: ready
                ? (d) => _holdMove(d.localPosition.dx)
                : null,
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
          // While a seek goes on, every tap counts at once: under the double-tap detector
          // the third tap would wait for a fourth and the two would make one step.
          if (_streak != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => _onStreakTap(d, box.maxWidth),
            ),
          if (ready && _controls) const IgnorePointer(child: _Scrim()),
          if (!ready || c.value.isBuffering)
            const IgnorePointer(
              child: Center(
                child: CircularProgressIndicator(color: Colors.white70),
              ),
            ),
          if (_streak case final streak? when streak.steps > 0)
            IgnorePointer(
              child: _SeekHint(
                direction: streak.direction,
                seconds: _seekStep.inSeconds * streak.steps,
              ),
            ),
          if (_hold case final hold?)
            IgnorePointer(child: _HoldHint(speed: hold.speed)),
          // The words of the post go with the controls: a tap takes both off the picture.
          // They lie under the bar, so that the band behind them never covers its slider.
          if (widget.caption.isNotEmpty && (!ready || _controls))
            ViewerCaption(
              text: widget.caption,
              entities: widget.entities,
              onOpenLink: widget.onOpenLink,
              gateway: _s.gateway,
              bottomInset: ready ? _barHeight : 0,
            ),
          if (ready && _controls) SafeArea(child: _overlay(c)),
          // Leaving must work while the video still loads, too.
          if (!ready || _controls)
            ViewerTopBar(title: widget.title, actions: widget.actions),
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
                  context.l10n.videoCannotPlay(message),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
              TextButton(
                onPressed: _s.retry,
                child: Text(context.l10n.commonTryAgain),
              ),
            ],
          ),
        ),
        ViewerTopBar(title: widget.title, actions: widget.actions),
      ],
    ),
  );

  Widget _overlay(VideoPlayerController c) {
    final l10n = context.l10n;
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
              tooltip: v.isPlaying ? l10n.playerPause : l10n.playerPlay,
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
                      onChanged: (x) {
                        setState(() => _scrub = x);
                        _showFrameAt(c, x);
                      },
                      onChangeEnd: (x) async {
                        await c.seekTo(Duration(milliseconds: x.round()));
                        if (mounted) setState(() => _scrub = null);
                        _scheduleHide();
                      },
                    ),
                  ),
                ),
                // Dark, like the menu beside it: a white card over the black stage.
                Theme(
                  data: ThemeData.dark(),
                  child: PopupMenuButton<double>(
                    tooltip: l10n.playerSpeed,
                    icon: const Icon(Icons.speed, color: Colors.white),
                    initialValue: v.playbackSpeed,
                    onSelected: c.setPlaybackSpeed,
                    itemBuilder: (context) => [
                      // Any speed between the slowest and the fastest, as the
                      // official menu's slider; the video follows the drag.
                      PopupMenuItem(
                        enabled: false,
                        padding: EdgeInsets.zero,
                        child: SpeedSlider(
                          speed: v.playbackSpeed,
                          onChanged: c.setPlaybackSpeed,
                        ),
                      ),
                      for (final speed in SpeedSlider.choices)
                        PopupMenuItem(
                          value: speed,
                          child: Text(speedLabel(speed)),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: _s.muted ? l10n.videoSoundOn : l10n.videoSoundOff,
                  icon: Icon(_s.muted ? Icons.volume_off : Icons.volume_up),
                  onPressed: () => _s.setMuted(!_s.muted),
                ),
                // A video that is wider than tall can be laid on its side without
                // turning the phone, as in the official viewer.
                if (v.size.width > v.size.height)
                  IconButton(
                    tooltip: l10n.viewerRotate,
                    icon: const Icon(Icons.screen_rotation),
                    onPressed: _rotate,
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
/// The words of the post under the picture, over a dark band so they stay readable, as the
/// official app shows a caption in its viewer.
class ViewerCaption extends StatelessWidget {
  const ViewerCaption({
    super.key,
    required this.text,
    this.entities = const [],
    this.onOpenLink,
    this.gateway,
    this.bottomInset = 0,
  });
  final String text;

  /// The post's formatting. With it the words are drawn as the timeline draws them, on
  /// the dark band; without it only the links the words spell out are links.
  final List<TextEntity> entities;
  final void Function(String url)? onOpenLink;

  /// Fetches the custom emoji of the caption.
  final TelegramGateway? gateway;

  /// Room under the words for the player's bar, so the two never lie on each other.
  final double bottomInset;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomCenter,
    // The band lies across the picture: one line of words would otherwise sit in the
    // middle of the screen on a dark patch of its own.
    child: SizedBox(
      width: double.infinity,
      child: Stack(
        children: [
          // Only the words take touches: the band lets a tap through to the picture
          // and a drag through to the player's slider.
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 24, 16, 12 + bottomInset),
              child: ConstrainedBox(
                // A long post scrolls inside the band instead of covering the picture.
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.3,
                ),
                child: SingleChildScrollView(
                  child: entities.isEmpty
                      ? _CaptionText(text: text)
                      // The viewer is dark whatever the app's theme is: the colours of
                      // links, code and quotes are the dark theme's.
                      : Theme(
                          data: ThemeData(
                            colorSchemeSeed: Colors.blue,
                            brightness: Brightness.dark,
                            useMaterial3: true,
                          ),
                          child: FormattedText(
                            text: text,
                            entities: entities,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                            onOpenLink:
                                onOpenLink ??
                                (url) =>
                                    unawaited(launchFirst([Uri.tryParse(url)])),
                            gateway: gateway,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class ViewerTopBar extends StatelessWidget {
  const ViewerTopBar({super.key, this.title, this.actions = const []});

  /// The channel and the day, which take whatever width the buttons leave.
  final Widget? title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
        child: Row(
          children: [
            const BackButton(color: Colors.white),
            if (title case final title?)
              Expanded(child: title)
            else
              const Spacer(),
            ...actions,
          ],
        ),
      ),
    ),
  );
}

/// One line of the viewer's overflow menu.
class ViewerAction {
  const ViewerAction(this.label, this.onSelected);
  final String label;
  final VoidCallback onSelected;
}

/// What the top bar has no room for, behind the three dots the official viewer has there.
/// Dark like the rest of the viewer's chrome, whatever theme the app is in.
class ViewerMenu extends StatelessWidget {
  const ViewerMenu({super.key, required this.actions});

  /// Asked when the menu opens, so that a line says what it does at that moment (a
  /// download that is running offers to stop).
  final List<ViewerAction> Function() actions;

  @override
  Widget build(BuildContext context) => actions().isEmpty
      // Nothing to offer: a picture of a channel that protects its content.
      ? const SizedBox.shrink()
      : Theme(
          data: ThemeData.dark(),
          child: PopupMenuButton<VoidCallback>(
            tooltip: context.l10n.commonMore,
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (selected) => selected(),
            itemBuilder: (context) => [
              for (final a in actions())
                PopupMenuItem(value: a.onSelected, child: Text(a.label)),
            ],
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

/// Shown at the top while a held finger runs the video faster or backwards: the speed,
/// and which way.
class _HoldHint extends StatelessWidget {
  const _HoldHint({required this.speed});
  final double speed;

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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (speed < 0) ...[
              const Icon(Icons.fast_rewind, color: Colors.white, size: 18),
              const SizedBox(width: 4),
            ],
            Text(
              speedLabel(speed.abs()),
              style: const TextStyle(color: Colors.white),
            ),
            if (speed >= 0) ...[
              const SizedBox(width: 4),
              const Icon(Icons.fast_forward, color: Colors.white, size: 18),
            ],
          ],
        ),
      ),
    ),
  );
}

/// The slider on top of the speed menu: any speed from the slowest to the fastest, with
/// the speed it stands on beside it. The video follows it while it is dragged.
class SpeedSlider extends StatefulWidget {
  const SpeedSlider({super.key, required this.speed, required this.onChanged});
  final double speed;
  final ValueChanged<double> onChanged;

  /// The ends of the slider, as the official menu's.
  static const min = 0.2;
  static const max = 2.5;

  /// The speeds the menu names under the slider.
  static const choices = [0.2, 0.5, 1.0, 1.5, 2.0];

  @override
  State<SpeedSlider> createState() => _SpeedSliderState();
}

class _SpeedSliderState extends State<SpeedSlider> {
  late double _speed = widget.speed.clamp(SpeedSlider.min, SpeedSlider.max);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 12),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 150,
          child: Slider(
            min: SpeedSlider.min,
            max: SpeedSlider.max,
            value: _speed,
            semanticFormatterCallback: speedLabel,
            onChanged: (v) {
              // In tenths, as the label says it.
              final speed = (v * 10).round() / 10;
              if (speed == _speed) return;
              setState(() => _speed = speed);
              widget.onChanged(speed);
            },
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            speedLabel(_speed),
            textAlign: TextAlign.end,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ],
    ),
  );
}

/// Double taps on one side and the taps that follow them: where the seek began and how
/// many steps it has gone; none yet after the first tap on the other side.
class _SeekStreak {
  const _SeekStreak({
    required this.direction,
    required this.from,
    this.steps = 1,
  });
  final int direction;
  final Duration from;
  final int steps;

  _SeekStreak next() =>
      _SeekStreak(direction: direction, from: from, steps: steps + 1);

  /// Where the steps lead, within the video.
  Duration target(Duration duration) {
    final to = from + _seekStep * (steps * direction);
    if (to < Duration.zero) return Duration.zero;
    return to > duration ? duration : to;
  }
}

/// The seconds a seek has gone so far.
class _SeekHint extends StatelessWidget {
  const _SeekHint({required this.direction, required this.seconds});
  final int direction;
  final int seconds;

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
            context.l10n.videoSeekSeconds(seconds),
            style: const TextStyle(color: Colors.white),
          ),
        ],
      ),
    ),
  );
}

/// The words under a picture, with their links tappable: a caption is the text of a post
/// and its links lead somewhere, as they do in the timeline.
class _CaptionText extends StatefulWidget {
  const _CaptionText({required this.text});
  final String text;

  @override
  State<_CaptionText> createState() => _CaptionTextState();
}

class _CaptionTextState extends State<_CaptionText> {
  final _recognizers = <TapGestureRecognizer>[];

  static final _url = RegExp(
    r'(https?://[^\s]+)|(?:^|\s)(t\.me/[^\s]+)',
    caseSensitive: false,
  );

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    const style = TextStyle(color: Colors.white, fontSize: 14);
    final spans = <InlineSpan>[];
    var at = 0;
    for (final m in _url.allMatches(widget.text)) {
      final url = m.group(1) ?? m.group(2)!;
      final start = widget.text.indexOf(url, m.start);
      if (start > at) {
        spans.add(TextSpan(text: widget.text.substring(at, start)));
      }
      final target = url.startsWith('http') ? url : 'https://$url';
      final recognizer = TapGestureRecognizer()
        ..onTap = () => unawaited(launchFirst([Uri.tryParse(target)]));
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: url,
          style: const TextStyle(
            color: Color(0xFF8FC7FF),
            decoration: TextDecoration.underline,
            decorationColor: Color(0xFF8FC7FF),
          ),
          recognizer: recognizer,
        ),
      );
      at = start + url.length;
    }
    if (at < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(at)));
    }
    return Text.rich(TextSpan(style: style, children: spans));
  }
}
