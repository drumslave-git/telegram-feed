import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
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

  /// Fires when the file has played to its end.
  Stream<void> get completed;

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
  Stream<void> get completed => _player.processingStateStream.where(
    (s) => s == ProcessingState.completed,
  );

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
    this.id,
    this.isVoice = false,
  });
  final String path;
  final String label;
  final int durationSeconds;

  /// Which entry of the queue it is ([AudioItem.id]); null for a track that came with
  /// no queue.
  final int? id;

  /// A voice message, which neither repeats nor shuffles.
  final bool isVoice;
}

/// One voice message or one piece of music of a timeline, as the timeline knows it
/// before its file is on the phone: what the session plays on to when a track ends.
class AudioItem {
  const AudioItem({
    required this.id,
    required this.label,
    required this.durationSeconds,
    required this.isVoice,
    required this.load,
    this.onShow,
  });

  /// Goes to the post it came with, in the timeline that holds it; does nothing once
  /// that timeline is gone.
  final VoidCallback? onShow;

  /// Telegram's id of the file.
  final int id;
  final String label;
  final int durationSeconds;
  final bool isVoice;

  /// The path of the file, which is downloaded first when it is not there yet.
  final Future<String> Function() load;
}

/// What music does when it ends, as in the official app: stop at the end of the list,
/// start the list over, or play the same piece again.
enum AudioRepeat { off, all, one }

/// Hands the audio rows under it the queue they belong to: the voice messages or the
/// music of the timeline they are in, oldest first.
class AudioQueue extends InheritedWidget {
  const AudioQueue({super.key, required this.items, required super.child});
  final List<AudioItem> Function({required bool voice}) items;

  static AudioQueue? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AudioQueue>();

  @override
  bool updateShouldNotify(AudioQueue old) => false;
}

/// The one sound of the app. Voice messages and music play through it, so a post that
/// scrolls away keeps playing (H-20) and a bar can say what is on, and only one thing is
/// ever heard at a time. The speed button goes round the official app's 1×, 1.5× and
/// 2×; voice messages and music each keep the speed they were given.
class AudioSessions {
  AudioSessions({AudioEngine Function()? engine, math.Random? random})
    : _make = engine ?? JustAudioEngine.new,
      _random = random ?? math.Random();
  final AudioEngine Function() _make;
  final math.Random _random;

  /// The tracks the one that plays stands among, oldest first; empty when it came alone.
  List<AudioItem> _queue = const [];

  /// The order shuffled music plays in, as places in [_queue]; null while it is not
  /// shuffled.
  List<int>? _shuffled;

  /// What music does at its end, and whether it plays in a shuffled order. Voice
  /// messages follow neither: they play on in the order they were posted, and stop.
  final repeat = ValueNotifier<AudioRepeat>(AudioRepeat.off);
  final shuffle = ValueNotifier<bool>(false);

  /// A video took the sound away from a track that was playing ([pauseForVideo]).
  bool _heldForVideo = false;

  /// The speed voice messages play at, and the speed of music: a podcast listened to
  /// at 2× does not make the next song run.
  double _voiceSpeed = 1;
  double _musicSpeed = 1;

  /// What the track that plays stands among, oldest first.
  List<AudioItem> get queue => _queue;

