import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:telegram_gateway/telegram_gateway.dart';
import 'package:video_player/video_player.dart';

import 'media_server.dart';
import 'video_downloads.dart';

/// Playback of one video file. Lives outside the widget tree so that the inline player, the
/// full-screen player and a list row that was rebuilt all drive the same player instead of
/// each starting their own.
final class VideoSession extends ChangeNotifier {
  VideoSession._(
    this._owner,
    this.file, {
    required this.loop,
    required this._muted,
    required this.autoplay,
  });

  final VideoSessions _owner;
  final FileRef file;
  final bool loop;

  /// Started by scrolling into view, not by a tap: muted, and paused again when out of view.
  final bool autoplay;

  VideoPlayerController? _controller;
  String? _error;
  bool _muted;
  bool _disposed = false;
  int _holders = 0;

  /// Those of [_holders] that watch with sound: the viewer's page and the mini player. One
  /// can hand over to the other (picture-in-picture and back) without the video stopping.
  int _viewerHolds = 0;
  bool _wasPlaying = false;
  Timer? _idle;
  bool _resumeOnRetain = false;

  /// Null until the player is created; check `value.isInitialized` before showing it.
  VideoPlayerController? get controller => _controller;
  String? get error => _error;
  bool get muted => _muted;
  bool get isReady => _controller?.value.isInitialized ?? false;

  /// More than one widget shows the session: the full-screen view is open over the row.
  bool get isShared => _holders > 1;

  Future<void> _start() async {
    _error = null;
    notifyListeners();
    final clock = Stopwatch()..start();
    try {
      final c = await _owner._createController(file, mixWithOthers: _muted);
      if (_disposed) {
        await c.dispose();
        return;
      }
      _controller = c;
      c.addListener(_onPlayerValue);
      await c.initialize();
      debugPrint(
        'media: ${file.id} (${file.size} bytes) ready after '
        '${clock.elapsedMilliseconds} ms from ${c.dataSourceType.name}',
      );
      if (_disposed) return;
      await c.setLooping(loop);
      await c.setVolume(_muted ? 0 : 1);
      await play();
    } catch (e) {
      if (_disposed) return;
      _error = e is PlatformException ? (e.message ?? e.code) : '$e';
      notifyListeners();
    }
  }

  void _onPlayerValue() {
    final v = _controller?.value;
    if (v != null && v.hasError && _error == null) _error = v.errorDescription;
    // "Playing" may be set while the player still initializes; it counts once there is a
    // picture, whose size the picture-in-picture window needs.
    final playing = v != null && v.isInitialized && v.isPlaying;
    if (playing != _wasPlaying) {
      _wasPlaying = playing;
      _owner._syncForeground();
    }
    notifyListeners();
  }

  bool get isPlaying => isReady && _controller!.value.isPlaying;

  /// Drops the broken player and tries again.
  Future<void> retry() async {
    final old = _controller;
    _controller = null;
    old?.removeListener(_onPlayerValue);
    await old?.dispose();
    await _start();
  }

  Future<void> play() async {
    if (!_muted) _owner._pauseOthers(this);
    await _controller?.play();
  }

  Future<void> pause() async => _controller?.pause();

  Future<void> togglePlay() =>
      (_controller?.value.isPlaying ?? false) ? pause() : play();

  Future<void> setMuted(bool muted) async {
    _muted = muted;
    if (!muted) _owner._pauseOthers(this);
    await _controller?.setVolume(muted ? 0 : 1);
    notifyListeners();
  }

  /// Seeks relative to the current position, clamped to the video.
  Future<void> seekBy(Duration delta) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    var to = c.value.position + delta;
    if (to < Duration.zero) to = Duration.zero;
    if (to > c.value.duration) to = c.value.duration;
    await c.seekTo(to);
  }

  /// A widget shows this session. Balanced by [release].
  void retain() {
    _holders++;
    _idle?.cancel();
    _idle = null;
    if (_resumeOnRetain) {
      _resumeOnRetain = false;
      unawaited(play());
    }
  }

  /// The widget went away. A row that is only being rebuilt retains again within the grace
  /// period; otherwise playback ends and the unfinished download is cancelled.
  void release() {
    if (--_holders > 0 || _disposed) return;
    _resumeOnRetain = _controller?.value.isPlaying ?? false;
    unawaited(pause());
    _idle = Timer(VideoSessions.gracePeriod, () => _owner._close(this));
  }

  /// The full-screen viewer shows this session: with sound and playing. Called from widget
  /// lifecycle methods, so the player is only touched once the frame is done (listeners
  /// rebuild widgets).
  void retainForViewer() {
    // A video the timeline autoplayed is somewhere in the middle of itself; opening it
    // starts it over (founder decision 2026-09-20). Taking the session over from the mini
    // player or the system window is not an opening: there [_viewerHolds] is already up.
    final fromRow = autoplay && _viewerHolds == 0;
    retain();
    _viewerHolds++;
    scheduleMicrotask(() async {
      if (_disposed) return;
      if (_muted) await setMuted(false);
      if (fromRow) await _controller?.seekTo(Duration.zero);
      await play();
      _owner._syncForeground();
    });
  }

  /// The viewer is done with the session. A video that autoplays in its row goes back to
  /// playing there without sound; anything else stops at once and its streaming download is
  /// cancelled, as the official app does.
  void releaseFromViewer() {
    if (_disposed) return;
    _holders--;
    // Handed over between the viewer and the mini player: the other one goes on watching.
    if (--_viewerHolds > 0) return;
    final backToRow = autoplay && _holders > 0;
    scheduleMicrotask(() async {
      if (_disposed) return;
      _owner._syncForeground();
      if (backToRow) {
        await setMuted(true);
        await play();
      } else if (_holders <= 0) {
        await pause();
        await _owner._close(this);
      }
    });
  }

  Future<void> _dispose() async {
    _disposed = true;
    _idle?.cancel();
    final c = _controller;
    _controller = null;
    c?.removeListener(_onPlayerValue);
    await c?.dispose();
    super.dispose();
  }
}

