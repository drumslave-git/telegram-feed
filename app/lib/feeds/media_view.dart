import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:telegram_gateway/telegram_gateway.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../l10n/l10n.dart';
import '../media/audio_session.dart';
import '../media/auto_download.dart';
import '../media/media_viewer.dart';
import '../media/video_downloads.dart';
import '../media/video_sessions.dart';
import '../media/video_stage.dart';
import 'extra_media.dart';
import 'media_cover.dart';
import 'players.dart';
import 'sticker_view.dart';

/// A picture file decoded at the size it is drawn in [box] instead of its own: a photo of
/// 1280 px takes 6.5 MB decoded, the image cache would hold a few screens of them and
/// scrolling back would decode them again. [width] and [height] are the file's own; when
/// they are unknown, or the box needs every pixel, the file decodes whole. [cover] fills the
/// box and crops, as `BoxFit.cover` draws; otherwise the picture fits inside it.
ImageProvider fileImageFor(
  String path, {
  required int width,
  required int height,
  required Size box,
  required double pixelRatio,
  bool cover = true,
}) {
  final image = FileImage(File(path));
  if (width <= 0 || height <= 0 || !box.isFinite || box.isEmpty) return image;
  final scale =
      (cover
          ? math.max(box.width / width, box.height / height)
          : math.min(box.width / width, box.height / height)) *
      pixelRatio;
  if (scale >= 1) return image;
  return ResizeImage(image, width: math.max(1, (width * scale).ceil()));
}

/// [Image] of a picture file filling its place and cropped to it, decoded at that size
/// ([fileImageFor]).
class SizedFileImage extends StatelessWidget {
  const SizedFileImage({
    super.key,
    required this.path,
    required this.width,
    required this.height,
    this.gaplessPlayback = false,
  });
  final String path;

  /// The file's own size in pixels; zero when unknown.
  final int width;
  final int height;
  final bool gaplessPlayback;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Image(
      image: fileImageFor(
        path,
        width: width,
        height: height,
        box: constraints.biggest,
        pixelRatio: MediaQuery.devicePixelRatioOf(context),
      ),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: gaplessPlayback,
    ),
  );
}

/// Renders one post's media inline. Files are TDLib-managed: [gateway.download] returns the
/// local path and [gateway.fileProgress] reports progress while it downloads.
class MediaView extends StatelessWidget {
  const MediaView({
    super.key,
    required this.media,
    required this.gateway,
    this.onOpen,
    this.fill = false,
    this.radius = 8,
    this.heroTag,
  });
  final Media media;
  final TelegramGateway gateway;

  /// Tap on a photo or a video: the timeline opens the viewer on the album of the post.
  final VoidCallback? onOpen;

  /// A cell of an album mosaic: the picture is cropped into the box the parent gives it
  /// instead of taking the height of its own proportions.
  final bool fill;

  /// Corner radius of photos and videos; 0 inside a bubble, which clips them itself.
  final double radius;

