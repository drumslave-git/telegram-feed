import 'dart:async';

import 'package:flutter/material.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'media_viewer.dart';
import 'video_sessions.dart';
import 'video_stage.dart';

/// Picture-in-picture inside the app: the video of the viewer goes on playing in a small
/// window that floats over the timeline and every other screen, and can be dragged around,
/// opened in the viewer again or closed. One at a time; opening the viewer ends it.
abstract final class MiniPlayer {
  static OverlayEntry? _entry;
  static VideoSession? _session;

  static bool get isShowing => _entry != null;

  /// Takes [session] over from the viewer, which the caller closes afterwards. [items] and
  /// [index] are what the viewer showed, for the way back.
  static void show(
    BuildContext context, {
    required VideoSession session,
    required List<Media> items,
    required int index,
    required TelegramGateway gateway,
  }) {
    dismiss();
    final overlay = Navigator.of(context, rootNavigator: true).overlay;
    if (overlay == null) return;
    _session = session..retainForViewer();
    final entry = _entry = OverlayEntry(
      builder: (context) => _MiniPlayerView(
        session: session,
        onClose: dismiss,
        onExpand: () => unawaited(
          // The viewer takes the session over and dismisses this window once it is up.
          MediaViewerScreen.open(
            context,
            items: items,
            gateway: gateway,
            initialIndex: index,
          ),
        ),
      ),
    );
    overlay.insert(entry);
  }

  /// Hands the session back: unless the viewer holds it by now, the video ends here.
  static void dismiss() {
    final entry = _entry;
    if (entry == null) return;
    _entry = null;
    // Safe when the overlay itself is gone already (the app was torn down around it).
    entry.remove();
    entry.dispose();
    _session?.releaseFromViewer();
    _session = null;
  }
}

class _MiniPlayerView extends StatefulWidget {
  const _MiniPlayerView({
    required this.session,
    required this.onClose,
    required this.onExpand,
  });
  final VideoSession session;
  final VoidCallback onClose;
  final VoidCallback onExpand;

  @override
  State<_MiniPlayerView> createState() => _MiniPlayerViewState();
}

class _MiniPlayerViewState extends State<_MiniPlayerView> {
  static const _margin = 12.0;

  /// Top left corner; null until the first layout puts the window bottom right.
  Offset? _at;

  VideoSession get _s => widget.session;

  @override
  void initState() {
    super.initState();
    _s.addListener(_onSession);
  }

  @override
  void dispose() {
    _s.removeListener(_onSession);
    super.dispose();
  }

  void _onSession() {
    if (!mounted) return;
    // A video that broke has nothing to show in a window without room for an error.
    if (_s.error != null) return scheduleMicrotask(widget.onClose);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screen = media.size;
    final c = _s.controller;
    final ready = c != null && c.value.isInitialized;
    final file = _s.file;
    final aspect =
        (ready
                ? c.value.aspectRatio
                : file.width > 0 && file.height > 0
                ? file.width / file.height
                : 16 / 9)
            .clamp(0.6, 1.8);
    final width = (screen.width * (aspect < 1 ? 0.36 : 0.5)).clamp(
      120.0,
      280.0,
    );
    final size = Size(width, width / aspect);
    final bounds = Rect.fromLTRB(
      _margin + media.padding.left,
      _margin + media.padding.top,
      screen.width - size.width - _margin - media.padding.right,
      screen.height - size.height - _margin - media.padding.bottom,
    );
    final at = _at ?? Offset(bounds.right, bounds.bottom - 72);
    final position = Offset(
      at.dx.clamp(bounds.left, bounds.right),
      at.dy.clamp(bounds.top, bounds.bottom),
    );
    final playing = c?.value.isPlaying ?? false;
    final total = c?.value.duration.inMilliseconds ?? 0;
    return Positioned(
      left: position.dx,
      top: position.dy,
      width: size.width,
      height: size.height,
      child: GestureDetector(
        onTap: _s.togglePlay,
        onPanUpdate: (d) => setState(() => _at = position + d.delta),
        // Rests at the nearer side, as the system's window does.
        onPanEnd: (_) => setState(
          () => _at = Offset(
            position.dx + size.width / 2 < screen.width / 2
                ? bounds.left
                : bounds.right,
            position.dy,
          ),
        ),
        child: Material(
          color: Colors.black,
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: IconTheme(
            data: const IconThemeData(color: Colors.white, size: 20),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (ready)
                  VideoPicture(c)
                else
                  const Center(
                    child: CircularProgressIndicator(color: Colors.white70),
                  ),
                if (ready && !playing)
                  const Center(child: Icon(Icons.play_arrow, size: 40)),
                Align(
                  alignment: Alignment.topCenter,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black54, Colors.transparent],
                      ),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Back to full screen',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.open_in_full),
                          onPressed: widget.onExpand,
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Close',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close),
                          onPressed: widget.onClose,
                        ),
                      ],
                    ),
                  ),
                ),
                if (ready && total > 0)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      value: (c.value.position.inMilliseconds / total).clamp(
                        0.0,
                        1.0,
                      ),
                      color: Colors.white,
                      backgroundColor: Colors.white24,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
