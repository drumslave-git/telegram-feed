import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';

import 'media_view.dart' show formatDuration;

/// Play/pause with position for a downloaded audio file (voice messages, music).
class AudioPlayerWidget extends StatefulWidget {
  const AudioPlayerWidget({
    super.key,
    required this.path,
    required this.label,
    required this.durationSeconds,
  });
  final String path;
  final String label;
  final int durationSeconds;

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  final _player = AudioPlayer();
  String? _error;

  @override
  void initState() {
    super.initState();
    _player.setFilePath(widget.path).then((_) => _player.play()).catchError((
      Object e,
    ) {
      if (mounted) setState(() => _error = '$e');
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Text('Cannot play: $_error');
    return StreamBuilder<PlayerState>(
      stream: _player.playerStateStream,
      builder: (context, state) {
        final playing = state.data?.playing ?? false;
        final done = state.data?.processingState == ProcessingState.completed;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: IconButton.filled(
            tooltip: playing && !done ? 'Pause' : 'Play',
            onPressed: () {
              if (done) {
                _player.seek(Duration.zero);
                _player.play();
              } else if (playing) {
                _player.pause();
              } else {
                _player.play();
              }
            },
            icon: Icon(playing && !done ? Icons.pause : Icons.play_arrow),
          ),
          title: Text(widget.label),
          subtitle: StreamBuilder<Duration>(
            stream: _player.positionStream,
            builder: (context, pos) {
              final total =
                  _player.duration?.inSeconds ?? widget.durationSeconds;
              final p = pos.data?.inSeconds ?? 0;
              return Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: total > 0 ? (p / total).clamp(0, 1) : 0,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${formatDuration(p)} / ${formatDuration(total)}'),
                ],
              );
            },
          ),
        );
      },
    );
  }
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
