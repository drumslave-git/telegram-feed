import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:telegram_feed/media/video_positions.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// Stands in for ExoPlayer in widget tests: every player initialises at once as a 640x360
/// video of [duration] (100 seconds unless a test says otherwise) and remembers what it
/// was told.
class FakeVideoPlatform extends VideoPlayerPlatform {
  /// How long the players created from now on say their video is.
  Duration duration = const Duration(seconds: 100);

  /// Set, a player that is created stays loading: it does not say it is initialised.
  bool loadsForever = false;

  /// Whether each player was last told to loop.
  final looping = <int, bool>{};
  final sources = <DataSource>[];
  final log = <String>[];
  final positions = <int, Duration>{};
  final _events = <int, StreamController<VideoEvent>>{};

  static FakeVideoPlatform install() {
    final p = FakeVideoPlatform();
    VideoPlayerPlatform.instance = p;
    // Where a test before this one left its videos is nothing to this one.
    unawaited(VideoPositions.wipe());
    return p;
  }

  /// The video of [playerId] plays to its end, as ExoPlayer reports it for a video that
  /// does not loop.
  void finish(int playerId) {
    positions[playerId] = duration;
    _events[playerId]!.add(VideoEvent(eventType: VideoEventType.completed));
  }

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    sources.add(options.dataSource);
    final id = sources.length;
    positions[id] = Duration.zero;
    _events[id] = StreamController<VideoEvent>();
    if (!loadsForever) {
      _events[id]!.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: duration,
          size: const Size(640, 360),
        ),
      );
    }
    return id;
  }

  @override
  Future<int?> create(DataSource dataSource) => createWithOptions(
    VideoCreationOptions(
      dataSource: dataSource,
      viewType: VideoViewType.textureView,
    ),
  );

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async {
    log.add('dispose $playerId');
    await _events.remove(playerId)?.close();
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {
    this.looping[playerId] = looping;
  }

  @override
  Future<void> play(int playerId) async => log.add('play $playerId');
  @override
  Future<void> pause(int playerId) async => log.add('pause $playerId');
  @override
  Future<void> setVolume(int playerId, double volume) async =>
      log.add('volume $playerId $volume');
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async =>
      log.add('speed $playerId $speed');
  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    positions[playerId] = position;
    log.add('seek $playerId ${position.inSeconds}');
  }

  @override
  Future<Duration> getPosition(int playerId) async => positions[playerId]!;

  @override
  Widget buildView(int playerId) => const SizedBox.expand();
  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox.expand();
}
