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

  int releases = 0;

  @override
  Future<void> release() async => releases++;
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
    'an explicit request is spoken next, even when already queued',
    () async {
      tts.enqueue(const TtsItem(text: 'one', key: 1));
      tts.enqueue(const TtsItem(text: 'two', key: 2));
      tts.enqueue(const TtsItem(text: 'three', key: 3));
      await tick();
      tts.enqueue(const TtsItem(text: 'three', key: 3), next: true); // Listen
      tts.enqueue(
        const TtsItem(text: 'four', key: 4),
        next: true,
      ); // Listen, new
      tts.enqueue(
        const TtsItem(text: 'one', key: 1),
        next: true,
      ); // already playing
      for (var i = 0; i < 4; i++) {
        sp.finish();
        await tick();
      }
      expect(sp.spoken, ['one', 'four', 'three', 'two']);
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
      // The focus is kept, or the end of the interruption would never arrive.
      expect(sp.releases, 0);
      sp.interrupt(false);
      await tick();
      expect(sp.spoken, ['one', 'one']);
      sp.finish();
      await tick();
      expect(sp.spoken.last, 'two');
      sp.finish();
      await tick();
      expect(sp.releases, 1); // the queue has drained
    },
  );

  test(
    'Stop on the post being read silences it; the next one follows',
    () async {
      final changes = <Set<Object>>[];
      tts.readingChanges.listen(changes.add);
      tts.enqueue(const TtsItem(text: 'one', key: 1));
      tts.enqueue(const TtsItem(text: 'two', key: 2));
      expect(tts.reading, {1, 2});
      await tick();
      expect(sp.spoken, ['one']);
      await tts.stop(1);
      await tick();
      expect(sp.spoken, ['one', 'two']);
      expect(tts.reading, {2});
      sp.finish();
      await tick();
      expect(tts.reading, isEmpty);
      expect(changes, [
        {1},
        {1, 2},
        {2},
        <Object>{},
      ]);
    },
  );

  test('Stop on a waiting post takes it out of the queue', () async {
    tts.enqueue(const TtsItem(text: 'one', key: 1));
    tts.enqueue(const TtsItem(text: 'two', key: 2));
    tts.enqueue(const TtsItem(text: 'three', key: 3));
    await tick();
    await tts.stop(2);
    expect(tts.reading, {1, 3});
    sp.finish();
    await tick();
    sp.finish();
    await tick();
    expect(sp.spoken, ['one', 'three']);
    // Stop on a post that is not read changes nothing.
    await tts.stop(9);
    expect(tts.isSpeaking, isFalse);
  });

  test('an interrupted post is still waiting to be read', () async {
    tts.enqueue(const TtsItem(text: 'one', key: 1));
    await tick();
    sp.interrupt(true);
    await tick();
    expect(tts.reading, {1});
    sp.interrupt(false);
    await tick();
    sp.finish();
    await tick();
    expect(sp.spoken, ['one', 'one']);
    expect(tts.reading, isEmpty);
  });

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