  /// The name this picture flies under into the media viewer ([mediaHeroTag]); null where
  /// nothing opens it.
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final policy = AutoDownloadScope.of(context);
    final l10n = context.l10n;
    final media = this.media;
    final view = _view(context, policy, l10n);
    // A round video message is left as it is: the cover is a rectangle.
    return switch (media) {
      PhotoMedia(:final sizes, :final cover) when cover != MediaCover.none =>
        CoveredMedia(
          fileId: sizes.isEmpty ? 0 : sizes.last.id,
          cover: cover,
          radius: radius,
          child: view,
        ),
      VideoMedia(:final file, :final cover, :final isVideoNote)
          when cover != MediaCover.none && !isVideoNote =>
        CoveredMedia(
          fileId: file.id,
          cover: cover,
          radius: radius,
          child: view,
        ),
      _ => view,
    };
  }

  Widget _view(
    BuildContext context,
    AutoDownloadPolicy policy,
    AppLocalizations l10n,
  ) {
    return switch (media) {
      PhotoMedia(:final sizes, :final miniature) => PhotoView(
        file: pickPhotoSize(
          sizes,
          MediaQuery.sizeOf(context).width,
          pixelRatio: MediaQuery.devicePixelRatioOf(context),
        ),
        gateway: gateway,
        onTap: onOpen,
        fill: fill,
        radius: radius,
        heroTag: heroTag,
        miniature: miniature,
      ),
      // A sticker keeps its own size, so it must not be stretched by the bubble.
      final StickerMedia sticker => Align(
        alignment: Alignment.centerLeft,
        child: StickerView(sticker: sticker, gateway: gateway),
      ),
      // A round video message: the same player, clipped to a circle as in the official app.
      final VideoMedia video when video.isVideoNote => Align(
        alignment: Alignment.centerLeft,
        child: ClipOval(
          child: SizedBox(
            width: videoNoteSide,
            height: videoNoteSide,
            child: VideoView(
              video: video,
              gateway: gateway,
              autoplay: policy.autoplay(video),
              download: policy.video(video),
              preload: policy.preload(video),
              onOpen: onOpen,
              fill: true,
              radius: 0,
            ),
          ),
        ),
      ),
      final VideoMedia video => VideoView(
        video: video,
        gateway: gateway,
        autoplay: policy.autoplay(video),
        download: policy.video(video),
        preload: policy.preload(video),
        onOpen: onOpen,
        fill: fill,
        radius: radius,
        heroTag: heroTag,
      ),
      AudioMedia(
        :final file,
        :final durationSeconds,
        :final title,
        :final performer,
        :final isVoice,
      ) =>
        AudioView(
          file: file,
          durationSeconds: durationSeconds,
          label: isVoice
              ? l10n.mediaVoiceMessage
              : [title, performer].where((s) => s.isNotEmpty).join(' – '),
          gateway: gateway,
          isVoice: isVoice,
          autoLoad: isVoice ? policy.voice(file.size) : policy.file(file.size),
        ),
      DocumentMedia(
        :final file,
        :final fileName,
        :final mimeType,
        :final thumbnail,
      ) =>
        DocumentView(
          file: file,
          fileName: fileName,
          mimeType: mimeType,
          thumbnail: thumbnail,
          gateway: gateway,
          autoStart: policy.file(file.size),
        ),
      final LocationMedia place => LocationView(place: place, gateway: gateway),
      final ContactMedia contact => ContactView(
        contact: contact,
        gateway: gateway,
      ),
      final GameMedia game => GameView(game: game, gateway: gateway),
      final ChecklistMedia list => ChecklistView(list: list),
      UnsupportedMedia(:final tdType) => Chip(
        label: Text(l10n.unsupportedLabel(tdType)),
        visualDensity: VisualDensity.compact,
      ),
      // A line of its own in the timeline (`ChatPill`); here only in a reply quote.
      final ServiceNote note => Text(l10n.mediaPreview(note)),
    };
  }
}

/// Smallest size that is at least as wide as the viewport (or the largest available).
/// [pixelRatio] is the screen's own, so a dense phone does not get a blurred picture and
/// a plain one does not download twice what it can show.
FileRef pickPhotoSize(
  List<FileRef> sizes,
  double viewportWidth, {
  double pixelRatio = 2.0,
}) {
  for (final s in sizes) {
    if (s.width >= viewportWidth * pixelRatio) return s;
  }
  return sizes.last;
}

/// Downloads a file once and rebuilds with its local path; shows progress meanwhile.
class Downloaded extends StatefulWidget {
  const Downloaded({
    super.key,
    required this.file,
    required this.gateway,
    required this.builder,
    this.autoStart = true,
    this.placeholder,
    this.pending,
    this.waiting,
  });
  final FileRef file;
  final TelegramGateway gateway;
  final Widget Function(BuildContext context, String path) builder;
  final bool autoStart;
  final Widget? placeholder;

  /// Draws the waiting state from all there is to know about it ([DownloadWaiting]): how
  /// much has come, and the way to stop it. Takes precedence over [pending].
  final Widget Function(BuildContext context, DownloadWaiting waiting)? waiting;

  /// Draws the waiting state itself, with the way to start the download, how far it has
  /// come (null before it starts) and whether it is running. Takes precedence over
  /// [placeholder]; a picture uses it to offer a proper download badge.
  final Widget Function(
    BuildContext context,
    VoidCallback start,
    double? progress,
    bool started,
  )?
  pending;

