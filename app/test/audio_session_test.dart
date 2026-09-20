import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/players.dart';
import 'package:telegram_feed/media/audio_session.dart';

/// An engine that answers without a plugin, and records what it was asked to do.
class FakeEngine implements AudioEngine {
  final calls = <String>[];
  final _position = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  Duration? length = const Duration(seconds: 30);

  @override
  Future<void> open(String path) async => calls.add('open $path');

  @override
  Future<void> play() async {
    calls.add('play');
    _playing.add(true);
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    _playing.add(false);
  }

  @override
  Future<void> seek(Duration position) async =>
      calls.add('seek ${position.inSeconds}');

  @override
  Future<void> setSpeed(double speed) async => calls.add('speed $speed');

  @override
  Stream<Duration> get position => _position.stream;

  @override
  Stream<bool> get playing => _playing.stream;

  @override
  Duration? get duration => length;

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    await _position.close();
    await _playing.close();
  }

  void moveTo(Duration at) => _position.add(at);
}

void main() {
  late FakeEngine engine;
  late AudioSessions sessions;

  setUp(() {
    engine = FakeEngine();
    sessions = AudioSessions(engine: () => engine);
  });

  test('playing opens the file, sets the speed and starts', () async {
    await sessions.play(
      const AudioTrack(path: '/a.ogg', label: 'Voice', durationSeconds: 12),
    );
    expect(engine.calls, ['open /a.ogg', 'speed 1.0', 'play']);
    expect(sessions.track.value!.label, 'Voice');
    expect(sessions.isCurrent('/a.ogg'), isTrue);
  });

  test('pause, resume, seek and the speed button', () async {
    await sessions.play(
      const AudioTrack(path: '/a.ogg', label: 'Voice', durationSeconds: 12),
    );
    await sessions.toggle();
    expect(engine.calls.last, 'pause');
    await sessions.toggle();
    expect(engine.calls.last, 'play');

    await sessions.seek(const Duration(seconds: 5));
    expect(engine.calls.last, 'seek 5');
    expect(sessions.position.value, const Duration(seconds: 5));

    expect(await sessions.nextSpeed(), 1.5);
    expect(await sessions.nextSpeed(), 2.0);
    expect(await sessions.nextSpeed(), 1.0); // round again
  });

  test('a second file takes over from the first', () async {
    await sessions.play(
      const AudioTrack(path: '/a.ogg', label: 'A', durationSeconds: 12),
    );
    final first = engine;
    engine = FakeEngine();
    await sessions.play(
      const AudioTrack(path: '/b.mp3', label: 'B', durationSeconds: 30),
    );
    expect(first.calls, contains('dispose'));
    expect(sessions.isCurrent('/b.mp3'), isTrue);
    expect(sessions.isCurrent('/a.ogg'), isFalse);
  });

  testWidgets('the row seeks by dragging and shows the position', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AudioPlayerWidget(
            path: '/a.ogg',
            label: 'Voice message',
            durationSeconds: 30,
            sessions: sessions,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Voice message'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.text('1x'), findsOneWidget);

    engine.moveTo(const Duration(seconds: 9));
    await tester.pump();
    await tester.pump(); // the notifier rebuilds on the frame after it fires
    expect(find.textContaining('0:09 / 0:30'), findsOneWidget);

    // Dragging the bar seeks.
    await tester.drag(find.byType(Slider), const Offset(200, 0));
    await tester.pump();
    expect(engine.calls.where((c) => c.startsWith('seek')), isNotEmpty);

    await tester.tap(find.text('1x'));
    await tester.pump();
    await tester.pump();
    expect(find.text('1.5x'), findsOneWidget);

    // Take the row down before the session, so nothing listens to a closed stream.
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(sessions.stop);
  });
}
