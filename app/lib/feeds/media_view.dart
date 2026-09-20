import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:telegram_gateway/telegram_gateway.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../media/autoplay.dart';
import '../media/media_viewer.dart';
import '../media/video_downloads.dart';
import '../media/video_sessions.dart';
import '../media/video_stage.dart';
import 'players.dart';
import 'sticker_view.dart';

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

  @override
  Widget build(BuildContext context) => switch (media) {
    PhotoMedia(:final sizes) => PhotoView(
      file: pickPhotoSize(sizes, MediaQuery.sizeOf(context).width),
      gateway: gateway,
      onTap: onOpen,
      fill: fill,
      radius: radius,
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
            autoplay: AutoplayScope.of(context).allows(video),
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
      autoplay: AutoplayScope.of(context).allows(video),
      onOpen: onOpen,
      fill: fill,
      radius: radius,
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
            ? 'Voice message'
            : [title, performer].where((s) => s.isNotEmpty).join(' – '),
        gateway: gateway,
      ),
    DocumentMedia(:final file, :final fileName, :final mimeType) =>
      DocumentView(
        file: file,
        fileName: fileName,
        mimeType: mimeType,
        gateway: gateway,
      ),
    UnsupportedMedia(:final tdType) => Chip(
      label: Text(tdType.replaceFirst('message', '')),
      visualDensity: VisualDensity.compact,
    ),
  };
}

/// Smallest size that is at least as wide as the viewport (or the largest available).
FileRef pickPhotoSize(List<FileRef> sizes, double viewportWidth) {
  const dpr = 2.0;
  for (final s in sizes) {
    if (s.width >= viewportWidth * dpr) return s;
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
  });
  final FileRef file;
  final TelegramGateway gateway;
  final Widget Function(BuildContext context, String path) builder;
  final bool autoStart;
  final Widget? placeholder;

  @override
  State<Downloaded> createState() => _DownloadedState();
}

class _DownloadedState extends State<Downloaded> {
  String? _path;
  double? _progress;
  bool _started = false;
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
    if (old.file.id == widget.file.id) return;
    _sub?.cancel();
    _started = false;
    _progress = null;
    _error = null;
    _path = widget.file.isDownloaded ? widget.file.localPath : null;
    if (_path == null && widget.autoStart) start();
  }

  Future<void> start() async {
    if (_started) return;
    setState(() => _started = true);
    final file = widget.file;
    final sub = _sub = widget.gateway.fileProgress(file.id).listen((p) {
      if (!mounted || widget.file.id != file.id) return;
      setState(() => _progress = p.total > 0 ? p.downloaded / p.total : null);
    });
    try {
      final done = await widget.gateway.download(file);
      if (mounted && widget.file.id == file.id) {
        setState(() => _path = done.localPath);
      }
    } on TelegramException catch (e) {
      if (mounted && widget.file.id == file.id) {
        setState(() => _error = e.message);
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
    if (_error != null) {
      return Text(
        'Download failed: $_error',
        style: Theme.of(context).textTheme.bodySmall,
      );
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
              Text(_started ? 'Downloading…' : 'Tap to download'),
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
  });
  final FileRef file;
  final TelegramGateway gateway;
  final VoidCallback? onTap;
  final bool fill;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final aspect = file.width > 0 && file.height > 0
        ? file.width / file.height
        : 4 / 3;
    final picture = Downloaded(
      file: file,
      gateway: gateway,
      placeholder: const ColoredBox(
        color: Colors.black12,
        child: Center(child: CircularProgressIndicator()),
      ),
      builder: (context, path) => Image.file(
        File(path),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
      ),
    );
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: fill
            ? SizedBox.expand(child: picture)
            : AspectRatio(
                aspectRatio: aspect.clamp(mediaMinAspect, mediaMaxAspect),
                child: picture,
              ),
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
/// the official app does; the timeline itself only shows muted autoplay ([AutoplayPolicy]),
/// and a tap on that opens the viewer with sound too.
class VideoView extends StatefulWidget {
  const VideoView({
    super.key,
    required this.video,
    required this.gateway,
    this.autoplay = false,
    this.onOpen,
    this.fill = false,
    this.radius = 8,
  });
  final VideoMedia video;
  final TelegramGateway gateway;

  /// See [MediaView.fill] and [MediaView.radius].
  final bool fill;
  final double radius;

  /// Starts muted once most of it is visible ([AutoplayPolicy]).
  final bool autoplay;

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
  }

  @override
  void didUpdateWidget(VideoView old) {
    super.didUpdateWidget(old);
    if (old.video.file.id != _file.id) {
      _session?.release();
      _session = null;
      _adopt(_sessions.find(_file.id));
    }
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

  void _open() {
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
      ? const ColoredBox(color: Colors.black26)
      : Downloaded(
          key: ValueKey(widget.video.thumbnail!.id),
          file: widget.video.thumbnail!,
          gateway: widget.gateway,
          placeholder: const ColoredBox(color: Colors.black26),
          builder: (context, path) => Image.file(
            File(path),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
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
            Positioned(
              right: 6,
              bottom: 6,
              child: MediaBadge(
                widget.video.isAnimation
                    ? 'GIF'
                    : formatDuration(widget.video.durationSeconds),
              ),
            ),
          ],
          // Too much for a small cell of an album; the viewer has the button as well.
          if (!fill)
            Positioned(
              left: 8,
              top: 8,
              child: VideoDownloadButton(file: _file, gateway: widget.gateway),
            ),
        ],
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: fill
          ? SizedBox.expand(child: content)
          : AspectRatio(
              aspectRatio: aspect.clamp(mediaMinAspect, mediaMaxAspect),
              child: content,
            ),
    );
  }
}

/// The round, see-through play button of the official app.
class _PlayBadge extends StatelessWidget {
  const _PlayBadge({required this.size, required this.onPressed});
  final double size;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Play',
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
  });
  final FileRef file;
  final int durationSeconds;
  final String label;
  final TelegramGateway gateway;

  @override
  State<AudioView> createState() => _AudioViewState();
}

class _AudioViewState extends State<AudioView> {
  bool _requested = false;

  @override
  Widget build(BuildContext context) {
    if (!_requested) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: IconButton.filled(
          tooltip: 'Play',
          onPressed: () => setState(() => _requested = true),
          icon: const Icon(Icons.play_arrow),
        ),
        title: Text(widget.label.isEmpty ? 'Audio' : widget.label),
        subtitle: Text(formatDuration(widget.durationSeconds)),
      );
    }
    return Downloaded(
      file: widget.file,
      gateway: widget.gateway,
      builder: (context, path) => AudioPlayerWidget(
        path: path,
        label: widget.label.isEmpty ? 'Audio' : widget.label,
        durationSeconds: widget.durationSeconds,
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
  });
  final FileRef file;
  final String fileName;
  final String mimeType;
  final TelegramGateway gateway;

  @override
  Widget build(BuildContext context) {
    return Downloaded(
      file: file,
      gateway: gateway,
      autoStart: false,
      builder: (context, path) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.insert_drive_file_outlined),
        title: Text(fileName),
        subtitle: Text(
          'Saved: $path',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
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