  @override
  State<Downloaded> createState() => _DownloadedState();
}

/// A file on its way, for a stand-in that draws itself.
class DownloadWaiting {
  const DownloadWaiting({
    required this.start,
    required this.cancel,
    required this.started,
    required this.cancelled,
    required this.progress,
    required this.downloaded,
    required this.total,
  });
  final VoidCallback start;
  final VoidCallback cancel;

  /// The download is running.
  final bool started;

  /// The reader stopped it: it does not start again by itself.
  final bool cancelled;

  /// 0..1, or null while nothing is known.
  final double? progress;

  /// Bytes that have come, and how many there are in all (0 while unknown).
  final int downloaded;
  final int total;
}

class _DownloadedState extends State<Downloaded> {
  String? _path;
  double? _progress;
  int _downloaded = 0;
  int _total = 0;
  bool _started = false;
  bool _cancelled = false;
  String? _error;
  StreamSubscription<FileProgress>? _sub;

  @override
  void initState() {
    super.initState();
    _path = widget.file.isDownloaded ? widget.file.localPath : null;
    if (_path == null && widget.autoStart) start();
  }

  /// The list reuses row state by position; a different file starts over.
  @override
  void didUpdateWidget(Downloaded old) {
    super.didUpdateWidget(old);
    if (old.file.id == widget.file.id) {
      // The settings arrived and now allow it: start without waiting for a tap.
      if (_path == null && !_started && widget.autoStart && !old.autoStart) {
        unawaited(start());
      }
      return;
    }
    _sub?.cancel();
    _started = false;
    _cancelled = false;
    _progress = null;
    _downloaded = 0;
    _total = 0;
    _error = null;
    _path = widget.file.isDownloaded ? widget.file.localPath : null;
    if (_path == null && widget.autoStart) start();
  }

  /// Stops the download, as the cross in the official app's progress ring does. It does
  /// not start again until the reader asks.
  Future<void> cancel() async {
    if (!_started) return;
    final file = widget.file;
    setState(() {
      _cancelled = true;
      _started = false;
      _progress = null;
    });
    try {
      await widget.gateway.cancelDownload(file.id);
    } on TelegramException {
      // Nothing to stop: it was done, or never began.
    }
  }

  Future<void> start() async {
    if (_started) return;
    setState(() {
      _started = true;
      _cancelled = false;
      _error = null;
    });
    final file = widget.file;
    final sub = _sub = widget.gateway.fileProgress(file.id).listen((p) {
      if (!mounted || widget.file.id != file.id || _cancelled) return;
      setState(() {
        _downloaded = p.downloaded;
        _total = p.total;
        _progress = p.total > 0 ? p.downloaded / p.total : null;
      });
    });
    try {
      final done = await widget.gateway.download(file);
      if (mounted && widget.file.id == file.id && done.localPath != null) {
        setState(() => _path = done.localPath);
      }
    } on TelegramException catch (e) {
      // A download the reader stopped ends with an error too: that is no failure.
      if (mounted && widget.file.id == file.id && !_cancelled) {
        // [_started] goes back to false so a tap can ask again: a download that failed
        // once (a dropped connection) is not a dead end.
        setState(() {
          _error = e.message;
          _started = false;
          _progress = null;
        });
      }
    } finally {
      await sub.cancel();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final path = _path;
    if (path != null) return widget.builder(context, path);
    final failed = _error;
    if (failed != null) {
      // A picture keeps its stand-in and retries on a tap; a row without one says so.
      final again = InkWell(onTap: start, child: widget.placeholder);
      return Tooltip(
        message: failed,
        child: widget.placeholder != null
            ? again
            : InkWell(
                onTap: start,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.refresh, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        context.l10n.postDownloadFailed,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
      );
    }
    final waiting = widget.waiting;
    if (waiting != null) {
      return waiting(
        context,
        DownloadWaiting(
          start: () => unawaited(start()),
          cancel: () => unawaited(cancel()),
          started: _started,
          cancelled: _cancelled,
          progress: _progress,
          downloaded: _downloaded,
          total: _total > 0 ? _total : widget.file.size,
        ),
      );
    }
    final pending = widget.pending;
    if (pending != null) {
      return pending(context, () => unawaited(start()), _progress, _started);
    }
    return widget.placeholder ??
        InkWell(
          onTap: _started ? null : start,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: _started ? _progress : 0,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _started
                    ? context.l10n.postDownloading
                    : context.l10n.postTapToDownload,
              ),
            ],
          ),
        );
  }
}

