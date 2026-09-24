import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:app_db/app_db.dart';
import 'package:audio_session/audio_session.dart';
import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

/// Settings keys for read-aloud (P2-7 edits them).
abstract final class TtsKeys {
  static const rate =
      'tts.rate'; // double, flutter_tts scale (0.5 = normal on Android)
  static const pitch = 'tts.pitch'; // double, 1.0 normal
  static const maxChars = 'tts.maxChars'; // int
  static const defaultLanguage = 'tts.defaultLanguage'; // BCP-47, e.g. en-US
  static String voiceFor(String language) =>
      'tts.voice.$language'; // JSON {name, locale}
}

/// One utterance in the queue.
final class TtsItem {
  const TtsItem({required this.text, this.channelTitle, this.key});
  final String text;
  final String? channelTitle;

  /// Identifies the post so duplicate requests collapse.
  final Object? key;
}

/// Platform side of speech: language detection, voice choice, speaking, focus events.
/// Abstract so the queue can be tested without the plugins.
abstract interface class Speaker {
  Future<void> init();

  /// BCP-47 language code or null when unknown.
  Future<String?> detectLanguage(String text);

  /// Speaks and completes when done (or when stopped). Returns false if the engine refused.
  Future<bool> speak(
    String text, {
    String? language,
    Map<String, String>? voice,
    double? rate,
    double? pitch,
  });

  Future<void> stop();

  /// Gives the audio focus back: the queue has drained.
  Future<void> release();

  /// True while a phone call or another interruption holds the audio focus.
  Stream<bool> get interruptions;
}

/// FIFO read-aloud queue (ARCHITECTURE.md section 7). A new item never interrupts the one
/// playing; interruptions (calls) pause the queue and the interrupted item is spoken again.
final class TtsService {
  TtsService({
    required this.db,
    required this.speaker,
    void Function(String)? log,
  }) : _log = log ?? ((s) => debugPrint('tts: $s'));

  final AppDatabase db;
  final Speaker speaker;
  final void Function(String) _log;
  final _queue = Queue<TtsItem>();
  final _keys = <Object>{};
  // Synchronous, so a notification shown right after [enqueue] already knows.
  final _readingChanges = StreamController<Set<Object>>.broadcast(sync: true);
  StreamSubscription<bool>? _interruptSub;
  bool _speaking = false;
  bool _interrupted = false;
  bool _stopped = false;
  TtsItem? _current;

  int get queueLength => _queue.length + (_speaking ? 1 : 0);
  bool get isSpeaking => _speaking;

  /// Keys of the posts being read or waiting to be read.
  Set<Object> get reading => Set.unmodifiable(_keys);

  /// [reading] after each change: a post's notification offers Stop while its key is in
  /// it and Listen otherwise.
  Stream<Set<Object>> get readingChanges => _readingChanges.stream;

  void _readingChanged() => _readingChanges.add(reading);

  Future<void> init() async {
    await speaker.init();
    _interruptSub = speaker.interruptions.listen((begin) {
      _interrupted = begin;
      if (begin) {
        _log('interrupted');
        final c = _current;
        if (c != null) _queue.addFirst(c); // say it again afterwards
        unawaited(speaker.stop());
      } else {
        _log('interruption over');
        unawaited(_drain());
      }
    });
  }

  /// Adds to the queue (deduplicated by [TtsItem.key]) and starts speaking if idle.
  ///
  /// [next] is for explicit requests (the notification's Listen action): the item is spoken
  /// right after the current one, also when it was already waiting further back.
  void enqueue(TtsItem item, {bool next = false}) {
    final key = item.key;
    final isNew = key == null || _keys.add(key);
    if (!isNew && !next) return;
    if (!isNew) {
      if (_current?.key == key) return; // being spoken right now
      _queue.removeWhere((q) => q.key == key);
    }
    if (next) {
      _queue.addFirst(item);
    } else {
      _queue.add(item);
    }
    if (isNew && key != null) _readingChanged();
    _stopped = false;
    unawaited(_drain());
  }

  /// Stops one post (its notification's Stop): the one being read goes quiet and the next
  /// one follows; one still waiting leaves the queue.
  Future<void> stop(Object key) async {
    if (!_keys.remove(key)) return;
    _queue.removeWhere((q) => q.key == key);
    _readingChanged();
    if (_current?.key == key) await speaker.stop();
  }

  /// Stops the current utterance and clears the queue.
  Future<void> stopAll() async {
    _stopped = true;
    _queue.clear();
    final had = _keys.isNotEmpty;
    _keys.clear();
    if (had) _readingChanged();
    await speaker.stop();
  }

