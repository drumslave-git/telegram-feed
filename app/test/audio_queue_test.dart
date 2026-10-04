import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/media_view.dart';
import 'package:telegram_feed/media/audio_session.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'audio_session_test.dart' show FakeEngine;
import 'media_view_test.dart' show DownloadGateway;

void main() {
  /// Every track gets an engine of its own, as in the app; the newest is the one that
  /// plays.
  late List<FakeEngine> engines;
  late AudioSessions sessions;
  late List<int> loaded;

  setUp(() {
    engines = [];
    loaded = [];
    sessions = AudioSessions(
      engine: () {
        final e = FakeEngine();
        engines.add(e);
        return e;
      },
      random: math.Random(7),
    );
  });

  AudioItem item(int id, {bool voice = false}) => AudioItem(
    id: id,
    label: 'Track $id',
    durationSeconds: 30,
    isVoice: voice,
    load: () async {
      loaded.add(id);
      return '/t$id';
    },
  );

  List<AudioItem> queue(int count, {bool voice = false}) => [
    for (var i = 1; i <= count; i++) item(i, voice: voice),
  ];

  Future<void> start(int id, List<AudioItem> q) => sessions.play(
    AudioTrack(
      path: '/t$id',
      label: 'Track $id',
      durationSeconds: 30,
      id: id,
      isVoice: q.first.isVoice,
    ),
    queue: q,
  );

  /// The track that plays ends, and what follows from it settles.
  Future<void> finish() async {
    engines.last.finish();
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('a voice message plays on to the next one posted, and the last one '
      'ends it', () async {
    await start(2, queue(3, voice: true));
    expect(sessions.hasNext, isTrue);
    expect(sessions.hasPrevious, isTrue);

    await finish();
    expect(sessions.track.value!.id, 3);
    expect(sessions.track.value!.isVoice, isTrue);
    // Its file was asked for, and a new engine opened it.
    expect(loaded, [3]);
    expect(engines.last.calls, containsAllInOrder(['open /t3', 'play']));
    expect(sessions.hasNext, isFalse);

    await finish();
    expect(sessions.track.value, isNull);
  });

  test('voice messages neither repeat nor shuffle', () async {
    sessions.repeat.value = AudioRepeat.all;
    sessions.shuffle.value = true;
    await start(1, queue(3, voice: true));
    await finish();
    expect(sessions.track.value!.id, 2);
    await finish();
    expect(sessions.track.value!.id, 3);
    await finish();
    expect(sessions.track.value, isNull);
  });

  test('a track that came with no queue plays alone', () async {
    await sessions.play(
      const AudioTrack(path: '/a.ogg', label: 'Voice', durationSeconds: 12),
    );
    expect(sessions.hasNext, isFalse);
    await finish();
    expect(sessions.track.value, isNull);
  });

  test('music stops at the end of the list, starts it over with repeat, and '
      'plays one piece again with repeat one', () async {
    await start(2, queue(2));
    await finish();
    expect(sessions.track.value, isNull);

    // The button goes off, the whole list, one piece, off.
    expect(sessions.repeat.value, AudioRepeat.off);
    sessions.nextRepeat();
    expect(sessions.repeat.value, AudioRepeat.all);
    await start(2, queue(2));
    await finish();
    expect(sessions.track.value!.id, 1);

    sessions.nextRepeat();
    expect(sessions.repeat.value, AudioRepeat.one);
    final engine = engines.last;
    engine.calls.clear();
    await finish();
    expect(sessions.track.value!.id, 1);
    // The same engine, from its start: nothing was loaded again.
    expect(engines.last, same(engine));
    expect(engine.calls, ['seek 0', 'play']);
    sessions.nextRepeat();
    expect(sessions.repeat.value, AudioRepeat.off);
  });

  test(
    'shuffled music plays every piece once, the one that plays first',
    () async {
      sessions.toggleShuffle();
      await start(3, queue(6));
      final played = [3];
      while (sessions.hasNext) {
        await finish();
        played.add(sessions.track.value!.id!);
      }
      expect(played.first, 3);
      expect(played.toSet(), {1, 2, 3, 4, 5, 6});
      expect(played, hasLength(6));
      // Not in the order they were posted.
      expect(played, isNot([3, 4, 5, 6, 1, 2]));
      expect(played.sublist(1), isNot([1, 2, 4, 5, 6]));
      await finish();
      expect(sessions.track.value, isNull);
    },
  );

  test('next and previous walk the queue; previous goes to the start of a '
      'piece that has played for a while', () async {
    await start(2, queue(3));
    await sessions.next();
    expect(sessions.track.value!.id, 3);
    // Nothing after the last, without repeat.
    await sessions.next();
    expect(sessions.track.value!.id, 3);

    await sessions.previous();
    expect(sessions.track.value!.id, 2);
    engines.last.moveTo(const Duration(seconds: 10));
    await Future<void>.delayed(Duration.zero);
    engines.last.calls.clear();
    await sessions.previous();
    expect(sessions.track.value!.id, 2);
    expect(engines.last.calls, ['seek 0']);
    await sessions.previous();
    expect(sessions.track.value!.id, 1);
    // At the first: its own start.
    await sessions.previous();
    expect(sessions.track.value!.id, 1);
  });

  test('a file that cannot be had ends the playing', () async {
    await start(1, [
      item(1),
      AudioItem(
        id: 2,
        label: 'Gone',
        durationSeconds: 1,
        isVoice: false,
        load: () async => throw const TelegramException(404, 'FILE_NOT_FOUND'),
      ),
    ]);
    await finish();
    expect(sessions.track.value, isNull);
  });

  test('a video pauses what plays and gives it back when it is gone; what was '
      'paused by hand stays paused', () async {
    await start(1, queue(2));
    await Future<void>.delayed(Duration.zero);
    expect(sessions.playing.value, isTrue);

    await sessions.pauseForVideo();
    await Future<void>.delayed(Duration.zero);
    expect(engines.last.calls.last, 'pause');
    await sessions.resumeAfterVideo();
    expect(engines.last.calls.last, 'play');
    // Once: a second video end resumes nothing.
    engines.last.calls.clear();
    await sessions.resumeAfterVideo();
    expect(engines.last.calls, isEmpty);

    // Paused by the reader before the video: the video leaves it alone.
    await sessions.pause();
    await Future<void>.delayed(Duration.zero);
    await sessions.pauseForVideo();
    engines.last.calls.clear();
    await sessions.resumeAfterVideo();
    expect(engines.last.calls, isEmpty);

    // Paused by the video, then stopped by the reader: nothing comes back.
    await sessions.toggle();
    await Future<void>.delayed(Duration.zero);
    await sessions.pauseForVideo();
    await sessions.stop();
    await sessions.resumeAfterVideo();
    expect(sessions.track.value, isNull);
  });

  testWidgets('the row of the track the session played on to shows it '
      'playing, and a paused track does not start when its row is drawn', (
    tester,
  ) async {
    final gw = DownloadGateway('unused');
    FileRef file(int id) =>
        FileRef(id: id, remoteId: 'r$id', size: 10, localPath: '/t$id');
    final q = queue(2, voice: true);
    Widget rows() => MaterialApp(
      home: Scaffold(
        body: AudioQueue(
          items: ({required voice}) => q,
          child: Column(
            children: [
              for (final id in [1, 2])
                AudioView(
                  key: ValueKey(id),
                  file: file(id),
                  durationSeconds: 30,
                  label: 'Voice $id',
                  gateway: gw,
                  isVoice: true,
                  sessions: sessions,
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpWidget(rows());
    expect(find.byTooltip('Play'), findsNWidgets(2));
    expect(find.byType(Slider), findsNothing);

    // The first is tapped: it plays, with the queue of its timeline.
    await tester.tap(find.byTooltip('Play').first);
    await tester.pump();
    await tester.pump();
    expect(sessions.track.value!.id, 1);
    expect(sessions.hasNext, isTrue);
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);

    // It ends: the second row is the one with the player now.
    engines.last.finish();
    // The old engine is let go and the new one opened over several turns of the
    // event loop, the real one among them: a cancelled subscription answers there.
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(sessions.track.value!.id, 2);
    expect(find.byTooltip('Pause'), findsOneWidget);
    final playing = tester.getTopLeft(find.byTooltip('Pause'));
    expect(playing.dy, greaterThan(tester.getTopLeft(find.text('Voice 1')).dy));

    // Paused, and its row drawn anew (scrolled away and back): it stays paused.
    await sessions.pause();
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    engines.last.calls.clear();
    await tester.pumpWidget(rows());
    await tester.pump();
    expect(engines.last.calls, isEmpty);
    expect(find.byType(Slider), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(sessions.stop);
  });
}