class PhotoView extends StatelessWidget {
  const PhotoView({
    super.key,
    required this.file,
    required this.gateway,
    this.onTap,
    this.fill = false,
    this.radius = 8,
    this.heroTag,
    this.miniature,
  });
  final FileRef file;
  final TelegramGateway gateway;
  final VoidCallback? onTap;

  /// Telegram's tiny preview of the picture, drawn blurred while the picture loads.
  final String? miniature;
  final bool fill;
  final double radius;

  /// The name this picture flies under into the media viewer ([mediaHeroTag]).
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final aspect = file.width > 0 && file.height > 0
        ? file.width / file.height
        : 4 / 3;
    // A picture loads by itself only where the reader allowed photos for this connection.
    // While the settings are still being read nothing starts, and nothing is offered
    // either: a moment later the policy is known.
    final policy = AutoDownloadScope.of(context);
    final auto = policy.photos;
    final backdrop = MediaMiniature(miniature);
    final picture = Downloaded(
      file: file,
      gateway: gateway,
      autoStart: auto,
      // After a failure: the stand-in, which asks again on a tap.
      placeholder: backdrop,
      // While it loads the picture is its own blurred miniature with the ring and the
      // cross that stops it; where photos do not load by themselves on this connection
      // (or the reader stopped it) the whole area is the button, with the size on it.
      // While the settings are still being read nothing starts, and nothing is offered
      // either: a moment later the policy is known.
      waiting: (context, w) => _PhotoWaiting(
        backdrop: backdrop,
        waiting: w,
        size: file.size,
        offer: policy.ready && (!auto || w.cancelled),
      ),
      builder: (context, path) => SizedFileImage(
        path: path,
        width: file.width,
        height: file.height,
        gaplessPlayback: true,
      ),
    );
    final shown = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: fill
          ? SizedBox.expand(child: picture)
          : AspectRatio(
              aspectRatio: aspect.clamp(mediaMinAspect, mediaMaxAspect),
              child: picture,
            ),
    );
    return Semantics(
      image: true,
      button: onTap != null,
      label: onTap == null
          ? context.l10n.mediaPhoto
          : context.l10n.postPhotoOpensFullScreen,
      child: GestureDetector(
        onTap: onTap,
        // The picture flies from here into the viewer and back to here.
        child: heroTag == null ? shown : Hero(tag: heroTag!, child: shown),
      ),
    );
  }
}

/// Telegram's tiny preview of a picture or a video, blurred to fill its place while the
/// real thing loads; a tinted box when the post brought none.
class MediaMiniature extends StatelessWidget {
  const MediaMiniature(this.miniature, {super.key});

  /// A small JPEG in base64, or null.
  final String? miniature;

  static final _decoded = <String, Uint8List?>{};

  static Uint8List? _bytesOf(String data) => _decoded.putIfAbsent(data, () {
    try {
      return base64Decode(data);
    } on FormatException {
      return null;
    }
  });

  @override
  Widget build(BuildContext context) {
    final data = miniature;
    final bytes = data == null ? null : _bytesOf(data);
    if (bytes == null) return const ColoredBox(color: Colors.black12);
    return ClipRect(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Image.memory(
          bytes,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          gaplessPlayback: true,
          excludeFromSemantics: true,
          // A miniature Telegram sent broken is no reason to show an error.
          errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black12),
        ),
      ),
    );
  }
}

/// A picture that is not there yet, over its blurred miniature: the ring of the download
/// with the cross that stops it and how much has come, or the round download badge with
/// the size of the file where the download waits for a tap.
class _PhotoWaiting extends StatelessWidget {
  const _PhotoWaiting({
    required this.backdrop,
    required this.waiting,
    required this.size,
    required this.offer,
  });
  final Widget backdrop;
  final DownloadWaiting waiting;
  final int size;

