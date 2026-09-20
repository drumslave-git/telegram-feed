import 'dart:async';

import 'package:flutter/material.dart';

import '../feeds/media_view.dart' show formatDuration;
import 'audio_session.dart';

/// Keeps the player bar under every screen while something plays, the way the official app
/// keeps its music bar. The sound itself lives in [AudioSessions] and is not tied to the
/// post it came from, so scrolling away or leaving the screen does not stop it.
class AudioBarHost extends StatelessWidget {
  const AudioBarHost({super.key, required this.child, this.sessions});
  final Widget child;

  /// Tests hand in their own session.
  final AudioSessions? sessions;

  @override
  Widget build(BuildContext context) {
    final s = sessions ?? AudioSessions.instance;
    return ValueListenableBuilder<AudioTrack?>(
      valueListenable: s.track,
      builder: (context, track, _) => Column(
        children: [
          Expanded(child: child),
          if (track != null) AudioBar(track: track, sessions: s),
        ],
      ),
    );
  }
}

/// What is playing, with pause and a cross. A tap on the words does nothing: the post it
/// came from may be pages away, and the official app's bar is a control, not a link.
class AudioBar extends StatelessWidget {
  const AudioBar({super.key, required this.track, required this.sessions});
  final AudioTrack track;
  final AudioSessions sessions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: sessions.playing,
                builder: (context, playing, _) => IconButton(
                  tooltip: playing ? 'Pause' : 'Play',
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                  onPressed: () => unawaited(sessions.toggle()),
                ),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.label.isEmpty ? 'Audio' : track.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    ValueListenableBuilder<Duration>(
                      valueListenable: sessions.position,
                      builder: (context, at, _) => Text(
                        '${formatDuration(at.inSeconds)} / '
                        '${formatDuration(sessions.length.inSeconds)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ValueListenableBuilder<double>(
                valueListenable: sessions.speed,
                builder: (context, speed, _) => TextButton(
                  onPressed: () => unawaited(sessions.nextSpeed()),
                  child: Text(
                    '${speed == speed.roundToDouble() ? speed.toStringAsFixed(0) : speed}x',
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Stop',
                icon: const Icon(Icons.close),
                onPressed: () => unawaited(sessions.stop()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
