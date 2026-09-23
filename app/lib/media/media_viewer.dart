import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../feeds/media_view.dart' show Downloaded, pickPhotoSize;
import '../feeds/post_card.dart' show formatDay;
import 'audio_session.dart';
import 'gallery.dart';
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
    this.postKey = '',
  });
  final String channel;

  /// Unix seconds of the post.
  final int date;
  final String caption;

  /// Which post this picture belongs to, so "N of M" counts that post's album and not
  /// the whole feed. Empty where the caller does not say.
  final String postKey;
}

class MediaViewerScreen extends StatefulWidget {
  const MediaViewerScreen({
    super.key,
    required this.items,
    required this.gateway,
    this.initialIndex = 0,
    this.onNeedOlder,
    this.details = const [],
    this.onSave,
    this.onDetails,
    this.gallery = const Gallery(),
    this.share = shareFileWithSystemSheet,
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

  /// Forwards the post the item at that index belongs to into Saved Messages.
  final void Function(int index)? onSave;

  /// Opens the system share sheet with the file itself (tests inject a recorder).
  final Future<void> Function(String path, {required String mimeType}) share;

  static Future<void> shareFileWithSystemSheet(
    String path, {
    required String mimeType,
  }) async {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path, mimeType: mimeType)]),
    );
  }

  /// The details again, after more items were loaded.
  final List<ViewerDetail> Function()? onDetails;

  /// Where "Save to gallery" puts the file; tests hand in their own.
  final Gallery gallery;

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
    void Function(int index)? onSave,
    List<ViewerDetail> Function()? onDetails,
    Gallery gallery = const Gallery(),
    Future<void> Function(String path, {required String mimeType}) share =
        shareFileWithSystemSheet,
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
        onSave: onSave,
        onDetails: onDetails,
        gallery: gallery,
        share: share,
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );

  /// How many viewers are open; the audio bar stays out of their way.
  static final showing = ValueNotifier<int>(0);

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

  /// Whether the top bar and the caption are over a picture; a video's own controls carry
  /// them there.
  bool _chrome = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    MediaViewerScreen.showing.value++;
    _quietAudioFor(_index);
    // Once the first page holds its session: a mini player that was opened in the viewer
    // again goes on here, any other one ends.
    WidgetsBinding.instance.addPostFrameCallback((_) => MiniPlayer.dismiss());
  }

  /// A video plays with its sound, so voice and music stop, as in the official app.
  void _quietAudioFor(int index) {
    if (index < _items.length && _items[index] is VideoMedia) {
      unawaited(AudioSessions.instance.pause());
    }
  }

  void _toMiniPlayer(VideoSession session) {
    final w = widget;
    MiniPlayer.show(
      context,
      session: session,
      items: _items,
      index: _index,
      gateway: w.gateway,
      // Back to the viewer with everything it had: channel and day, caption, actions and
      // the older pictures of the feed.
      reopen: (context, items, index) => MediaViewerScreen.open(
        context,
        items: items,
        gateway: w.gateway,
        initialIndex: index,
        onNeedOlder: w.onNeedOlder,
        details: _details,
        onSave: w.onSave,
        onDetails: w.onDetails,
        gallery: w.gallery,
        share: w.share,
      ),
    );
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    MediaViewerScreen.showing.value--;
    _pages.dispose();
    super.dispose();
  }

  void _onZoom(bool zoomed) {
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  /// The file of the page in front, and whether it is a video.
  ({FileRef file, bool video})? _current() {
    final item = _index < _items.length ? _items[_index] : null;
    final file = switch (item) {
      PhotoMedia(:final sizes) => sizes.isEmpty ? null : sizes.last,
      VideoMedia(:final file) => file,
      _ => null,
    };
    return file == null ? null : (file: file, video: item is VideoMedia);
  }

  /// The whole file in Telegram's cache, or null when it is not there. A post carries the
  /// [FileRef] of the time it was loaded, so TDLib is asked how much of the file it has by
  /// now; a complete file answers with its path at once.
  Future<String?> _fileOnDisk(FileRef file) async {
    if (file.isDownloaded) return file.localPath;
    if (file.size <= 0) return null;
    if (await widget.gateway.downloadedPrefix(file.id, 0) < file.size) {
      return null;
    }
    return (await widget.gateway.download(file)).localPath;
  }

  /// Shares the picture or the video itself, not the post's words. A video is only shared
  /// once it is on the device: sharing does not start an 800 MB download behind the
  /// reader's back, it says what is missing and offers to fetch it.
  Future<void> _share() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final current = _current();
    if (current == null) return;
    final (:file, :video) = current;
    try {
      final path = video
          ? await _fileOnDisk(file)
          : (await widget.gateway.download(file)).localPath;
      if (!mounted) return;
      if (path == null) {
        messenger?.showSnackBar(
          video
              ? SnackBar(
                  content: const Text('Download the video first to share it.'),
                  action: SnackBarAction(
                    label: 'Download',
                    onPressed: () => unawaited(
                      VideoDownloads.of(widget.gateway).start(file),
                    ),
                  ),
                )
              : const SnackBar(
                  content: Text('Cannot share: the file did not arrive'),
                ),
        );
        return;
      }
      await widget.share(path, mimeType: video ? 'video/mp4' : 'image/jpeg');
    } on Object catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('Cannot share: $e')));
    }
  }

  /// Puts the picture or the video of the page in front into the phone's gallery. The file
  /// is downloaded first if it is not there yet, as the download button would.
  Future<void> _saveToGallery() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final current = _current();
    if (current == null) return;
    final (:file, :video) = current;
    try {
      final ready = file.localPath != null
          ? file
          : await widget.gateway.download(file);
      final path = ready.localPath;
      if (path == null) throw StateError('the file did not arrive');
      await widget.gallery.save(
        path: path,
        name: Gallery.nameFor(fileId: file.id, video: video),
        mimeType: video ? 'video/mp4' : 'image/jpeg',
      );
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            video ? 'Video saved to gallery' : 'Picture saved to gallery',
          ),
        ),
      );
    } on Object catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('Cannot save: $e')));
    }
  }

  /// "N of M" for the album the picture in front belongs to, or for the whole list when
  /// it is one post's album on its own. Null when there is nothing to count.
  String? _counter() {
    final key = _index < _details.length ? _details[_index].postKey : '';
    if (key.isEmpty) {
      return _items.length > 1 && widget.onNeedOlder == null
          ? '${_index + 1} of ${_items.length}'
          : null;
    }
    var first = _index;
    var last = _index;
    while (first > 0 && _details[first - 1].postKey == key) {
      first--;
    }
    while (last + 1 < _details.length && _details[last + 1].postKey == key) {
      last++;
    }
    final total = last - first + 1;
    return total > 1 ? '${_index - first + 1} of $total' : null;
  }

  /// Near the older end (the last page): ask the timeline for its next page of posts.
  Future<void> _loadOlder() async {
    final ask = widget.onNeedOlder;
    if (ask == null || _loadingOlder || _noMoreOlder) return;
    if (mounted) setState(() => _loadingOlder = true);
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
      if (mounted) {
        setState(() => _loadingOlder = false);
      } else {
        _loadingOlder = false;
      }
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
            // Within the post the picture came from: a feed's pictures grow as older
            // ones load, so counting them all would say "3 of 60".
            ?_counter(),
            if (detail != null && detail.date > 0)
              formatDay(
                DateTime.fromMillisecondsSinceEpoch(detail.date * 1000),
              ),
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
      ],
    );
    // Only sharing stands in the bar beside the video's own buttons; the rest is behind
    // the three dots, so that the channel and the day keep their room on a phone.
    List<ViewerAction> menu() => [
      if (widget.onSave != null)
        ViewerAction('Save to Saved Messages', () => widget.onSave!(_index)),
      ViewerAction('Save to gallery', () => unawaited(_saveToGallery())),
    ];
    final actions = [
      IconButton(
        tooltip: 'Share',
        color: Colors.white,
        icon: const Icon(Icons.share),
        onPressed: () => unawaited(_share()),
      ),
      ViewerMenu(actions: menu),
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
            _quietAudioFor(i);
            // One page short of the end: the next ones are on their way.
            if (i >= items.length - 2) unawaited(_loadOlder());
          },
          itemBuilder: (context, i) => switch (items[i]) {
            final VideoMedia video => _VideoPage(
              key: ValueKey(video.file.id),
              video: video,
              gateway: widget.gateway,
              active: i == _index,
              title: title,
              actions: actions,
              menu: menu,
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
                  // A tap takes the bar and the words off the picture, as on a video.
                  onTap: () => setState(() => _chrome = !_chrome),
                ),
                // A gradient under the bar: white letters on a white sky are unreadable.
                if (_chrome) const _TopScrim(),
                if (_chrome) ViewerTopBar(title: title, actions: actions),
                if (_chrome &&
                    i < _details.length &&
                    _details[i].caption.isNotEmpty)
                  ViewerCaption(text: _details[i].caption),
              ],
            ),
            _ => const SizedBox.shrink(),
          },
        ),
      ),
      // The older pages are being fetched: a quiet line at the bottom, so the end of the
      // feed and a slow connection do not look the same.
      bottomNavigationBar: _loadingOlder && _index >= items.length - 2
          ? const SizedBox(
              height: 3,
              child: LinearProgressIndicator(minHeight: 3),
            )
          : null,
    );
  }
}

