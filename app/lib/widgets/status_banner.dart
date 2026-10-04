import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../media/audio_bar.dart';
import '../media/audio_session.dart';
import '../media/media_viewer.dart' show MediaViewerScreen;
import '../service/reading_now.dart';

/// Keeps a banner under the header of every screen while a post is read aloud (Stop, Stop
/// and clear queue), while notifications are paused (Resume), and while a voice message
/// or music plays (the [AudioBar], as the official app keeps its player bar under the
/// header). It is the app's [ScaffoldMessenger]'s material banner, which every screen's
/// [Scaffold] shows below its app bar; there is one such banner at a time, so the audio
/// bar and the line about reading or the pause share it, the bar on top. Reading wins
/// over the pause while both hold: Listen still reads during a pause. The words follow
/// the state without the banner being shown again; it comes and goes only when what it
/// is about changes. The full-screen viewer has the whole screen, so the banner waits
/// under it.
class StatusBannerHost extends StatefulWidget {
  const StatusBannerHost({
    super.key,
    required this.reading,
    required this.paused,
    required this.onStop,
    required this.onResume,
    required this.child,
    this.audio,
  });

  /// The app's one sound; tests hand in their own.
  final AudioSessions? audio;

  final ValueListenable<ReadingNow?> reading;
  final ValueListenable<bool> paused;
  final void Function({required bool clear}) onStop;
  final VoidCallback onResume;
  final Widget child;

  /// Roughly how much room the banner takes under the header right now, 0 without one:
  /// what floats in the corner under the header (the round video's window) stays below
  /// it. An estimate from what the banner holds, since the banner itself is built inside
  /// each screen's scaffold.
  static final heightUnderHeader = ValueNotifier<double>(0);

  @override
  State<StatusBannerHost> createState() => _StatusBannerHostState();
}

enum _Banner { none, reading, paused }

class _StatusBannerHostState extends State<StatusBannerHost> {
  ({_Banner status, bool audio}) _shown = (status: _Banner.none, audio: false);
  late AudioSessions _audio = widget.audio ?? AudioSessions.instance;
  late Listenable _state = _watched();

  Listenable _watched() => Listenable.merge([
    widget.reading,
    widget.paused,
    _audio.track,
    MediaViewerScreen.showing,
  ]);

