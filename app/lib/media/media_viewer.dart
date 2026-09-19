import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../feeds/media_view.dart' show Downloaded;
import 'swipe_to_close.dart';
import 'video_downloads.dart';
import 'video_sessions.dart';
import 'video_stage.dart';
import 'zoom.dart';

/// The photos and videos of one post on the whole screen, in whatever orientation the device
/// has: swipe sideways through the album, pinch or double tap to zoom, drag down or up to
/// close. The video of the page in front plays with sound; turning the page or leaving hands
/// its session back, which ends playback and streaming unless the video autoplays in its row.
class MediaViewerScreen extends StatefulWidget {
  const MediaViewerScreen({
    super.key,
    required this.items,
    required this.gateway,
    this.initialIndex = 0,
  });

  /// [PhotoMedia] and [VideoMedia] only, see [viewable].
  final List<Media> items;
  final TelegramGateway gateway;
  final int initialIndex;

  /// What of a post's media the viewer can show, in the order of the post.
  static List<Media> viewable(Iterable<Media> media) => [
    for (final m in media)
      if (m is PhotoMedia || m is VideoMedia) m,
  ];

  static Future<void> open(
    BuildContext context, {
    required List<Media> items,
    required TelegramGateway gateway,
    int initialIndex = 0,
  }) => Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      // The timeline shows through while the page is dragged away.
      opaque: false,
      pageBuilder: (_, _, _) => MediaViewerScreen(
        items: items,
        gateway: gateway,
        initialIndex: initialIndex,
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  late final _pages = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  /// Paging and swipe-to-close are off while a page is zoomed in, so a drag pans it instead.
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _pages.dispose();
    super.dispose();
  }

  void _onZoom(bool zoomed) {
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final counter = items.length > 1
        ? Text(
            '${_index + 1} of ${items.length}',
            style: const TextStyle(color: Colors.white, fontSize: 16),
          )
        : null;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SwipeToClose(
        enabled: !_zoomed,
        onClose: () => Navigator.of(context).maybePop(),
        child: PageView.builder(
          controller: _pages,
          physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
          itemCount: items.length,
          onPageChanged: (i) => setState(() {
            _index = i;
            _zoomed = false;
          }),
          itemBuilder: (context, i) => switch (items[i]) {
            final VideoMedia video => _VideoPage(
              key: ValueKey(video.file.id),
              video: video,
              gateway: widget.gateway,
              active: i == _index,
              title: counter,
              onZoomChanged: _onZoom,
            ),
            final PhotoMedia photo => Stack(
              fit: StackFit.expand,
              children: [
                ZoomablePhoto(
                  photo: photo,
                  gateway: widget.gateway,
                  onZoomChanged: _onZoom,
                ),
                ViewerTopBar(title: counter),
              ],
            ),
            _ => const SizedBox.shrink(),
          },
        ),
      ),
    );
  }
}

/// A video page plays only while it is the one in front; its neighbours, which show while
/// the album is being swiped, are posters.
class _VideoPage extends StatefulWidget {
  const _VideoPage({
    super.key,
    required this.video,
    required this.gateway,
    required this.active,
    required this.title,
    required this.onZoomChanged,
  });
  final VideoMedia video;
  final TelegramGateway gateway;
  final bool active;
  final Widget? title;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  VideoSession? _session;

  @override
  void initState() {
    super.initState();
    if (widget.active) _take();
  }

  @override
  void didUpdateWidget(_VideoPage old) {
    super.didUpdateWidget(old);
    if (widget.active == old.active) return;
    widget.active ? _take() : _handBack();
  }

  @override
  void dispose() {
    _handBack();
    super.dispose();
  }

  void _take() => _session = VideoSessions.of(
    widget.gateway,
  ).open(widget.video.file, loop: widget.video.isAnimation)..retainForViewer();

  void _handBack() {
    _session?.releaseFromViewer();
    _session = null;
  }

  Widget _poster() {
    final thumbnail = widget.video.thumbnail;
    if (thumbnail == null) return const SizedBox.expand();
    return Downloaded(
      key: ValueKey(thumbnail.id),
      file: thumbnail,
      gateway: widget.gateway,
      placeholder: const SizedBox.expand(),
      builder: (context, path) => Image.file(File(path), fit: BoxFit.contain),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session == null) return _poster();
    return VideoStage(
      session: session,
      poster: _poster(),
      title: widget.title,
      onZoomChanged: widget.onZoomChanged,
      actions: [
        VideoDownloadButton(file: widget.video.file, gateway: widget.gateway),
      ],
    );
  }
}

/// The full-size photo, not the viewport-sized one the timeline shows.
class ZoomablePhoto extends StatefulWidget {
  const ZoomablePhoto({
    super.key,
    required this.photo,
    required this.gateway,
    required this.onZoomChanged,
  });
  final PhotoMedia photo;
  final TelegramGateway gateway;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<ZoomablePhoto> {
  final _transform = TransformationController();
  Offset _doubleTapAt = Offset.zero;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_report);
  }

  void _report() => widget.onZoomChanged(_transform.isZoomed);

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
      onDoubleTap: () => _transform.toggleZoom(_doubleTapAt),
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: 1,
        maxScale: 6,
        child: Center(
          child: Downloaded(
            file: widget.photo.largest,
            gateway: widget.gateway,
            placeholder: const Center(
              child: CircularProgressIndicator(color: Colors.white70),
            ),
            builder: (context, path) => Image.file(
              File(path),
              fit: BoxFit.contain,
              gaplessPlayback: true,
            ),
          ),
        ),
      ),
    );
  }
}
