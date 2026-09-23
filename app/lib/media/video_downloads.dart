import 'dart:async';

import 'package:flutter/material.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../settings/settings_screen.dart' show formatBytes;
import 'video_sessions.dart';
import 'video_stage.dart';

enum DownloadPhase { idle, downloading, done }

/// Downloads the user asked for with the button on a video, and the ones the automatic
/// downloads start by themselves: the whole file goes into Telegram's cache, so that it plays
/// at once and offline later. Unlike the download that feeds a playing video, this one goes
/// on when the viewer closes.
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

  /// Files the reader stopped by hand: they do not start by themselves again in this run.
  final _declined = <int>{};

  /// Files whose first seconds were asked for already.
  final _preloaded = <int>{};

  /// How much of a larger video is loaded ahead: a few seconds of it.
  static const preloadBytes = 2 * 1024 * 1024;

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

  /// [auto] is the automatic download of a video within the limit: it shows on the pill
  /// like one the user asked for, but one the user stopped stays stopped.
  Future<void> start(FileRef file, {bool auto = false}) async {
    if (auto && _declined.contains(file.id)) return;
    if (phase(file) != DownloadPhase.idle) return;
    if (!auto) _declined.remove(file.id);
    _errors.remove(file.id);
    final w = _wanted[file.id] = _Wanted();
    w.sub = gateway
        .fileProgress(file.id)
        .listen((p) => _onProgress(file.id, p));
    notifyListeners();
    if (auto) debugPrint('media: ${file.id} loads by itself (${file.size} B)');
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

  /// The first seconds of a video too large to load by itself (the official app's "Preload
  /// larger videos"). Nothing shows for it; a download or a player later takes over the
  /// same file from where it got.
  Future<void> preload(FileRef file) async {
    if (phase(file) != DownloadPhase.idle || !_preloaded.add(file.id)) return;
    if (VideoSessions.of(gateway).find(file.id) != null) return;
    debugPrint('media: ${file.id} first $preloadBytes B loaded ahead');
    try {
      await gateway.downloadFrom(file.id, priority: 1, limit: preloadBytes);
    } on TelegramException catch (e) {
      debugPrint('media: preload ${file.id}: ${e.message}');
    }
  }

  /// The file got complete some other way: a video streamed it to the end while it played.
  void markComplete(int fileId) {
    if (_done.contains(fileId)) return;
    _drop(fileId);
    _done.add(fileId);
    notifyListeners();
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
    _declined.add(fileId);
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
    this.compact = false,
  });
  final FileRef file;
  final TelegramGateway gateway;

  /// In the viewer's top bar, where the size has no room: the ring alone while the file
  /// downloads and nothing otherwise, because [menuActions] is where a download is asked
  /// for.
  final bool compact;

  /// The same download as lines of the viewer's menu.
  static List<ViewerAction> menuActions(FileRef file, TelegramGateway gateway) {
    final downloads = VideoDownloads.of(gateway);
    return switch (downloads.phase(file)) {
      DownloadPhase.done => const [],
      DownloadPhase.downloading => [
        ViewerAction(
          'Cancel download',
          () => unawaited(downloads.cancel(file.id)),
        ),
      ],
      DownloadPhase.idle => [
        ViewerAction(
          file.size > 0 ? 'Download (${formatBytes(file.size)})' : 'Download',
          () => unawaited(downloads.start(file)),
        ),
      ],
    };
  }

  @override
  State<VideoDownloadButton> createState() => _VideoDownloadButtonState();
}

class _VideoDownloadButtonState extends State<VideoDownloadButton> {
  VideoDownloads get _downloads => VideoDownloads.of(widget.gateway);
  StreamSubscription<FileProgress>? _completion;

  @override
  void initState() {
    super.initState();
    _watch();
  }

  @override
  void didUpdateWidget(VideoDownloadButton old) {
    super.didUpdateWidget(old);
    if (old.file.id != widget.file.id) _watch();
  }

  @override
  void dispose() {
    _completion?.cancel();
    super.dispose();
  }

  /// Whether the file is complete by now, and the moment it gets complete while the button
  /// shows: a short video that autoplays under it is streamed whole within seconds.
  void _watch() {
    _completion?.cancel();
    _completion = null;
    final file = widget.file;
    if (file.isDownloaded) return;
    unawaited(_downloads.check(file));
    final downloads = _downloads;
    _completion = widget.gateway.fileProgress(file.id).listen((p) {
      if (p.isComplete) downloads.markComplete(p.fileId);
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _downloads,
    builder: (context, _) {
      final file = widget.file;
      final phase = _downloads.phase(file);
      if (phase == DownloadPhase.done) return const SizedBox.shrink();
      final downloading = phase == DownloadPhase.downloading;
      if (widget.compact) {
        if (!downloading) return const SizedBox.shrink();
        final got = _downloads.downloaded(file.id);
        return IconButton(
          tooltip: 'Cancel download',
          color: Colors.white,
          onPressed: () => unawaited(_downloads.cancel(file.id)),
          icon: SizedBox.square(
            dimension: 22,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                  value: file.size > 0 && got > 0 ? got / file.size : null,
                ),
                const Icon(Icons.close, color: Colors.white, size: 14),
              ],
            ),
          ),
        );
      }
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
