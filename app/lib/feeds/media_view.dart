import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:telegram_gateway/telegram_gateway.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../media/autoplay.dart';
import '../media/video_sessions.dart';
import '../media/video_stage.dart';
import 'players.dart';

/// Renders one post's media inline. Files are TDLib-managed: [gateway.download] returns the
/// local path and [gateway.fileProgress] reports progress while it downloads.
class MediaView extends StatelessWidget {
  const MediaView({
    super.key,
    required this.media,
    required this.gateway,
    this.onOpenPhoto,
  });
  final Media media;
  final TelegramGateway gateway;

  /// Tap on a photo (the timeline opens the full-screen viewer).
  final VoidCallback? onOpenPhoto;

  @override
  Widget build(BuildContext context) => switch (media) {
    PhotoMedia(:final sizes) => PhotoView(
      file: _pickSize(sizes, MediaQuery.sizeOf(context).width),
      gateway: gateway,
      onTap: onOpenPhoto,
    ),
    final VideoMedia video => VideoView(
      video: video,
      gateway: gateway,
      autoplay: AutoplayScope.of(context).allows(video),
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

  /// Smallest size that is at least as wide as the viewport (or the largest available).
  static FileRef _pickSize(List<FileRef> sizes, double viewportWidth) {
    final dpr = 2.0;
    for (final s in sizes) {
      if (s.width >= viewportWidth * dpr) return s;
    }
    return sizes.last;
  }
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
  });
  final FileRef file;
  final TelegramGateway gateway;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final aspect = file.width > 0 && file.height > 0
        ? file.width / file.height
        : 4 / 3;
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: AspectRatio(
          aspectRatio: aspect.clamp(0.5, 2.5),
          child: Downloaded(
            file: file,
            gateway: gateway,
            placeholder: const ColoredBox(
              color: Colors.black12,
              child: Center(child: CircularProgressIndicator()),
            ),
            builder: (context, path) => Image.file(
              File(path),
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
          ),
        ),
      ),
    );
  }
}

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
  });
  final VideoMedia video;
  final TelegramGateway gateway;

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

  void _adopt(VideoSession? s) {
    if (s == null || !s.autoplay) return;
    s.retain();
    _session = s;
  }

  void _open() {
    final onOpen = widget.onOpen;
    if (onOpen != null) return onOpen();
    unawaited(
      FullscreenVideoScreen.open(
        context,
        video: widget.video,
        gateway: widget.gateway,
        poster: _poster(BoxFit.contain),
      ),
    );
  }

  /// Autoplay starts when most of the video is on screen and pauses once little of it is
  /// left, unless the viewer is showing it.
  void _onVisibility(VisibilityInfo info) {
    if (!mounted) return;
    final visible = info.visibleFraction;
    final s = _session;
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

  Widget _poster(BoxFit fit) => widget.video.thumbnail == null
      ? const ColoredBox(color: Colors.black26)
      : Downloaded(
          key: ValueKey(widget.video.thumbnail!.id),
          file: widget.video.thumbnail!,
          gateway: widget.gateway,
          placeholder: const ColoredBox(color: Colors.black26),
          builder: (context, path) => Image.file(File(path), fit: fit),
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: AspectRatio(
        aspectRatio: aspect.clamp(0.5, 2.5),
        child: GestureDetector(
          onTap: _open,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (session != null)
                InlineVideo(session: session, poster: _poster(BoxFit.cover))
              else ...[
                _poster(BoxFit.cover),
                Center(
                  child: IconButton.filled(
                    iconSize: 40,
                    tooltip: 'Play',
                    onPressed: _open,
                    icon: const Icon(Icons.play_arrow),
                  ),
                ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Chip(
                    label: Text(
                      widget.video.isAnimation
                          ? 'GIF'
                          : formatDuration(widget.video.durationSeconds),
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
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
