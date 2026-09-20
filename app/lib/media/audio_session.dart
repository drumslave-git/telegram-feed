import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// What plays sound, behind an interface so tests can drive it without the plugin, the way
/// `Speaker` stands in front of the text-to-speech engine.
abstract interface class AudioEngine {
  Future<void> open(String path);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setSpeed(double speed);

  /// Where the sound is now, while it plays.
  Stream<Duration> get position;

  /// Whether sound is coming out.
  Stream<bool> get playing;

  /// Length of the open file once it is known.
  Duration? get duration;
  Future<void> dispose();
}

/// The default engine: `just_audio`.
class JustAudioEngine implements AudioEngine {
  final _player = AudioPlayer();

  @override
  Future<void> open(String path) => _player.setFilePath(path).then((_) {});

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Stream<Duration> get position => _player.positionStream;

  @override
  Stream<bool> get playing => _player.playingStream;

  @override
  Duration? get duration => _player.duration;

  @override
  Future<void> dispose() => _player.dispose();
}

/// What is playing: the file, what to call it, and how long it is.
class AudioTrack {
  const AudioTrack({
    required this.path,
    required this.label,
    required this.durationSeconds,
  });
  final String path;
  final String label;
  final int durationSeconds;
}

/// The one sound of the app. Voice messages and music play through it, so a post that
/// scrolls away keeps playing (H-20) and a bar can say what is on, and only one thing is
/// ever heard at a time. Speeds are the official app's: 1×, 1.5×, 2×.
class AudioSessions {
  AudioSessions({AudioEngine Function()? engine})
    : _make = engine ?? JustAudioEngine.new;
  final AudioEngine Function() _make;

  /// The app's own; tests make their own instance instead.
  static AudioSessions instance = AudioSessions();

  static const speeds = [1.0, 1.5, 2.0];

  AudioEngine? _engine;

  /// The track that is open, playing or paused; null when nothing is.
  final track = ValueNotifier<AudioTrack?>(null);
  final playing = ValueNotifier<bool>(false);
  final position = ValueNotifier<Duration>(Duration.zero);
  final speed = ValueNotifier<double>(1);
  final error = ValueNotifier<String?>(null);
  final _subs = <StreamSubscription<Object?>>[];

  /// Length the engine reports, or what the post said.
  Duration get length {
    final known = _engine?.duration;
    if (known != null && known > Duration.zero) return known;
    return Duration(seconds: track.value?.durationSeconds ?? 0);
  }

  bool isCurrent(String path) => track.value?.path == path;

  /// Plays [path] from the beginning, or carries on with it when it is already the one.
  Future<void> play(AudioTrack next) async {
    if (isCurrent(next.path)) {
      await resume();
      return;
    }
    await _release();
    final engine = _make();
    _engine = engine;
    track.value = next;
    error.value = null;
    position.value = Duration.zero;
    _subs.add(engine.position.listen((p) => position.value = p));
    _subs.add(engine.playing.listen((p) => playing.value = p));
    try {
      await engine.open(next.path);
      await engine.setSpeed(speed.value);
      await engine.play();
    } on Object catch (e) {
      error.value = '$e';
      playing.value = false;
    }
  }

  Future<void> resume() async {
    if (_engine == null) return;
    // At the end: start again, as the official app does.
    if (length > Duration.zero && position.value >= length) {
      await seek(Duration.zero);
    }
    await _engine!.play();
  }

  Future<void> pause() async => _engine?.pause();

  Future<void> toggle() async => playing.value ? await pause() : await resume();

  Future<void> seek(Duration to) async {
    position.value = to;
    await _engine?.seek(to);
  }

  /// The next speed of [speeds], round and round, as the official app's button does.
  Future<double> nextSpeed() async {
    final i = speeds.indexOf(speed.value);
    final next = speeds[(i + 1) % speeds.length];
    speed.value = next;
    await _engine?.setSpeed(next);
    return next;
  }

  /// Stops, and forgets what was playing: the bar goes away with it.
  Future<void> stop() async {
    await _release();
    track.value = null;
    playing.value = false;
    position.value = Duration.zero;
  }

  Future<void> _release() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    final engine = _engine;
    _engine = null;
    await engine?.dispose();
  }
}
