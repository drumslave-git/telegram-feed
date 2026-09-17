import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';

import 'media_view.dart' show formatDuration;

/// Inline video for a downloaded file. Starts playing immediately; tap toggles pause.
class VideoPlayerWidget extends StatefulWidget {
  const VideoPlayerWidget({super.key, required this.path, this.loop = false});
  final String path;
  final bool loop;

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late final VideoPlayerController _ctl = VideoPlayerController.file(
    File(widget.path),
  );
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _ctl.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _ctl.setLooping(widget.loop);
      _ctl.play();
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const ColoredBox(
        color: Colors.black87,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return GestureDetector(
      onTap: () =>
          setState(() => _ctl.value.isPlaying ? _ctl.pause() : _ctl.play()),
      child: Stack(
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: _ctl.value.size.width,
              height: _ctl.value.size.height,
              child: VideoPlayer(_ctl),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: VideoProgressIndicator(_ctl, allowScrubbing: true),
          ),
        ],
      ),
    );
  }
}

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