  Future<void> _drain() async {
    if (_speaking || _interrupted) return;
    _speaking = true;
    try {
      while (_queue.isNotEmpty && !_interrupted && !_stopped) {
        final item = _queue.removeFirst();
        _current = item;
        await _speakOne(item);
        _current = null;
        // An item put back by an interruption is still waiting.
        if (item.key != null &&
            !_queue.any((q) => q.key == item.key) &&
            _keys.remove(item.key)) {
          _readingChanged();
        }
      }
    } finally {
      _speaking = false;
      _current = null;
      // Through an interruption the focus is kept: its return ends the interruption.
      if (!_interrupted) unawaited(speaker.release());
    }
  }

  /// False once [stop] or [stopAll] took the item back.
  bool _wanted(TtsItem item) =>
      !_stopped && (item.key == null || _keys.contains(item.key));

  Future<void> _speakOne(TtsItem item) async {
    final maxChars =
        int.tryParse(await db.setting(TtsKeys.maxChars) ?? '') ?? 600;
    final text = prepareForSpeech(
      item.text,
      channelTitle: item.channelTitle,
      maxChars: maxChars,
    );
    if (text.isEmpty) return;
    final detected = await speaker.detectLanguage(item.text);
    final language =
        detected ?? await db.setting(TtsKeys.defaultLanguage) ?? 'en';
    final voiceJson = await db.setting(TtsKeys.voiceFor(language));
    Map<String, String>? voice;
    if (voiceJson != null) {
      try {
        voice = (jsonDecode(voiceJson) as Map).cast<String, String>();
      } on FormatException {
        voice = null;
      }
    }
    final rate = double.tryParse(await db.setting(TtsKeys.rate) ?? '');
    final pitch = double.tryParse(await db.setting(TtsKeys.pitch) ?? '');
    // A Stop pressed while the settings and the language were looked up.
    if (!_wanted(item)) return;
    _log(
      'speak [$language${voice == null ? '' : ', ${voice['name']}'}] ${text.length} chars',
    );
    final ok = await speaker.speak(
      text,
      language: language,
      voice: voice,
      rate: rate,
      pitch: pitch,
    );
    if (!ok && _wanted(item) && !_interrupted) _log('speech not heard');
  }

  Future<void> dispose() async {
    await _interruptSub?.cancel();
    await stopAll();
    await _readingChanges.close();
  }
}

/// Real speaker: flutter_tts + ML Kit language identification + just_audio + audio_session.
///
/// The engine writes the speech into a file and this app plays it: Android mutes audio
/// played in the background by an app without a while-in-use foreground service, and the
/// engine plays in its own process, which has none (ARCHITECTURE 7).
final class FlutterTtsSpeaker implements Speaker {
  FlutterTtsSpeaker({void Function(String)? log})
    : _log = log ?? ((s) => debugPrint('tts: $s'));

  final void Function(String) _log;
  final _tts = FlutterTts();
  final _langId = LanguageIdentifier(confidenceThreshold: 0.5);
  final _interruptions = StreamController<bool>.broadcast();
  // The focus and interruptions are handled here, not by the player.
  final _player = AudioPlayer(
    handleInterruptions: false,
    handleAudioSessionActivation: false,
  );
  String? _language;
  Map<String, String>? _voice;
  double? _rate;
  double? _pitch;
  int _files = 0;

  /// Ends the utterance in progress with false: on [stop], on a permanent loss of the
  /// audio focus, and when the engine reports an error, after which flutter_tts never
  /// answers the call it failed.
  Completer<bool>? _end;

  /// Asks for the audio focus again while a call holds it.
  Timer? _retry;

  void _finish() {
    final end = _end;
    if (end != null && !end.isCompleted) end.complete(false);
  }

  @override
  Stream<bool> get interruptions => _interruptions.stream;

  @override
  Future<void> init() async {
    await _tts.awaitSynthCompletion(true);
    await _tts.awaitSpeakCompletion(true);
    _tts.setErrorHandler((m) {
      _log('engine error: $m');
      _finish();
    });
    final session = await AudioSession.instance;
    await session.configure(
      const AudioSessionConfiguration(
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType:
            AndroidAudioFocusGainType.gainTransientMayDuck,
        androidWillPauseWhenDucked: false,
      ),
    );
    // A phone call or another app's short sound pauses the queue; a notification sound
    // only ducks the speech, which Android does by itself. Another app taking the focus
    // for good (music started) ends the post being read.
    session.interruptionEventStream.listen((e) {
      switch (e.type) {
        case AudioInterruptionType.pause:
          _interruptions.add(e.begin);
        case AudioInterruptionType.unknown:
          if (e.begin) {
            _log('audio focus lost');
            _finish();
          }
        case AudioInterruptionType.duck:
          break;
      }
    });
    session.becomingNoisyEventStream.listen((_) => _finish());
  }

