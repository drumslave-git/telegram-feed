import 'dart:async';

import 'package:app_db/app_db.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/service/tts_service.dart';

final class FakeSpeaker implements Speaker {
  final spoken = <String>[];
  final languages = <String?>[];
  final _interruptions = StreamController<bool>.broadcast();
  Completer<void>? _current;
  String? detected;

  @override
  Future<void> init() async {}

  @override
  Stream<bool> get interruptions => _interruptions.stream;
  void interrupt(bool begin) => _interruptions.add(begin);

  @override
  Future<String?> detectLanguage(String text) async => detected;

  @override
  Future<bool> speak(
    String text, {
    String? language,
    Map<String, String>? voice,
    double? rate,
    double? pitch,
  }) async {
    spoken.add(text);
    languages.add(language);
    _current = Completer<void>();
    await _current!.future;
    return true;
  }

  /// Finishes the utterance being spoken.
  void finish() {
    _current?.complete();
    _current = null;
  }

  @override
  Future<void> stop() async {
    _current?.complete();
    _current = null;
  }
}

void main() {
  late AppDatabase db;
  late FakeSpeaker sp;
  late TtsService tts;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    sp = FakeSpeaker();
    tts = TtsService(db: db, speaker: sp, log: (_) {});
    await tts.init();
  });

  Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 10));

  test(
    'FIFO: a new item waits for the current one; duplicates by key collapse',
    () async {
      tts.enqueue(const TtsItem(text: 'first post', channelTitle: 'A', key: 1));
      tts.enqueue(const TtsItem(text: 'second post', key: 2));
      tts.enqueue(const TtsItem(text: 'second again', key: 2));
      await tick();
      expect(sp.spoken, ['New post in A. first post']);
      expect(tts.queueLength, 2);
      sp.finish();
      await tick();
      expect(sp.spoken, ['New post in A. first post', 'second post']);
      sp.finish();
      await tick();
      expect(tts.isSpeaking, isFalse);
      expect(tts.queueLength, 0);
    },
  );

  test(
    'language: detected, else default setting, else en; voice from settings',
    () async {
      await db.setSetting(TtsKeys.defaultLanguage, 'de');
      tts.enqueue(const TtsItem(text: 'hallo', key: 1));
      await tick();
      expect(sp.languages, ['de']);
      sp.finish();
      await tick();
      sp.detected = 'ru';
      tts.enqueue(const TtsItem(text: 'привет', key: 2));
      await tick();
      expect(sp.languages.last, 'ru');
      sp.finish();
    },
  );

  test(
    'interruption stops, requeues the current item and resumes after',
    () async {
      tts.enqueue(const TtsItem(text: 'one', key: 1));
      tts.enqueue(const TtsItem(text: 'two', key: 2));
      await tick();
      expect(sp.spoken, ['one']);
      sp.interrupt(true);
      await tick();
      expect(tts.isSpeaking, isFalse);
      expect(tts.queueLength, 2); // "one" is back at the head
      sp.interrupt(false);
      await tick();
      expect(sp.spoken, ['one', 'one']);
      sp.finish();
      await tick();
      expect(sp.spoken.last, 'two');
      sp.finish();
    },
  );

  test('stopAll clears everything; empty text is skipped', () async {
    tts.enqueue(const TtsItem(text: 'one', key: 1));
    tts.enqueue(const TtsItem(text: 'two', key: 2));
    await tick();
    await tts.stopAll();
    await tick();
    expect(tts.queueLength, 0);
    tts.enqueue(const TtsItem(text: '🚀🚀', key: 3));
    await tick();
    expect(sp.spoken, ['one']);
    expect(tts.isSpeaking, isFalse);
  });
}