/// The dark fade behind the viewer's top bar, so its white letters hold on any picture.
class _TopScrim extends StatelessWidget {
  const _TopScrim();

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        height: 140 + MediaQuery.paddingOf(context).top,
        child: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black54, Colors.transparent],
            ),
          ),
          child: SizedBox(width: double.infinity),
        ),
      ),
    ),
  );
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
    required this.menu,
    required this.caption,
    required this.onZoomChanged,
    required this.onPip,
  });
  final VideoMedia video;
  final TelegramGateway gateway;
  final bool active;
  final Widget? title;

  /// The viewer's own buttons, of which the last is its menu: the video puts its buttons
  /// before them and its own lines into the menu.
  final List<Widget> actions;
  final List<ViewerAction> Function() menu;
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
    final file = widget.video.file;
    return VideoStage(
      session: session,
      poster: _poster(),
      title: widget.title,
      onZoomChanged: widget.onZoomChanged,
      actions: [
        // A ring while the file downloads, nothing otherwise: the menu is where a download
        // is asked for.
        VideoDownloadButton(file: file, gateway: widget.gateway, compact: true),
        IconButton(
          tooltip: 'Picture-in-picture',
          color: Colors.white,
          icon: const Icon(Icons.picture_in_picture_alt),
          onPressed: () => widget.onPip(session),
        ),
        // Everything but the viewer's menu, which comes last and takes the video's lines.
        ...widget.actions.take(widget.actions.length - 1),
        ViewerMenu(
          actions: () => [
            ...VideoDownloadButton.menuActions(file, widget.gateway),
            ...widget.menu(),
          ],
        ),
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
    this.onTap,
  });
  final PhotoMedia photo;
  final TelegramGateway gateway;
  final ValueChanged<bool> onZoomChanged;

  /// A single tap on the picture, which shows or hides the viewer's chrome.
  final VoidCallback? onTap;

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

  /// The size the timeline drew, when it is not the largest: already on the phone.
  FileRef? _smaller(BuildContext context) {
    final sizes = widget.photo.sizes;
    if (sizes.length < 2) return null;
    for (final f in sizes.reversed.skip(1)) {
      if (f.isDownloaded) return f;
    }
    final picked = pickPhotoSize(
      sizes,
      MediaQuery.sizeOf(context).width,
      pixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
    return picked.id == widget.photo.largest.id ? null : picked;
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
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
            // What the timeline showed stands in while the full size loads, so the page
            // never starts black.
            placeholder: Stack(
              alignment: Alignment.center,
              children: [
                if (_smaller(context) case final small?)
                  Downloaded(
                    file: small,
                    gateway: widget.gateway,
                    autoStart: false,
                    placeholder: const SizedBox.shrink(),
                    builder: (context, path) => Image.file(
                      File(path),
                      fit: BoxFit.contain,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
                const CircularProgressIndicator(color: Colors.white70),
              ],
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
