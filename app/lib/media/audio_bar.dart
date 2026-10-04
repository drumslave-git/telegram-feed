import 'dart:async';

import 'package:flutter/material.dart';

import '../feeds/media_view.dart' show formatDuration;
import '../l10n/l10n.dart';
import 'audio_session.dart';
import 'video_stage.dart' show SpeedSlider;

/// A speed as the audio rows write it: "1x", "1.5x".
String audioSpeedLabel(double speed) {
  final rounded = (speed * 10).round() / 10;
  return rounded == rounded.roundToDouble()
      ? '${rounded.round()}x'
      : '${rounded.toStringAsFixed(1)}x';
}

/// What is playing, under the header of every screen as in the official app (the
/// `StatusBannerHost` puts it there): pause, the speed and a cross. A tap on the words
/// opens the player for music and goes to the post for a voice message. The sound itself
/// lives in [AudioSessions] and is not tied to the post it came from, so scrolling away
/// or leaving the screen does not stop it.
class AudioBar extends StatelessWidget {
  const AudioBar({super.key, required this.track, required this.sessions});
  final AudioTrack track;
  final AudioSessions sessions;

  void _open(BuildContext context) {
    if (track.isVoice) {
      // The post it was said in, where the timeline that holds it is still there.
      sessions.currentItem?.onShow?.call();
    } else {
      unawaited(showAudioPlayer(context, sessions));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: sessions.playing,
            builder: (context, playing, _) => IconButton(
              tooltip: playing ? l10n.playerPause : l10n.playerPlay,
              icon: Icon(playing ? Icons.pause : Icons.play_arrow),
              onPressed: () => unawaited(sessions.toggle()),
            ),
          ),
          Expanded(
            child: Semantics(
              button: true,
              hint: track.isVoice ? l10n.audioShowPost : l10n.audioOpenPlayer,
              child: InkWell(
                onTap: () => _open(context),
                child: SizedBox(
                  height: 52,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.label.isEmpty ? l10n.mediaAudio : track.label,
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
              ),
            ),
          ),
          AudioSpeedButton(sessions: sessions),
          IconButton(
            tooltip: l10n.audioStop,
            icon: const Icon(Icons.close),
            onPressed: () => unawaited(sessions.stop()),
          ),
        ],
      ),
    );
  }
}

/// The speed of what plays: a tap goes round 1×, 1.5× and 2× as the official app's
/// button does, a long press offers a slider and the speeds from 0.5× to 2×.
class AudioSpeedButton extends StatelessWidget {
  const AudioSpeedButton({super.key, required this.sessions});
  final AudioSessions sessions;

  /// The speeds the menu names, and the ends of its slider.
  static const choices = [0.5, 1.0, 1.5, 2.0];

  Future<void> _menu(BuildContext context) async {
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final at = RelativeRect.fromRect(
      box.localToGlobal(Offset.zero, ancestor: overlay) & box.size,
      Offset.zero & overlay.size,
    );
    final chosen = await showMenu<double>(
      context: context,
      position: at,
      items: [
        PopupMenuItem(
          enabled: false,
          padding: EdgeInsets.zero,
          child: Theme(
            // The menu is the app's own colour, not the viewer's dark one.
            data: Theme.of(context),
            child: SpeedSlider(
              speed: sessions.speed.value,
              min: choices.first,
              max: choices.last,
              label: audioSpeedLabel,
              color: Theme.of(context).colorScheme.onSurface,
              onChanged: (v) => unawaited(sessions.setSpeed(v)),
            ),
          ),
        ),
        for (final speed in choices)
          PopupMenuItem(value: speed, child: Text(audioSpeedLabel(speed))),
      ],
    );
    if (chosen != null) await sessions.setSpeed(chosen);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: sessions.speed,
    builder: (context, speed, _) => Tooltip(
      message: context.l10n.playerSpeed,
      child: TextButton(
        onPressed: () => unawaited(sessions.nextSpeed()),
        onLongPress: () => unawaited(_menu(context)),
        child: Text(audioSpeedLabel(speed)),
      ),
    ),
  );
}

/// Opens the player over the screen: what the bar's words lead to while music plays.
Future<void> showAudioPlayer(BuildContext context, AudioSessions sessions) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => AudioPlayerSheet(sessions: sessions),
    );

