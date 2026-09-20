import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../feeds/media_view.dart' show Downloaded;
import '../feeds/post_card.dart' show formatDay;
import 'mini_player.dart';
import 'swipe_to_close.dart';
import 'video_downloads.dart';
import 'video_sessions.dart';
import 'video_stage.dart';
import 'zoom.dart';

/// The photos and videos on the whole screen, in whatever orientation the device has: swipe
/// sideways through everything the timeline holds — the post's own album and the pictures of
/// the posts around it, older ones loading as the reader goes (H-21) — pinch or double tap
/// to zoom, drag down or up to close. The video of the page in front plays with sound; turning the page or leaving hands
/// its session back, which ends playback and streaming unless the video autoplays in its row
/// or moved on into the [MiniPlayer].
/// What the viewer says about one picture: which channel it came from, when it was posted
/// and what its post said. Aligned with the items by index.
class ViewerDetail {
  const ViewerDetail({
    required this.channel,
    required this.date,
    this.caption = '',
  });
  final String channel;

  /// Unix seconds of the post.
  final int date;
  final String caption;
}

class MediaViewerScreen extends StatefulWidget {
  const MediaViewerScreen({
    super.key,
    required this.items,
    required this.gateway,
    this.initialIndex = 0,
    this.onNeedOlder,
    this.details = const [],
    this.onShare,
    this.onSave,
    this.onDetails,
  });

  /// [PhotoMedia] and [VideoMedia] only, see [viewable].
  final List<Media> items;
  final TelegramGateway gateway;
  final int initialIndex;

  /// Asked for more media when the reader reaches the older end: the timeline loads its
  /// next page and answers with everything it has, this list included.
  final Future<List<Media>> Function()? onNeedOlder;

  /// The channel, the time and the caption of each item; empty where the caller has none.
  final List<ViewerDetail> details;

  /// Share and save the post the item at that index belongs to.
  final void Function(int index)? onShare;
  final void Function(int index)? onSave;

  /// The details again, after more items were loaded.
  final List<ViewerDetail> Function()? onDetails;

  /// What of a post's media the viewer can show, in the order of the post.
  static List<Media> viewable(Iterable<Media> media) => [
    for (final m in media)
      // A sticker is not a picture to open, and a round video message plays where it is.
      if (m is PhotoMedia || (m is VideoMedia && !m.isVideoNote)) m,
  ];

  static Future<void> open(
    BuildContext context, {
    required List<Media> items,
    required TelegramGateway gateway,
    int initialIndex = 0,
    Future<List<Media>> Function()? onNeedOlder,
    List<ViewerDetail> details = const [],
    void Function(int index)? onShare,
    void Function(int index)? onSave,
    List<ViewerDetail> Function()? onDetails,
  }) => Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      // The timeline shows through while the page is dragged away.
      opaque: false,
      pageBuilder: (_, _, _) => MediaViewerScreen(
        items: items,
        gateway: gateway,
        initialIndex: initialIndex,
        onNeedOlder: onNeedOlder,
        details: details,
        onShare: onShare,
        onSave: onSave,
        onDetails: onDetails,
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

  /// Everything the viewer can page through: what it opened with, and what the timeline
  /// hands over as the reader goes past the older end.
  late List<Media> _items = widget.items;
  late List<ViewerDetail> _details = widget.details;
  bool _loadingOlder = false;
  bool _noMoreOlder = false;

  /// Paging and swipe-to-close are off while a page is zoomed in, so a drag pans it instead.
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // Once the first page holds its session: a mini player that was opened in the viewer
    // again goes on here, any other one ends.
    WidgetsBinding.instance.addPostFrameCallback((_) => MiniPlayer.dismiss());
  }

  void _toMiniPlayer(VideoSession session) {
    MiniPlayer.show(
      context,
      session: session,
      items: _items,
      index: _index,
      gateway: widget.gateway,
    );
    Navigator.of(context).maybePop();
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

  /// Near the older end (the last page): ask the timeline for its next page of posts.
  Future<void> _loadOlder() async {
    final ask = widget.onNeedOlder;
    if (ask == null || _loadingOlder || _noMoreOlder) return;
    _loadingOlder = true;
    try {
      final more = await ask();
      if (!mounted) return;
      if (more.length <= _items.length) {
        _noMoreOlder = true;
        return;
      }
      setState(() {
        _items = more;
        // The caller hands the details over with the items; asking again refreshes both.
        _details = widget.onDetails?.call() ?? _details;
      });
    } finally {
      _loadingOlder = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final detail = _index < _details.length ? _details[_index] : null;
    // The channel and the day above, the counter under them, as the official app does.
    final title = Column(
      // Without this the column fills the screen and the bar swallows every tap.
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (detail != null && detail.channel.isNotEmpty)
          Text(
            detail.channel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        Text(
          [
            if (items.length > 1) '${_index + 1} of ${items.length}',
            if (detail != null && detail.date > 0)
              formatDay(
                DateTime.fromMillisecondsSinceEpoch(detail.date * 1000),
              ),
          ].join(' · '),
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
      ],
    );
    final counter = Flexible(child: title);
    final actions = [
      if (widget.onShare != null)
        IconButton(
          tooltip: 'Share',
          color: Colors.white,
          icon: const Icon(Icons.share),
          onPressed: () => widget.onShare!(_index),
        ),
      if (widget.onSave != null)
        IconButton(
          tooltip: 'Save to Saved Messages',
          color: Colors.white,
          icon: const Icon(Icons.bookmark_add_outlined),
          onPressed: () => widget.onSave!(_index),
        ),
    ];
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SwipeToClose(
        enabled: !_zoomed,
        onClose: () => Navigator.of(context).maybePop(),
        child: PageView.builder(
          controller: _pages,
          physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
          itemCount: items.length,
          onPageChanged: (i) {
            setState(() {
              _index = i;
              _zoomed = false;
            });
            // One page short of the end: the next ones are on their way.
            if (i >= items.length - 2) unawaited(_loadOlder());
          },
          itemBuilder: (context, i) => switch (items[i]) {
            final VideoMedia video => _VideoPage(
              key: ValueKey(video.file.id),
              video: video,
              gateway: widget.gateway,
              active: i == _index,
              title: counter,
              actions: actions,
              caption: i < _details.length ? _details[i].caption : '',
              onZoomChanged: _onZoom,
              onPip: _toMiniPlayer,
            ),
            final PhotoMedia photo => Stack(
              fit: StackFit.expand,
              children: [
                ZoomablePhoto(
                  photo: photo,
                  gateway: widget.gateway,
                  onZoomChanged: _onZoom,
                ),
                ViewerTopBar(title: counter, actions: actions),
                if (i < _details.length && _details[i].caption.isNotEmpty)
                  ViewerCaption(text: _details[i].caption),
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
    required this.actions,
    required this.caption,
    required this.onZoomChanged,
    required this.onPip,
  });
  final VideoMedia video;
  final TelegramGateway gateway;
  final bool active;
  final Widget? title;
  final List<Widget> actions;
  final String caption;
  final ValueChanged<bool> onZoomChanged;
  final ValueChanged<VideoSession> onPip;

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
        IconButton(
          tooltip: 'Picture-in-picture',
          color: Colors.white,
          icon: const Icon(Icons.picture_in_picture_alt),
          onPressed: () => widget.onPip(session),
        ),
        ...widget.actions,
      ],
      caption: widget.caption,
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
