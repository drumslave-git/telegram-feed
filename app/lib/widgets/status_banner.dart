import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../media/media_viewer.dart' show MediaViewerScreen;
import '../service/reading_now.dart';

/// Keeps a banner under the header of every screen while a post is read aloud, with Stop
/// and Stop and clear queue. It is the app's [ScaffoldMessenger]'s material banner, which
/// every screen's [Scaffold] shows below its app bar. The words follow the queue without
/// the banner being shown again; it comes and goes only when reading starts or ends. The
/// full-screen viewer has the whole screen, so the banner waits under it.
class StatusBannerHost extends StatefulWidget {
  const StatusBannerHost({
    super.key,
    required this.reading,
    required this.onStop,
    required this.child,
  });

  final ValueListenable<ReadingNow?> reading;
  final void Function({required bool clear}) onStop;
  final Widget child;

  @override
  State<StatusBannerHost> createState() => _StatusBannerHostState();
}

enum _Banner { none, reading }

class _StatusBannerHostState extends State<StatusBannerHost> {
  _Banner _shown = _Banner.none;
  late final Listenable _state = Listenable.merge([
    widget.reading,
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
