import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'audio_session.dart';

/// The words of Android's player, in the app's language: the name of its notification
/// channel and what its buttons are called.
typedef NowPlayingWords = ({
  String channel,
  String play,
  String pause,
  String previous,
  String next,
});

/// Android's side of the voice message or music that plays (`NowPlaying.kt`): a media
/// notification with the player's buttons, the same player on the lock screen, and the
/// headset's buttons, as the official app has them. Android is told what plays whenever
/// that changes; it counts the position on by itself, so the position is said again only
/// when it jumps. Its buttons come back here and do what the app's own buttons do.
class NowPlaying {
  NowPlaying(this._sessions, {MethodChannel? channel, DateTime Function()? now})
    : _channel = channel ?? const MethodChannel('tf/nowPlaying'),
      _now = now ?? DateTime.now {
    for (final Listenable l in [
      _sessions.track,
      _sessions.playing,
      _sessions.speed,
      _sessions.error,
    ]) {
      l.addListener(_changed);
    }
    _sessions.position.addListener(_onPosition);
    _channel.setMethodCallHandler(_onCall);
  }

  final AudioSessions _sessions;
  final MethodChannel _channel;
  final DateTime Function() _now;

  static NowPlaying? _app;

  /// The app's own, over the one session it has.
  static void start() => _app ??= NowPlaying(AudioSessions.instance);

  static NowPlayingWords _words = (
    channel: 'Playback',
    play: 'Play',
    pause: 'Pause',
    previous: 'Previous',
    next: 'Next',
  );

  /// Set by `PipHost`, which sits under the app's strings; a player that is shown takes
  /// the new words at once.
  static set words(NowPlayingWords to) {
    if (to == _words) return;
    _words = to;
    _app?._changed();
  }

  /// How far the position may be from where Android counts it before it is said again:
  /// a seek, in the app or by a track that starts over.
  static const drift = Duration(milliseconds: 1500);

  bool _shown = false;
  bool _pending = false;

  /// What Android was told last, and when: it counts on from there.
  Duration _sentPosition = Duration.zero;
  DateTime? _sentAt;
  bool _sentPlaying = false;
  double _sentSpeed = 1;

  void _changed() {
    if (_pending) return;
    _pending = true;
    // One message for a change that moves several notifiers.
    scheduleMicrotask(() {
      _pending = false;
      unawaited(_send());
    });
  }

  void _onPosition() {
    final at = _sentAt;
    if (!_shown || at == null) return;
    final counted = _sentPlaying
        ? _sentPosition + (_now().difference(at) * _sentSpeed)
        : _sentPosition;
    if ((_sessions.position.value - counted).abs() > drift) _changed();
  }

  Future<void> _send() async {
    final track = _sessions.track.value;
    if (track == null) {
      if (!_shown) return;
      _shown = false;
      _sentAt = null;
      return _invoke('hide');
    }
    final item = _sessions.currentItem;
    // A track that is being opened counts as playing: it will in a moment, and the
    // player must not show a pause between two tracks.
    final playing = _sessions.playing.value || _sessions.starting;
    _shown = true;
    _sentPosition = _sessions.position.value;
    _sentAt = _now();
    _sentPlaying = playing;
    _sentSpeed = _sessions.speed.value;
    await _invoke('show', {
      'title': item?.title ?? track.label,
      'artist': item?.artist ?? '',
      'playing': playing,
      'position': _sentPosition.inMilliseconds,
      'duration': _sessions.length.inMilliseconds,
      'speed': _sentSpeed,
      // Previous and next for a track that stands among others, whichever it is: the
      // buttons do not come and go from track to track.
      'skips': _sessions.queue.length > 1,
      'channelName': _words.channel,
      'play': _words.play,
      'pause': _words.pause,
      'previous': _words.previous,
      'next': _words.next,
    });
  }

  Future<void> _invoke(String method, [Object? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // No activity behind the channel (tests, an engine without the app's channels).
    } on PlatformException catch (e) {
      debugPrint('now playing: $e');
    }
  }

  Future<void> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'play':
        if (!_sessions.playing.value) unawaited(_sessions.toggle());
      case 'pause':
        if (_sessions.playing.value) unawaited(_sessions.toggle());
      case 'next':
        unawaited(_sessions.next());
      case 'previous':
        unawaited(_sessions.previous());
      case 'seek':
        unawaited(
          _sessions.seek(
            Duration(milliseconds: (call.arguments as num).toInt()),
          ),
        );
      case 'stop':
        unawaited(_sessions.stop());
    }
  }

  /// Lets go of the session; tests make and drop their own.
  void dispose() {
    for (final Listenable l in [
      _sessions.track,
      _sessions.playing,
      _sessions.speed,
      _sessions.error,
    ]) {
      l.removeListener(_changed);
    }
    _sessions.position.removeListener(_onPosition);
    _channel.setMethodCallHandler(null);
  }
}