  /// The download waits for the reader: the badge with the arrow is shown.
  final bool offer;

  @override
  Widget build(BuildContext context) {
    final w = waiting;
    final l10n = context.l10n;
    Widget badge(Widget child) => DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.black45,
        shape: BoxShape.circle,
      ),
      child: SizedBox.square(dimension: 48, child: child),
    );
    final Widget centre;
    if (w.started) {
      centre = Semantics(
        button: true,
        label: l10n.mediaCancelDownload,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: w.cancel,
          child: badge(
            Stack(
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.all(5),
                  child: CircularProgressIndicator(
                    value: w.progress,
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                ),
                const Icon(Icons.close, color: Colors.white, size: 22),
              ],
            ),
          ),
        ),
      );
    } else if (offer) {
      centre = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          badge(
            const Icon(Icons.arrow_downward, color: Colors.white, size: 24),
          ),
          if (size > 0) ...[
            const SizedBox(height: 6),
            MediaBadge(formatBytes(size)),
          ],
        ],
      );
    } else {
      centre = const SizedBox.shrink();
    }
    return GestureDetector(
      onTap: !w.started && offer ? w.start : null,
      child: Stack(
        fit: StackFit.expand,
        children: [
          backdrop,
          Center(child: centre),
          // How much of it is here, in the corner where the official app writes it.
          if (w.started && w.total > 0)
            Positioned(
              left: 8,
              top: 8,
              child: MediaBadge(
                l10n.mediaLoadedOf(
                  formatBytes(w.downloaded),
                  formatBytes(w.total),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Side of a round video message, as the official app draws one.
const videoNoteSide = 200.0;

/// Proportions a single photo or video may take in a row; beyond them it is cropped.
const mediaMinAspect = 0.65;
const mediaMaxAspect = 2.5;

/// Thumbnail with a play button. A tap plays the video in the full-screen viewer at once, as
/// the official app does; the timeline itself only shows muted autoplay of the videos that
/// load by itself ([AutoDownloadPolicy]), and a tap on that opens the viewer with sound too.
class VideoView extends StatefulWidget {
  const VideoView({
    super.key,
    required this.video,
    required this.gateway,
    this.autoplay = false,
    this.download = false,
    this.preload = false,
    this.onOpen,
    this.fill = false,
    this.radius = 8,
    this.heroTag,
  });
  final VideoMedia video;
  final TelegramGateway gateway;

  /// The name this video flies under into the media viewer ([mediaHeroTag]).
  final String? heroTag;

  /// See [MediaView.fill] and [MediaView.radius].
  final bool fill;
  final double radius;

  /// Starts muted once most of it is visible ([AutoDownloadPolicy.autoplay]).
  final bool autoplay;

  /// The whole file loads by itself, with its progress on the pill in the corner
  /// ([AutoDownloadPolicy.video]).
  final bool download;

  /// Too large for that: its first seconds load ahead ([AutoDownloadPolicy.preload]).
  final bool preload;

  /// Opens the viewer (the timeline pages through the post's album); by default the viewer
  /// shows this video alone.
  final VoidCallback? onOpen;

  @override
  State<VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<VideoView> {
  /// Only ever an autoplay session; a video started by a tap belongs to the viewer.
  VideoSession? _session;

  bool _routeIsCurrent = true;
  double _visible = 0;

  VideoSessions get _sessions => VideoSessions.of(widget.gateway);
  FileRef get _file => widget.video.file;

  @override
  void initState() {
    super.initState();
    _adopt(_sessions.find(_file.id));
    _fetch();
  }

  @override
  void didUpdateWidget(VideoView old) {
    super.didUpdateWidget(old);
    if (old.video.file.id != _file.id) {
      _session?.release();
      _session = null;
      _adopt(_sessions.find(_file.id));
      _fetch();
    } else if (widget.download != old.download ||
        widget.preload != old.preload) {
      // The settings arrived, or the connection changed.
      _fetch();
    }
  }

  /// What loads without a tap: the whole file, or the first seconds of a larger one. Not
  /// now: the downloads' listeners rebuild the pills of other rows.
  void _fetch() {
    if (_file.isDownloaded || !(widget.download || widget.preload)) return;
    final file = _file;
    final downloads = VideoDownloads.of(widget.gateway);
    final whole = widget.download;
    scheduleMicrotask(() {
      if (!mounted || file.id != _file.id) return;
      unawaited(
        whole ? downloads.start(file, auto: true) : downloads.preload(file),
      );
    });
  }

  /// The route of the viewer is see-through (it can be dragged away), so rows below it stay
  /// visible to the visibility detector; autoplay rests while another route is on top.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.of(context)?.isCurrent ?? true;
    if (current == _routeIsCurrent) return;
    _routeIsCurrent = current;
    // Not now: the listeners of the session rebuild widgets.
    scheduleMicrotask(() {
      final s = _session;
      if (!mounted || s == null || s.isShared) return;
      if (!current) {
        unawaited(s.pause());
      } else if (_visible >= 0.6) {
        unawaited(s.play());
      }
    });
  }

  void _adopt(VideoSession? s) {
    if (s == null || !s.autoplay) return;
    s.retain();
    _session = s;
  }

  /// A round video message plays where it is, with its sound, as in the official app; a
  /// second tap pauses it.
  Future<void> _playInCircle() async {
    var s = _session;
    if (s == null) {
      s = _sessions.open(_file, loop: false, autoplay: true);
      setState(() => _adopt(s));
    }
    if (s.muted) {
      await s.setMuted(false);
      await s.play();
    } else {
      await s.togglePlay();
    }
  }

  void _open() {
    if (widget.video.isVideoNote) {
      unawaited(_playInCircle());
      return;
    }
    final onOpen = widget.onOpen;
    if (onOpen != null) return onOpen();
    unawaited(
      MediaViewerScreen.open(
        context,
        items: [widget.video],
        gateway: widget.gateway,
      ),
    );
  }

  /// Autoplay starts when most of the video is on screen and pauses once little of it is
  /// left, unless the viewer is showing it.
  void _onVisibility(VisibilityInfo info) {
    if (!mounted) return;
    final visible = _visible = info.visibleFraction;
    final s = _session;
    if (!_routeIsCurrent) return;
    if (s == null) {
      if (widget.autoplay && visible >= 0.6) {
        setState(
          () => _adopt(_sessions.open(_file, loop: true, autoplay: true)),
        );
      }
      return;
    }
    if (s.isShared) return;
    if (visible >= 0.6) {
      unawaited(s.play());
    } else if (visible < 0.2) {
      unawaited(s.pause());
    }
  }

  @override
  void dispose() {
    _session?.release();
    super.dispose();
  }

  Widget _poster() => widget.video.thumbnail == null
      ? MediaMiniature(widget.video.miniature)
      : Downloaded(
          key: ValueKey(widget.video.thumbnail!.id),
          file: widget.video.thumbnail!,
          gateway: widget.gateway,
          placeholder: MediaMiniature(widget.video.miniature),
          builder: (context, path) => SizedFileImage(
            path: path,
            width: widget.video.thumbnail!.width,
            height: widget.video.thumbnail!.height,
          ),
        );

  @override
  Widget build(BuildContext context) {
    final aspect = _file.width > 0 && _file.height > 0
        ? _file.width / _file.height
        : 16 / 9;
    return VisibilityDetector(
      key: ValueKey(('video', _file.id, identityHashCode(this))),
      onVisibilityChanged: _onVisibility,
      child: _frame(aspect, _session),
    );
  }

  Widget _frame(double aspect, VideoSession? session) {
    final fill = widget.fill;
    final content = GestureDetector(
      onTap: _open,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (session != null)
            InlineVideo(session: session, poster: _poster(), cover: fill)
          else ...[
            _poster(),
            Center(
              child: _PlayBadge(size: fill ? 40 : 56, onPressed: _open),
            ),
          ],
          // Top left, next to the download button: the bottom right corner belongs to the
          // views and the time, which the post draws over the picture.
          Positioned(
            left: 8,
            top: 8,
            child: Row(
              children: [
                // Too much for a small cell of an album; the viewer has it as well.
                if (!fill) ...[
                  VideoDownloadButton(file: _file, gateway: widget.gateway),
                  const SizedBox(width: 6),
                ],
                if (session == null)
                  MediaBadge(
                    widget.video.isAnimation
                        ? context.l10n.mediaGif
                        : formatDuration(widget.video.durationSeconds),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    final shown = ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: fill
          ? SizedBox.expand(child: content)
          : AspectRatio(
              aspectRatio: aspect.clamp(mediaMinAspect, mediaMaxAspect),
              child: content,
            ),
    );
    final tag = widget.heroTag;
    // Only while it is a poster: a player that is already running would be handed to the
    // flight and flicker; once the viewer takes over, the page it flies to has one too.
    return tag == null || session != null
        ? shown
        : Hero(tag: tag, child: shown);
  }
}

/// The round, see-through play button of the official app.
class _PlayBadge extends StatelessWidget {
  const _PlayBadge({required this.size, required this.onPressed});
  final double size;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: context.l10n.postPlay,
    child: Material(
      color: Colors.black45,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox.square(
          dimension: size,
          child: Icon(Icons.play_arrow, color: Colors.white, size: size * 0.6),
        ),
      ),
    ),
  );
}

/// Small dark label on top of a picture: the length of a video, the time of a post.
class MediaBadge extends StatelessWidget {
  const MediaBadge(this.label, {super.key, this.child});
  final String label;

  /// Replaces the plain [label] (a footer with icons).
  final Widget? child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child:
          child ??
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
    ),
  );
}

/// Play/pause row for voice messages and audio files.
class AudioView extends StatefulWidget {
  const AudioView({
    super.key,
    required this.file,
    required this.durationSeconds,
    required this.label,
    required this.gateway,
    this.isVoice = false,
    this.sessions,
    this.autoLoad = false,
  });
  final FileRef file;
  final int durationSeconds;
  final String label;
  final TelegramGateway gateway;

  /// A voice message; music otherwise. Each plays on among its own kind.
  final bool isVoice;

  /// The app's one sound; tests hand in their own.
  final AudioSessions? sessions;

  /// The file loads ahead without playing, so a tap plays it at once
  /// ([AutoDownloadPolicy.file]).
  final bool autoLoad;

  @override
  State<AudioView> createState() => _AudioViewState();
}

class _AudioViewState extends State<AudioView> {
  bool _requested = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AudioView old) {
    super.didUpdateWidget(old);
    if (widget.autoLoad && (!old.autoLoad || old.file.id != widget.file.id)) {
      _load();
    }
  }

  void _load() {
    if (!widget.autoLoad || widget.file.isDownloaded) return;
    widget.gateway
        .download(widget.file, priority: 1)
        .then<void>(
          (_) {},
          onError: (Object e) {
            debugPrint('media: preload ${widget.file.id}: $e');
          },
        );
  }

  AudioSessions get _sessions => widget.sessions ?? AudioSessions.instance;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AudioTrack?>(
    valueListenable: _sessions.track,
    builder: (context, track, _) => _row(
      context,
      // The session played on to this one by itself: the row shows it as playing.
      current: track?.id == widget.file.id,
    ),
  );

  Widget _row(BuildContext context, {required bool current}) {
    final l10n = context.l10n;
    final label = widget.label.isEmpty ? l10n.mediaAudio : widget.label;
    final queue = AudioQueue.maybeOf(context);
    if (!_requested && !current) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: IconButton.filled(
          tooltip: l10n.postPlay,
          onPressed: () => setState(() => _requested = true),
          icon: const Icon(Icons.play_arrow),
        ),
        title: Text(label),
        subtitle: Text(formatDuration(widget.durationSeconds)),
      );
    }
    return Downloaded(
      file: widget.file,
      gateway: widget.gateway,
      // The same row while it loads, with the ring where the play button was: the
      // bubble kept changing shape three times on the way to playing.
      pending: (context, start, progress, started) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: SizedBox.square(
          dimension: 40,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: CircularProgressIndicator(value: progress, strokeWidth: 2),
          ),
        ),
        title: Text(label),
        subtitle: Text(formatDuration(widget.durationSeconds)),
      ),
      builder: (context, path) => AudioPlayerWidget(
        path: path,
        label: label,
        durationSeconds: widget.durationSeconds,
        sessions: widget.sessions,
        id: widget.file.id,
        isVoice: widget.isVoice,
        queue: queue == null ? null : () => queue.items(voice: widget.isVoice),
        // Only a tap on this row starts it; a row whose track already plays is drawn
        // as it is.
        autoStart: _requested,
      ),
    );
  }
}

class DocumentView extends StatelessWidget {
  const DocumentView({
    super.key,
    required this.file,
    required this.fileName,
    required this.mimeType,
    required this.gateway,
    this.autoStart = false,
    this.thumbnail,
  });
  final FileRef file;
  final String fileName;
  final String mimeType;
  final TelegramGateway gateway;

  /// Telegram's preview of the file (the first page of a PDF, a picture sent as a file).
  final FileRef? thumbnail;

  /// Loads without a tap: within the file limit of the connection ([AutoDownloadPolicy]).
  final bool autoStart;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Downloaded(
      file: file,
      gateway: gateway,
      autoStart: autoStart,
      pending: (context, start, progress, started) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: SizedBox.square(
          dimension: 40,
          child: started
              ? Padding(
                  padding: const EdgeInsets.all(6),
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 2,
                  ),
                )
              : FileThumbnail(thumbnail: thumbnail, gateway: gateway),
        ),
        title: Text(fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          started
              ? l10n.postDownloading
              : file.size > 0
              ? l10n.postFileTapToDownload(formatBytes(file.size))
              : l10n.postTapToDownload,
        ),
        onTap: started ? null : start,
      ),
      builder: (context, path) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: SizedBox.square(
          dimension: 40,
          child: FileThumbnail(thumbnail: thumbnail, gateway: gateway),
        ),
        title: Text(fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          file.size > 0 ? formatBytes(file.size) : l10n.postOnThisDevice,
        ),
        // A tap opens the file in the app the phone has for it, as in the official app;
        // the button beside it hands the file to an app of the reader's choice.
        onTap: () => unawaited(openDownloadedFile(context, path, mimeType)),
        // The app has no viewer of its own for documents; another app opens it.
        trailing: IconButton(
          tooltip: l10n.postOpenWith,
          icon: const Icon(Icons.open_in_new),
          onPressed: () => unawaited(
            SharePlus.instance.share(
              ShareParams(files: [XFile(path, name: fileName)]),
            ),
          ),
        ),
      ),
    );
  }
}