  @override
  Future<String?> detectLanguage(String text) async {
    try {
      final code = await _langId.identifyLanguage(text);
      return code == 'und' ? null : code;
    } catch (e) {
      _log('language id failed: $e');
      return null;
    }
  }

  @override
  Future<bool> speak(
    String text, {
    String? language,
    Map<String, String>? voice,
    double? rate,
    double? pitch,
  }) async {
    if (language != null && language != _language) {
      final available = await _tts.isLanguageAvailable(language);
      if (available == true) {
        await _tts.setLanguage(language);
        _language = language;
      }
    }
    if (voice != null && voice != _voice) {
      await _tts.setVoice(voice);
      _voice = voice;
    }
    if (rate != null && rate != _rate) {
      await _tts.setSpeechRate(rate);
      _rate = rate;
    }
    if (pitch != null && pitch != _pitch) {
      await _tts.setPitch(pitch);
      _pitch = pitch;
    }
    final end = _end = Completer<bool>();
    try {
      final session = await AudioSession.instance;
      if (await session.setActive(true)) {
        return await _synthesizeAndPlay(text, end.future);
      }
      // audio_session would answer the next request from the refused one without asking.
      await session.setActive(false);
      final mode = await AndroidAudioManager().getMode();
      if (mode != AndroidAudioHardwareMode.normal) {
        _log('audio focus refused during a call');
        _waitForTheCall();
        return false;
      }
      // Android withholds the focus from a foreground service that it started in the
      // background (after a reboot or an update, until the app is opened). The engine
      // speaks by itself then, which Android lets be heard right after a tap such as
      // Listen.
      _log('audio focus withheld in the background; the engine speaks');
      return await Future.any([
        _tts.speak(text, focus: true).then((r) => r == 1),
        end.future,
      ]);
    } on Object catch (e) {
      _log('speech not played: $e');
      return false;
    } finally {
      _end = null;
    }
  }

  /// The queue waits while a call holds the focus, and asks again every few seconds.
  void _waitForTheCall() {
    _interruptions.add(true);
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 5), () {
      _interruptions.add(false);
    });
  }

  /// The engine writes the speech into a file, which is played here under the focus
  /// already taken; that focus is kept until [release], because through an interruption
  /// regaining it is what ends the interruption.
  Future<bool> _synthesizeAndPlay(String text, Future<bool> ended) async {
    final file = File(
      '${(await getTemporaryDirectory()).path}/read-aloud-${_files++}.wav',
    );
    try {
      final made = await Future.any([
        _tts.synthesizeToFile(text, file.path, true).then((r) => r == 1),
        ended,
      ]);
      if (!made || !file.existsSync()) return false;
      return await _play(file.path, ended);
    } finally {
      try {
        if (file.existsSync()) file.deleteSync();
      } on FileSystemException {
        // Gone already, or still held; the temporary directory is the system's to clear.
      }
    }
  }

  Future<bool> _play(String path, Future<bool> ended) async {
    final played = Completer<bool>();
    final sub = _player.processingStateStream.listen(
      (s) {
        if (s == ProcessingState.completed && !played.isCompleted) {
          played.complete(true);
        }
      },
      onError: (Object e) {
        _log('playback failed: $e');
        if (!played.isCompleted) played.complete(false);
      },
    );
    try {
      await _player.setFilePath(path);
      // Done when the player reaches the end; its own future also completes on a stop.
      unawaited(_player.play());
      return await Future.any([played.future, ended]);
    } finally {
      await sub.cancel();
      await _player.stop();
    }
  }

  @override
  Future<void> stop() async {
    _finish();
    await _tts.stop();
  }

  @override
  Future<void> release() async {
    _retry?.cancel();
    await (await AudioSession.instance).setActive(false);
  }

  /// Voices the engine offers, as `{name, locale}` maps (for the settings screen).
  Future<List<Map<String, String>>> voices() async {
    final raw = await _tts.getVoices;
    if (raw is! List) return const [];
    return [
      for (final v in raw)
        if (v is Map) {for (final e in v.entries) '${e.key}': '${e.value}'},
    ];
  }
}
