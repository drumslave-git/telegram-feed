import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// Stands in for ExoPlayer in widget tests: every player initialises at once as a 100 second,
/// 640x360 video and remembers what it was told.
class FakeVideoPlatform extends VideoPlayerPlatform {
  final sources = <DataSource>[];
  final log = <String>[];
  final positions = <int, Duration>{};
  final _events = <int, StreamController<VideoEvent>>{};

  static FakeVideoPlatform install() {
    final p = FakeVideoPlatform();
    VideoPlayerPlatform.instance = p;
    return p;
  }

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    sources.add(options.dataSource);
    final id = sources.length;
    positions[id] = Duration.zero;
    _events[id] = StreamController<VideoEvent>()
      ..add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(seconds: 100),
          size: const Size(640, 360),
        ),
      );
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
  Future<void> setLooping(int playerId, bool looping) async {}
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