/// The player of the music that is on: the piece, a bar to seek on, previous, play and
/// next, repeat and shuffle, the speed, and the list it plays through, where a tap
/// plays another piece.
class AudioPlayerSheet extends StatefulWidget {
  const AudioPlayerSheet({super.key, required this.sessions});
  final AudioSessions sessions;

  @override
  State<AudioPlayerSheet> createState() => _AudioPlayerSheetState();
}

class _AudioPlayerSheetState extends State<AudioPlayerSheet> {
  /// Where the finger holds the thumb while it drags; null otherwise.
  double? _scrub;

  AudioSessions get _s => widget.sessions;

  late final Listenable _state = Listenable.merge([
    _s.track,
    _s.playing,
    _s.position,
    _s.repeat,
    _s.shuffle,
  ]);

  String _repeatLabel(AppLocalizations l10n) => switch (_s.repeat.value) {
    AudioRepeat.off => l10n.audioRepeatOff,
    AudioRepeat.all => l10n.audioRepeatAll,
    AudioRepeat.one => l10n.audioRepeatOne,
  };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _state,
    builder: (context, _) {
      final l10n = context.l10n;
      final theme = Theme.of(context);
      final track = _s.track.value;
      // Nothing plays any more: the sheet has nothing to show.
      if (track == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) Navigator.of(context).maybePop();
        });
        return const SizedBox(height: 120);
      }
      final length = _s.length.inMilliseconds.toDouble();
      final at = (_scrub ?? _s.position.value.inMilliseconds.toDouble()).clamp(
        0.0,
        length <= 0 ? 0.0 : length,
      );
      final queue = _s.queue;
      final on = theme.colorScheme.primary;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  track.label.isEmpty ? l10n.mediaAudio : track.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Slider(
                  value: at,
                  max: length <= 0 ? 1 : length,
                  // The thumb follows the finger; the player seeks once, when it lifts.
                  onChanged: length <= 0
                      ? null
                      : (v) => setState(() => _scrub = v),
                  onChangeEnd: length <= 0
                      ? null
                      : (v) {
                          setState(() => _scrub = null);
                          unawaited(_s.seek(Duration(milliseconds: v.round())));
                        },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      formatDuration(at ~/ 1000),
                      style: theme.textTheme.bodySmall,
                    ),
                    Text(
                      formatDuration(_s.length.inSeconds),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      tooltip: _s.shuffle.value
                          ? l10n.audioShuffleOn
                          : l10n.audioShuffleOff,
                      icon: const Icon(Icons.shuffle),
                      color: _s.shuffle.value ? on : null,
                      onPressed: () => setState(_s.toggleShuffle),
                    ),
                    IconButton(
                      tooltip: l10n.audioPrevious,
                      iconSize: 32,
                      icon: const Icon(Icons.skip_previous),
                      onPressed: () => unawaited(_s.previous()),
                    ),
                    IconButton.filled(
                      tooltip: _s.playing.value
                          ? l10n.playerPause
                          : l10n.playerPlay,
                      iconSize: 36,
                      icon: Icon(
                        _s.playing.value ? Icons.pause : Icons.play_arrow,
                      ),
                      onPressed: () => unawaited(_s.toggle()),
                    ),
                    IconButton(
                      tooltip: l10n.audioNext,
                      iconSize: 32,
                      icon: const Icon(Icons.skip_next),
                      onPressed: _s.hasNext ? () => unawaited(_s.next()) : null,
                    ),
                    IconButton(
                      tooltip: _repeatLabel(l10n),
                      icon: Icon(
                        _s.repeat.value == AudioRepeat.one
                            ? Icons.repeat_one
                            : Icons.repeat,
                      ),
                      color: _s.repeat.value == AudioRepeat.off ? null : on,
                      onPressed: () => setState(_s.nextRepeat),
                    ),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: AudioSpeedButton(sessions: _s),
                ),
              ),
              if (queue.length > 1) ...[
                const Divider(height: 1),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: queue.length,
                    itemBuilder: (context, i) {
                      // The newest on top, as the official player lists them.
                      final item = queue[queue.length - 1 - i];
                      final current = item.id == track.id;
                      return ListTile(
                        dense: true,
                        selected: current,
                        leading: Icon(
                          current ? Icons.graphic_eq : Icons.music_note,
                        ),
                        title: Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(formatDuration(item.durationSeconds)),
                        onTap: current
                            ? null
                            : () => unawaited(_s.playItem(item)),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}
