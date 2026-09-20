import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../media/audio_session.dart';
import 'media_view.dart' show formatDuration;

/// A voice message or a music file in a post: play or pause, a bar that can be dragged to
/// seek, the position and length, and the official app's speed button (1x, 1.5x, 2x). The
/// sound itself lives in [AudioSessions], so it keeps playing when the post scrolls away.
class AudioPlayerWidget extends StatefulWidget {
  const AudioPlayerWidget({
    super.key,
    required this.path,
    required this.label,
    required this.durationSeconds,
    this.sessions,
  });

  final String path;
  final String label;
  final int durationSeconds;

  /// Tests hand in their own; the app uses the one session it has.
  final AudioSessions? sessions;

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  AudioSessions get _sessions => widget.sessions ?? AudioSessions.instance;

  @override
  void initState() {
    super.initState();
    // The post asked for it: start at once, as it did before.
    unawaited(
      _sessions.play(
        AudioTrack(
          path: widget.path,
          label: widget.label,
          durationSeconds: widget.durationSeconds,
        ),
      ),
    );
  }

  Duration get _length {
    final own = Duration(seconds: widget.durationSeconds);
    if (!_sessions.isCurrent(widget.path)) return own;
    final known = _sessions.length;
    return known > Duration.zero ? known : own;
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AudioTrack?>(
    valueListenable: _sessions.track,
    builder: (context, track, _) {
      final mine = track?.path == widget.path;
      final error = mine ? _sessions.error.value : null;
      if (error != null) return Text('Cannot play: $error');
      return ValueListenableBuilder<bool>(
        valueListenable: _sessions.playing,
        builder: (context, playing, _) => ValueListenableBuilder<Duration>(
          valueListenable: _sessions.position,
          builder: (context, position, _) {
            final at = mine ? position : Duration.zero;
            final length = _length;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: IconButton.filled(
                tooltip: mine && playing ? 'Pause' : 'Play',
                onPressed: () => unawaited(
                  mine
                      ? _sessions.toggle()
                      : _sessions.play(
                          AudioTrack(
                            path: widget.path,
                            label: widget.label,
                            durationSeconds: widget.durationSeconds,
                          ),
                        ),
                ),
                icon: Icon(mine && playing ? Icons.pause : Icons.play_arrow),
              ),
              title: Text(widget.label),
              subtitle: Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: length.inMilliseconds == 0
                          ? 0
                          : at.inMilliseconds
                                .clamp(0, length.inMilliseconds)
                                .toDouble(),
                      max: length.inMilliseconds == 0
                          ? 1
                          : length.inMilliseconds.toDouble(),
                      onChanged: length.inMilliseconds == 0
                          ? null
                          : (v) => unawaited(
                              _sessions.seek(Duration(milliseconds: v.round())),
                            ),
                    ),
                  ),
                  Text(
                    '${formatDuration(at.inSeconds)} / '
                    '${formatDuration(length.inSeconds)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  ValueListenableBuilder<double>(
                    valueListenable: _sessions.speed,
                    builder: (context, speed, _) => TextButton(
                      onPressed: () => unawaited(_sessions.nextSpeed()),
                      child: Text(
                        '${speed == speed.roundToDouble() ? speed.toStringAsFixed(0) : speed}x',
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    },
  );
}

/// A small silent video that plays over and over: WebM stickers and animated emoji. No
/// controls, nothing to tap — as in the official app.
class LoopingVideo extends StatefulWidget {
  const LoopingVideo({
    super.key,
    required this.path,
    required this.width,
    required this.height,
  });
  final String path;
  final double width;
  final double height;

  @override
  State<LoopingVideo> createState() => _LoopingVideoState();
}

class _LoopingVideoState extends State<LoopingVideo> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    final c = VideoPlayerController.file(File(widget.path));
    try {
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0);
      await c.play();
    } on Object {
      await c.dispose();
      return;
    }
    if (!mounted) {
      await c.dispose();
      return;
    }
    setState(() => _controller = c);
  }

  @override
  void dispose() {
    unawaited(_controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: c == null ? const SizedBox.shrink() : VideoPlayer(c),
    );
  }
}
