import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../feeds/open_links.dart';

import 'package:video_player/video_player.dart';

import '../feeds/media_view.dart' show formatDuration;
import '../l10n/l10n.dart';
import 'video_sessions.dart';
import 'zoom.dart';

const _seekStep = Duration(seconds: 10);

/// How long after a seek's last tap the next one still adds a step.
const _streakWindow = Duration(milliseconds: 700);
const _holdSpeed = 2.0;

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
    this.poster,
    this.title,
    this.actions = const [],
    this.onZoomChanged,
  });
  final VideoSession session;

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
    _streakEnd?.cancel();
    _transform.dispose();
    final before = _speedBeforeHold;
    if (before != null) unawaited(_s.controller?.setPlaybackSpeed(before));
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
          if (_speedBeforeHold != null) const IgnorePointer(child: _HoldHint()),
          // The words of the post go with the controls: a tap takes both off the picture.
          // They lie under the bar, so that the band behind them never covers its slider.
          if (widget.caption.isNotEmpty && (!ready || _controls))
            ViewerCaption(
              text: widget.caption,
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
                      onChanged: (x) => setState(() => _scrub = x),
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
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 0.5, child: Text('0.5×')),
                      PopupMenuItem(value: 1.0, child: Text('1×')),
                      PopupMenuItem(value: 1.5, child: Text('1.5×')),
                      PopupMenuItem(value: 2.0, child: Text('2×')),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: _s.muted ? l10n.videoSoundOn : l10n.videoSoundOff,
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
/// The words of the post under the picture, over a dark band so they stay readable, as the
/// official app shows a caption in its viewer.
class ViewerCaption extends StatelessWidget {
  const ViewerCaption({super.key, required this.text, this.bottomInset = 0});
  final String text;

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
                child: SingleChildScrollView(child: _CaptionText(text: text)),
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