  /// Another account took over: its host has notifiers of its own, and the banner has
  /// to say what holds there, not what held for the account that was left.
  @override
  void didUpdateWidget(StatusBannerHost old) {
    super.didUpdateWidget(old);
    if (identical(old.reading, widget.reading) &&
        identical(old.paused, widget.paused) &&
        identical(old.audio, widget.audio)) {
      return;
    }
    _state.removeListener(_update);
    _audio = widget.audio ?? AudioSessions.instance;
    _state = _watched()..addListener(_update);
    // The banner in place may show the other account's words through its own
    // listeners: it is put up again.
    _shown = (status: _Banner.none, audio: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.removeCurrentMaterialBanner();
      _update();
    });
  }

  @override
  void initState() {
    super.initState();
    _state.addListener(_update);
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  @override
  void dispose() {
    _state.removeListener(_update);
    super.dispose();
  }

  ({_Banner status, bool audio}) get _wanted {
    if (MediaViewerScreen.showing.value > 0) {
      return (status: _Banner.none, audio: false);
    }
    return (
      status: widget.reading.value != null
          ? _Banner.reading
          : widget.paused.value
          ? _Banner.paused
          : _Banner.none,
      audio: _audio.track.value != null,
    );
  }

  void _update() {
    if (!mounted) return;
    final wanted = _wanted;
    if (wanted == _shown) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    _shown = wanted;
    StatusBannerHost.heightUnderHeader.value =
        (wanted.audio ? 52.0 : 0.0) +
        switch (wanted.status) {
          _Banner.none => 0.0,
          // Two lines of words with the button beside them, or under them when the
          // audio bar shares the banner.
          _Banner.paused => wanted.audio ? 100.0 : 60.0,
          _Banner.reading => 112.0,
        };
    messenger.removeCurrentMaterialBanner();
    if (wanted.audio) {
      messenger.showMaterialBanner(_audioBanner(wanted.status));
      return;
    }
    switch (wanted.status) {
      case _Banner.none:
        break;
      case _Banner.reading:
        messenger.showMaterialBanner(_readingBanner());
      case _Banner.paused:
        messenger.showMaterialBanner(_pausedBanner());
    }
  }

  /// The audio bar, and under it the line about reading or the pause when one holds.
  MaterialBanner _audioBanner(_Banner status) => MaterialBanner(
    padding: EdgeInsets.zero,
    leadingPadding: EdgeInsets.zero,
    minActionBarHeight: 0,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ValueListenableBuilder<AudioTrack?>(
          valueListenable: _audio.track,
          // The track changes under the bar as the queue plays on.
          builder: (context, track, _) => track == null
              ? const SizedBox(height: 52)
              : AudioBar(track: track, sessions: _audio),
        ),
        if (status == _Banner.reading)
          _line(
            Icons.record_voice_over_outlined,
            ValueListenableBuilder<ReadingNow?>(
              valueListenable: widget.reading,
              builder: (context, now, _) => Text(
                readingLine(now, context.l10n),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            [
              TextButton(
                onPressed: () => widget.onStop(clear: false),
                child: Builder(
                  builder: (context) => Text(context.l10n.bannerStop),
                ),
              ),
              TextButton(
                onPressed: () => widget.onStop(clear: true),
                child: Builder(
                  builder: (context) =>
                      Text(context.l10n.bannerStopAndClearQueue),
                ),
              ),
            ],
          ),
        if (status == _Banner.paused)
          _line(
            Icons.notifications_off_outlined,
            Builder(builder: (context) => Text(context.l10n.bannerPaused)),
            [
              TextButton(
                onPressed: widget.onResume,
                child: Builder(
                  builder: (context) => Text(context.l10n.bannerResume),
                ),
              ),
            ],
          ),
      ],
    ),
    // A banner must have one; the bar carries its own buttons.
    actions: const [SizedBox.shrink()],
  );

  /// A line of the shared banner: what it is about, and its buttons under the words.
  Widget _line(IconData icon, Widget words, List<Widget> actions) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon),
            const SizedBox(width: 16),
            Expanded(child: words),
          ],
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Wrap(children: actions),
        ),
      ],
    ),
  );

  MaterialBanner _readingBanner() => MaterialBanner(
    leading: const Icon(Icons.record_voice_over_outlined),
    content: ValueListenableBuilder<ReadingNow?>(
      valueListenable: widget.reading,
      builder: (context, now, _) => Text(
        readingLine(now, context.l10n),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => widget.onStop(clear: false),
        child: Builder(builder: (context) => Text(context.l10n.bannerStop)),
      ),
      TextButton(
        onPressed: () => widget.onStop(clear: true),
        child: Builder(
          builder: (context) => Text(context.l10n.bannerStopAndClearQueue),
        ),
      ),
    ],
  );

  MaterialBanner _pausedBanner() => MaterialBanner(
    leading: const Icon(Icons.notifications_off_outlined),
    content: Builder(builder: (context) => Text(context.l10n.bannerPaused)),
    actions: [
      TextButton(
        onPressed: widget.onResume,
        child: Builder(builder: (context) => Text(context.l10n.bannerResume)),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The banner's words for [now]: the channel being read, and how many posts wait.
String readingLine(ReadingNow? now, AppLocalizations l10n) {
  if (now == null) return '';
  final channel = now.channelTitle.isEmpty
      ? l10n.bannerReadingAloud
      : l10n.bannerReadingAloudChannel(now.channelTitle);
  return switch (now.waiting) {
    0 => channel,
    final n => l10n.bannerReadingQueue(channel, n),
  };
}

/// The kill switch in the home screen's header: one tap silences every rule, one tap
/// brings them back. While paused the bell is filled and red, and the banner says so.
class PauseButton extends StatelessWidget {
  const PauseButton({super.key, required this.paused, required this.onChanged});
  final ValueListenable<bool> paused;
  final Future<void> Function(bool paused) onChanged;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: paused,
    builder: (context, on, _) => IconButton(
      tooltip: on
          ? context.l10n.bannerResumeNotifications
          : context.l10n.bannerPauseNotifications,
      isSelected: on,
      icon: const Icon(Icons.notifications_off_outlined),
      selectedIcon: Icon(
        Icons.notifications_off,
        color: Theme.of(context).colorScheme.error,
      ),
      onPressed: () => unawaited(onChanged(!on)),
    ),
  );
}
