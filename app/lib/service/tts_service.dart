import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:app_db/app_db.dart';
import 'package:audio_session/audio_session.dart';
import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';

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
  StreamSubscription<bool>? _interruptSub;
  bool _speaking = false;
  bool _interrupted = false;
  bool _stopped = false;
  TtsItem? _current;

  int get queueLength => _queue.length + (_speaking ? 1 : 0);
  bool get isSpeaking => _speaking;

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
  void enqueue(TtsItem item) {
    if (item.key != null && !_keys.add(item.key!)) return;
    _queue.add(item);
    _stopped = false;
    unawaited(_drain());
  }

  /// Stops the current utterance and clears the queue (user pressed stop).
  Future<void> stopAll() async {
    _stopped = true;
    _queue.clear();
    _keys.clear();
    await speaker.stop();
  }

  Future<void> _drain() async {
    if (_speaking || _interrupted || _stopped) return;
    _speaking = true;
    try {
      while (_queue.isNotEmpty && !_interrupted && !_stopped) {
        final item = _queue.removeFirst();
        _current = item;
        await _speakOne(item);
        _current = null;
        if (item.key != null) _keys.remove(item.key);
      }
    } finally {
      _speaking = false;
      _current = null;
    }
  }

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
    if (!ok) _log('engine refused to speak');
  }

  Future<void> dispose() async {
    await _interruptSub?.cancel();
    await stopAll();
  }
}

/// Real speaker: flutter_tts + ML Kit language identification + audio_session interruptions.
final class FlutterTtsSpeaker implements Speaker {
  /// [detectLanguage] replaces ML Kit where it does not exist (web: script heuristic).
  FlutterTtsSpeaker({
    void Function(String)? log,
    Future<String?> Function(String text)? detectLanguage,
  }) : _log = log ?? ((s) => debugPrint('tts: $s')),
       _detect = detectLanguage;

  final void Function(String) _log;
  final Future<String?> Function(String text)? _detect;
  final _tts = FlutterTts();
  late final _langId = LanguageIdentifier(confidenceThreshold: 0.5);
  final _interruptions = StreamController<bool>.broadcast();
  String? _language;
  Map<String, String>? _voice;
  double? _rate;
  double? _pitch;

  @override
  Stream<bool> get interruptions => _interruptions.stream;

  @override
  Future<void> init() async {
    await _tts.awaitSpeakCompletion(true);
    _tts.setErrorHandler((m) => _log('engine error: $m'));
    final session = await AudioSession.instance;
    await session.configure(
      const AudioSessionConfiguration(
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.assistant,
        ),
        androidAudioFocusGainType:
            AndroidAudioFocusGainType.gainTransientMayDuck,
        androidWillPauseWhenDucked: false,
      ),
    );
    // Phone calls and other apps taking the focus arrive as interruptions.
    session.interruptionEventStream.listen((e) => _interruptions.add(e.begin));
    session.becomingNoisyEventStream.listen((_) => _tts.stop());
  }

  @override
  Future<String?> detectLanguage(String text) async {
    final custom = _detect;
    if (custom != null) return custom(text);
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
    final r = await _tts.speak(text, focus: true);
    return r == 1;
  }

  @override
  Future<void> stop() => _tts.stop();

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
