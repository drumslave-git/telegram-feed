import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../media/media_viewer.dart' show MediaViewerScreen;
import '../service/reading_now.dart';

/// Keeps a banner under the header of every screen while a post is read aloud (Stop, Stop
/// and clear queue) or while notifications are paused (Resume). It is the app's
/// [ScaffoldMessenger]'s material banner, which every screen's [Scaffold] shows below its
/// app bar. Reading wins while both hold: Listen still reads during a pause. The words
/// follow the state without the banner being shown again; it comes and goes only when
/// what it is about changes. The full-screen viewer has the whole screen, so the banner
/// waits under it.
class StatusBannerHost extends StatefulWidget {
  const StatusBannerHost({
    super.key,
    required this.reading,
    required this.paused,
    required this.onStop,
    required this.onResume,
    required this.child,
  });

  final ValueListenable<ReadingNow?> reading;
  final ValueListenable<bool> paused;
  final void Function({required bool clear}) onStop;
  final VoidCallback onResume;
  final Widget child;

  @override
  State<StatusBannerHost> createState() => _StatusBannerHostState();
}

enum _Banner { none, reading, paused }

class _StatusBannerHostState extends State<StatusBannerHost> {
  _Banner _shown = _Banner.none;
  late final Listenable _state = Listenable.merge([
    widget.reading,
    widget.paused,
    MediaViewerScreen.showing,
  ]);

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

  _Banner get _wanted {
    if (MediaViewerScreen.showing.value > 0) return _Banner.none;
    if (widget.reading.value != null) return _Banner.reading;
    if (widget.paused.value) return _Banner.paused;
    return _Banner.none;
  }

  void _update() {
    if (!mounted) return;
    final wanted = _wanted;
    if (wanted == _shown) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    _shown = wanted;
    messenger.removeCurrentMaterialBanner();
    switch (wanted) {
      case _Banner.none:
        break;
      case _Banner.reading:
        messenger.showMaterialBanner(_readingBanner());
      case _Banner.paused:
        messenger.showMaterialBanner(_pausedBanner());
    }
  }

  MaterialBanner _readingBanner() => MaterialBanner(
    leading: const Icon(Icons.record_voice_over_outlined),
    content: ValueListenableBuilder<ReadingNow?>(
      valueListenable: widget.reading,
      builder: (context, now, _) =>
          Text(readingLine(now), maxLines: 2, overflow: TextOverflow.ellipsis),
    ),
    actions: [
      TextButton(
        onPressed: () => widget.onStop(clear: false),
        child: const Text('Stop'),
      ),
      TextButton(
        onPressed: () => widget.onStop(clear: true),
        child: const Text('Stop and clear queue'),
      ),
    ],
  );

  MaterialBanner _pausedBanner() => MaterialBanner(
    leading: const Icon(Icons.notifications_off_outlined),
    content: const Text(
      'Notifications are paused. Rules notify about nothing and read nothing aloud.',
    ),
    actions: [
      TextButton(onPressed: widget.onResume, child: const Text('Resume')),
    ],
  );

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The banner's words for [now]: the channel being read, and how many posts wait.
String readingLine(ReadingNow? now) {
  if (now == null) return '';
  final channel = now.channelTitle.isEmpty
      ? 'Reading aloud'
      : 'Reading aloud: ${now.channelTitle}';
  return switch (now.waiting) {
    0 => channel,
    1 => '$channel. 1 more post waits.',
    final n => '$channel. $n more posts wait.',
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
      tooltip: on ? 'Resume notifications' : 'Pause notifications',
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