/// The little picture at the head of a file row: Telegram's preview of the file when it
/// has one, the paper icon otherwise.
class FileThumbnail extends StatelessWidget {
  const FileThumbnail({
    super.key,
    required this.thumbnail,
    required this.gateway,
    this.iconSize = 24,
  });
  final FileRef? thumbnail;
  final TelegramGateway gateway;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(Icons.insert_drive_file_outlined, size: iconSize);
    final file = thumbnail;
    if (file == null) return icon;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Downloaded(
        key: ValueKey(file.id),
        file: file,
        gateway: gateway,
        placeholder: Center(child: icon),
        builder: (context, path) =>
            SizedFileImage(path: path, width: file.width, height: file.height),
      ),
    );
  }
}

/// Opens a downloaded file in the app the phone has for its kind; says so when it has
/// none.
Future<void> openDownloadedFile(
  BuildContext context,
  String path,
  String mimeType,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final l10n = context.l10n;
  var opened = false;
  try {
    opened =
        await const MethodChannel('tf/app')
            .invokeMethod<bool>('openFile', {'path': path, 'mime': mimeType}) ??
        false;
  } on PlatformException {
    opened = false;
  } on MissingPluginException {
    opened = false;
  }
  if (!opened) {
    messenger?.showSnackBar(SnackBar(content: Text(l10n.postNoAppForFile)));
  }
}

String formatDuration(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  final h = m ~/ 60;
  if (h > 0) {
    return '$h:${(m % 60).toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Bytes as the official app writes them: 12 KB, 3.4 MB.
String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return i == 0
      ? '$bytes B'
      : '${v.toStringAsFixed(v >= 10 ? 0 : 1)} ${units[i]}';
}