  /// The queue's entry of the track that plays; null when it came with no queue.
  AudioItem? get currentItem {
    final id = track.value?.id;
    if (id == null) return null;
    for (final item in _queue) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// Plays another entry of the queue, as a tap in the player's list asks for.
  Future<void> playItem(AudioItem item) => _playItem(item);

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
  /// [queue] is what it stands among, which plays on when it ends; without one the
  /// track plays alone.
  Future<void> play(AudioTrack next, {List<AudioItem>? queue}) async {
    _heldForVideo = false;
    if (queue != null) {
      _queue = queue;
      _shuffled = null;
    }
    if (isCurrent(next.path)) {
      await resume();
      return;
    }
    await _release();
    final engine = _make();
    _engine = engine;
    speed.value = next.isVoice ? _voiceSpeed : _musicSpeed;
    track.value = next;
    error.value = null;
    position.value = Duration.zero;
    _subs.add(engine.position.listen((p) => position.value = p));
    _subs.add(engine.playing.listen((p) => playing.value = p));
    // Played to its end: nothing is on any more, so the bar goes, as in the official app.
    // The engine itself goes on saying "playing" at the end of a file.
    _subs.add(
      engine.completed.listen((_) {
        if (identical(_engine, engine)) unawaited(_onCompleted());
      }),
    );
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

  Future<void> toggle() async {
    _heldForVideo = false;
    playing.value ? await pause() : await resume();
  }

  /// A video is about to play with its sound: a track that plays is paused, and
  /// remembered for [resumeAfterVideo].
  Future<void> pauseForVideo() async {
    if (!playing.value) return;
    _heldForVideo = true;
    await pause();
  }

  /// The video is gone: what it paused plays on, unless something else was done with
  /// the track meanwhile.
  Future<void> resumeAfterVideo() async {
    if (!_heldForVideo) return;
    _heldForVideo = false;
    if (track.value != null) await resume();
  }

  /// The file played to its end: the same piece again, the next of the queue, or
  /// nothing more.
  Future<void> _onCompleted() async {
    final current = track.value;
    if (current == null) return;
    if (!current.isVoice && repeat.value == AudioRepeat.one) {
      await seek(Duration.zero);
      await _engine?.play();
      return;
    }
    final next = _neighbour(
      1,
      wrap: !current.isVoice && repeat.value == AudioRepeat.all,
    );
    if (next == null) return stop();
    await _playItem(next);
  }

  /// The order the queue plays in: shuffled for music while [shuffle] is on, with the
  /// track that plays at its head, and as posted otherwise.
  List<int> _order(AudioTrack current) {
    final plain = [for (var i = 0; i < _queue.length; i++) i];
    if (current.isVoice || !shuffle.value) return plain;
    final kept = _shuffled;
    if (kept != null && kept.length == _queue.length) return kept;
    final at = _queue.indexWhere((i) => i.id == current.id);
    final rest = [
      for (final i in plain)
        if (i != at) i,
    ]..shuffle(_random);
    return _shuffled = [if (at >= 0) at, ...rest];
  }

  /// The entry [step] places from the one that plays; null at an end of the queue,
  /// unless it [wrap]s round.
  AudioItem? _neighbour(int step, {bool wrap = false}) {
    final current = track.value;
    if (current == null || current.id == null || _queue.isEmpty) return null;
    final order = _order(current);
    final at = order.indexWhere((i) => _queue[i].id == current.id);
    if (at < 0) return null;
    var to = at + step;
    if (to < 0 || to >= order.length) {
      if (!wrap) return null;
      to %= order.length;
    }
    return _queue[order[to]];
  }

  /// Whether there is a track after, or before, the one that plays.
  bool get hasNext => _neighbour(1, wrap: _wraps) != null;
  bool get hasPrevious => _neighbour(-1, wrap: _wraps) != null;

  bool get _wraps =>
      !(track.value?.isVoice ?? true) && repeat.value == AudioRepeat.all;

  /// The next track of the queue, as the button and the headset ask for it.
  Future<void> next() async {
    final to = _neighbour(1, wrap: _wraps);
    if (to != null) await _playItem(to);
  }

  /// The track before, or the start of this one once it has played three seconds, as
  /// players do.
  Future<void> previous() async {
    final to = _neighbour(-1, wrap: _wraps);
    if (to == null || position.value > const Duration(seconds: 3)) {
      await seek(Duration.zero);
      return;
    }
    await _playItem(to);
  }

  Future<void> _playItem(AudioItem item) async {
    final String path;
    try {
      path = await item.load();
    } on Object catch (e) {
      // What cannot be had ends the playing; the row says why when it is tapped.
      debugPrint('audio: next track not loaded: $e');
      return stop();
    }
    await play(
      AudioTrack(
        path: path,
        label: item.label,
        durationSeconds: item.durationSeconds,
        id: item.id,
        isVoice: item.isVoice,
      ),
    );
  }

  /// Off, the whole list, one piece, and off again, as the official app's button goes.
  void nextRepeat() => repeat.value =
      AudioRepeat.values[(repeat.value.index + 1) % AudioRepeat.values.length];

  void toggleShuffle() {
    shuffle.value = !shuffle.value;
    _shuffled = null;
  }

  Future<void> seek(Duration to) async {
    position.value = to;
    await _engine?.seek(to);
  }

  /// The next speed of [speeds], round and round, as the official app's button does. A
  /// speed that is none of them goes to the first.
  Future<double> nextSpeed() async {
    final i = speeds.indexOf(speed.value);
    final next = speeds[(i + 1) % speeds.length];
    await setSpeed(next);
    return next;
  }

  /// Any speed, for the kind of track that plays; the other kind keeps its own.
  Future<void> setSpeed(double to) async {
    if (track.value?.isVoice ?? false) {
      _voiceSpeed = to;
    } else {
      _musicSpeed = to;
    }
    speed.value = to;
    await _engine?.setSpeed(to);
  }

  /// Stops, and forgets what was playing: the bar goes away at once, and the engine is let
  /// go afterwards.
  Future<void> stop() async {
    _heldForVideo = false;
    track.value = null;
    playing.value = false;
    position.value = Duration.zero;
    await _release();
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
