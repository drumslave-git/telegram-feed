import 'dart:async';

import 'package:flutter/material.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../settings/settings_screen.dart' show formatBytes;
import 'video_sessions.dart';

enum DownloadPhase { idle, downloading, done }

/// Downloads the user asked for with the button on a video: the whole file goes into
/// Telegram's cache, so that it plays at once and offline later. Unlike the download that
/// feeds a playing video, this one goes on when the viewer closes.
final class VideoDownloads extends ChangeNotifier {
  VideoDownloads(this.gateway);

  static final _instances = Expando<VideoDownloads>();
  static VideoDownloads of(TelegramGateway gateway) =>
      _instances[gateway] ??= VideoDownloads(gateway);

  final TelegramGateway gateway;
  final _wanted = <int, _Wanted>{};
  final _done = <int>{};

  /// The user asked for the file; playback ending must not cancel its download.
  bool wants(int fileId) => _wanted.containsKey(fileId);

  DownloadPhase phase(FileRef file) =>
      file.isDownloaded || _done.contains(file.id)
      ? DownloadPhase.done
      : wants(file.id)
      ? DownloadPhase.downloading
      : DownloadPhase.idle;

  /// Bytes on disk while [phase] is downloading.
  int downloaded(int fileId) => _wanted[fileId]?.downloaded ?? 0;
  String? error(int fileId) => _errors[fileId];
  final _errors = <int, String>{};

  /// The post's [FileRef] is as old as the post: finds out whether TDLib got the whole file
  /// since (an earlier download, or a video that was watched to the end).
  Future<void> check(FileRef file) async {
    if (file.size <= 0 || phase(file) != DownloadPhase.idle) return;
    try {
      if (await gateway.downloadedPrefix(file.id, 0) >= file.size) {
        _done.add(file.id);
        notifyListeners();
      }
    } on TelegramException {
      // Unknown stays "not downloaded"; the button finds out when it is tapped.
    }
  }

  Future<void> start(FileRef file) async {
    if (phase(file) != DownloadPhase.idle) return;
    _errors.remove(file.id);
    final w = _wanted[file.id] = _Wanted();
    w.sub = gateway
        .fileProgress(file.id)
        .listen((p) => _onProgress(file.id, p));
    notifyListeners();
    // A video that is playing already pulls the whole file; aiming the download at the
    // start would only take it away from where the player reads.
    if (VideoSessions.of(gateway).find(file.id) != null) return;
    try {
      _onProgress(file.id, await gateway.downloadFrom(file.id, priority: 16));
    } on TelegramException catch (e) {
      _drop(file.id);
      _errors[file.id] = e.message;
      notifyListeners();
    }
  }

  void _onProgress(int fileId, FileProgress p) {
    final w = _wanted[fileId];
    if (w == null) return;
    if (p.isComplete) {
      _drop(fileId);
      _done.add(fileId);
    } else {
      w.downloaded = p.downloaded;
    }
    notifyListeners();
  }

  /// Keeps what is on disk; a later download goes on from there.
  Future<void> cancel(int fileId) async {
    if (!wants(fileId)) return;
    _drop(fileId);
    notifyListeners();
    // A playing video still needs its download; it is cancelled with the player.
    if (VideoSessions.of(gateway).find(fileId) != null) return;
    try {
      await gateway.cancelDownload(fileId);
    } on TelegramException catch (e) {
      debugPrint('media: cancel $fileId: ${e.message}');
    }
  }

  void _drop(int fileId) => _wanted.remove(fileId)?.sub?.cancel();
}

class _Wanted {
  StreamSubscription<FileProgress>? sub;
  int downloaded = 0;
}

/// The pill in the top left corner of a video, as in the official app: an arrow and the size
/// while the file is not on the device, a progress ring that cancels while it downloads,
/// nothing once it is there.
class VideoDownloadButton extends StatefulWidget {
  const VideoDownloadButton({
    super.key,
    required this.file,
    required this.gateway,
  });
  final FileRef file;
  final TelegramGateway gateway;

  @override
  State<VideoDownloadButton> createState() => _VideoDownloadButtonState();
}

class _VideoDownloadButtonState extends State<VideoDownloadButton> {
  VideoDownloads get _downloads => VideoDownloads.of(widget.gateway);

  @override
  void initState() {
    super.initState();
    unawaited(_downloads.check(widget.file));
  }

  @override
  void didUpdateWidget(VideoDownloadButton old) {
    super.didUpdateWidget(old);
    if (old.file.id != widget.file.id) unawaited(_downloads.check(widget.file));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _downloads,
    builder: (context, _) {
      final file = widget.file;
      final phase = _downloads.phase(file);
      if (phase == DownloadPhase.done) return const SizedBox.shrink();
      final downloading = phase == DownloadPhase.downloading;
      final got = _downloads.downloaded(file.id);
      final label = _downloads.error(file.id) != null
          ? 'Failed, try again'
          : downloading && file.size > 0
          ? '${formatBytes(got)} / ${formatBytes(file.size)}'
          : file.size > 0
          ? formatBytes(file.size)
          : '';
      return Tooltip(
        message: downloading ? 'Cancel download' : 'Download',
        child: Material(
          color: Colors.black54,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => downloading
                ? _downloads.cancel(file.id)
                : _downloads.start(file),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 10, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 22,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (downloading)
                          CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                            value: file.size > 0 && got > 0
                                ? got / file.size
                                : null,
                          ),
                        Icon(
                          downloading ? Icons.close : Icons.arrow_downward,
                          color: Colors.white,
                          size: downloading ? 14 : 18,
                        ),
                      ],
                    ),
                  ),
                  if (label.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