/// All running [VideoSession]s of one gateway, by file id.
final class VideoSessions {
  VideoSessions(this.gateway) : _server = MediaServer(gateway);

  static final _instances = Expando<VideoSessions>();
  static VideoSessions of(TelegramGateway gateway) =>
      _instances[gateway] ??= VideoSessions(gateway);

  /// How long a session without widgets survives (rows get rebuilt when the list shifts).
  static const gracePeriod = Duration(milliseconds: 800);

  final TelegramGateway gateway;
  final MediaServer _server;
  final _sessions = <int, VideoSession>{};

  /// The video that plays in the viewer or the mini player, if any: what Android's
  /// picture-in-picture window shows when the app is left (`SystemPip`).
  static final foreground = ValueNotifier<VideoSession?>(null);

  void _syncForeground() {
    VideoSession? playing;
    for (final s in _sessions.values) {
      if (s._viewerHolds > 0 && s.isPlaying && !s._disposed) playing = s;
    }
    foreground.value = playing;
  }

  VideoSession? find(int fileId) => _sessions[fileId];

  /// The running session for [file], or a new one that starts playing right away.
  VideoSession open(FileRef file, {bool loop = false, bool autoplay = false}) {
    final existing = _sessions[file.id];
    if (existing != null) return existing;
    final s = VideoSession._(
      this,
      file,
      loop: loop,
      muted: autoplay,
      autoplay: autoplay,
    );
    _sessions[file.id] = s;
    unawaited(s._start());
    return s;
  }

  /// Only one video has sound at a time.
  void _pauseOthers(VideoSession except) {
    for (final s in _sessions.values) {
      if (!identical(s, except) && !s.muted) unawaited(s.pause());
    }
  }

  Future<VideoPlayerController> _createController(
    FileRef file, {
    required bool mixWithOthers,
  }) async {
    final options = VideoPlayerOptions(mixWithOthers: mixWithOthers);
    if (file.isDownloaded) {
      return VideoPlayerController.file(
        File(file.localPath!),
        videoPlayerOptions: options,
      );
    }
    if (file.size <= 0) {
      // Ranges need the size; without one the file is fetched whole first.
      final done = await gateway.download(file, priority: 32);
      return VideoPlayerController.file(
        File(done.localPath!),
        videoPlayerOptions: options,
      );
    }
    // Start the download at once; the player reads behind it through the loopback server.
    final state = await gateway.downloadFrom(file.id);
    if (state.isComplete) {
      return VideoPlayerController.file(
        File(state.localPath!),
        videoPlayerOptions: options,
      );
    }
    return VideoPlayerController.networkUrl(
      await _server.urlFor(file),
      videoPlayerOptions: options,
    );
  }

  Future<void> _close(VideoSession s) async {
    if (s._holders > 0) return;
    _sessions.remove(s.file.id);
    _server.release(s.file.id);
    _syncForeground();
    await s._dispose();
    final downloads = VideoDownloads.of(gateway);
    // A download the user asked for with the button goes on without the player.
    if (s.file.isDownloaded || downloads.wants(s.file.id)) return;
    // Watched to the end, the file is complete and the button can go.
    await downloads.check(s.file);
    if (downloads.phase(s.file) == DownloadPhase.done) return;
    try {
      await gateway.cancelDownload(s.file.id);
      debugPrint('media: ${s.file.id} closed, streaming download cancelled');
    } on TelegramException catch (e) {
      debugPrint('media: cancel ${s.file.id}: ${e.message}');
    }
  }
}
