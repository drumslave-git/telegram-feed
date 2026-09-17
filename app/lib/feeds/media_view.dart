import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'players.dart';

/// Renders one post's media inline. Files are TDLib-managed: [gateway.download] returns the
/// local path and [gateway.fileProgress] reports progress while it downloads.
class MediaView extends StatelessWidget {
  const MediaView({super.key, required this.media, required this.gateway});
  final Media media;
  final TelegramGateway gateway;

  @override
  Widget build(BuildContext context) => switch (media) {
    PhotoMedia(:final sizes) => PhotoView(
      file: _pickSize(sizes, MediaQuery.sizeOf(context).width),
      gateway: gateway,
    ),
    VideoMedia(
      :final file,
      :final thumbnail,
      :final durationSeconds,
      :final isAnimation,
    ) =>
      VideoView(
        file: file,
        thumbnail: thumbnail,
        durationSeconds: durationSeconds,
        isAnimation: isAnimation,
        gateway: gateway,
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

  Future<void> start() async {
    if (_started) return;
    setState(() => _started = true);
    _sub = widget.gateway.fileProgress(widget.file.id).listen((p) {
      if (!mounted) return;
      setState(() => _progress = p.total > 0 ? p.downloaded / p.total : null);
    });
    try {
      final done = await widget.gateway.download(widget.file);
      if (mounted) setState(() => _path = done.localPath);
    } on TelegramException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      await _sub?.cancel();
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
  const PhotoView({super.key, required this.file, required this.gateway});
  final FileRef file;
  final TelegramGateway gateway;

  @override
  Widget build(BuildContext context) {
    final aspect = file.width > 0 && file.height > 0
        ? file.width / file.height
        : 4 / 3;
    return ClipRRect(
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
          builder: (context, path) =>
              Image.file(File(path), fit: BoxFit.cover, gaplessPlayback: true),
        ),
      ),
    );
  }
}

/// Thumbnail with a play button; downloads and plays inline on tap.
class VideoView extends StatefulWidget {
  const VideoView({
    super.key,
    required this.file,
    required this.thumbnail,
    required this.durationSeconds,
    required this.isAnimation,
    required this.gateway,
  });
  final FileRef file;
  final FileRef? thumbnail;
  final int durationSeconds;
  final bool isAnimation;
  final TelegramGateway gateway;

  @override
  State<VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<VideoView> {
  bool _playing = false;

  @override
  Widget build(BuildContext context) {
    final aspect = widget.file.width > 0 && widget.file.height > 0
        ? widget.file.width / widget.file.height
        : 16 / 9;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: AspectRatio(
        aspectRatio: aspect.clamp(0.5, 2.5),
        child: _playing
            ? Downloaded(
                file: widget.file,
                gateway: widget.gateway,
                placeholder: const ColoredBox(
                  color: Colors.black87,
                  child: Center(child: CircularProgressIndicator()),
                ),
                builder: (context, path) =>
                    VideoPlayerWidget(path: path, loop: widget.isAnimation),
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  if (widget.thumbnail != null)
                    Downloaded(
                      file: widget.thumbnail!,
                      gateway: widget.gateway,
                      placeholder: const ColoredBox(color: Colors.black26),
                      builder: (context, path) =>
                          Image.file(File(path), fit: BoxFit.cover),
                    )
                  else
                    const ColoredBox(color: Colors.black26),
                  Center(
                    child: IconButton.filled(
                      iconSize: 40,
                      tooltip: 'Play',
                      onPressed: () => setState(() => _playing = true),
                      icon: const Icon(Icons.play_arrow),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Chip(
                      label: Text(
                        widget.isAnimation
                            ? 'GIF'
                            : formatDuration(widget.durationSeconds),
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
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
