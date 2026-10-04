import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/players.dart';
import 'package:telegram_feed/media/audio_bar.dart';
import 'package:telegram_feed/media/audio_session.dart';
import 'package:telegram_feed/media/media_viewer.dart';
import 'package:telegram_feed/media/video_stage.dart' show SpeedSlider;
import 'package:telegram_feed/service/reading_now.dart';
import 'package:telegram_feed/widgets/status_banner.dart';

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

  final _completed = StreamController<void>.broadcast();

  @override
  Stream<void> get completed => _completed.stream;

  /// The file played to its end.
  void finish() => _completed.add(null);

  @override
  Duration? get duration => length;

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    await _position.close();
    await _playing.close();
    await _completed.close();
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

  test('a file that played to its end leaves nothing on', () async {
    await sessions.play(
      const AudioTrack(path: '/a.ogg', label: 'Voice', durationSeconds: 12),
    );
    await Future<void>.delayed(Duration.zero);
    expect(sessions.playing.value, isTrue);

    engine.finish();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    // The bar is drawn while there is a track: it goes with it.
    expect(sessions.track.value, isNull);
    expect(sessions.playing.value, isFalse);
    expect(engine.calls.last, 'dispose');
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

    // Dragging the bar seeks once, when the finger lifts.
    await tester.drag(find.byType(Slider), const Offset(200, 0));
    await tester.pump();
    expect(engine.calls.where((c) => c.startsWith('seek')), hasLength(1));

    await tester.tap(find.text('1x'));
    await tester.pump();
    await tester.pump();
    expect(find.text('1.5x'), findsOneWidget);

    // Take the row down before the session, so nothing listens to a closed stream.
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(sessions.stop);
  });

  final reading = ValueNotifier<ReadingNow?>(null);
  final paused = ValueNotifier<bool>(false);
  var resumes = 0;

  /// A screen with a header under the app's banner host, which keeps the bar.
  Widget host() => MaterialApp(
    builder: (context, child) => StatusBannerHost(
      reading: reading,
      paused: paused,
      onStop: ({required clear}) {},
      onResume: () => resumes++,
      audio: sessions,
      child: child!,
    ),
    home: Scaffold(
      appBar: AppBar(title: const Text('Header')),
      body: const Center(child: Text('the screen')),
    ),
  );

  testWidgets('the bar shows what plays and keeps it playing off screen', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    // Nothing plays: no bar at all.
    expect(find.byType(AudioBar), findsNothing);

    await sessions.play(
      const AudioTrack(
        path: '/a.ogg',
        label: 'Voice message',
        durationSeconds: 30,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AudioBar), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AudioBar),
        matching: find.text('Voice message'),
      ),
      findsOneWidget,
    );
    // Under the header, as the official app has it, and over the screen's own content.
    final header = tester.getRect(find.byType(AppBar));
    final bar = tester.getRect(find.byType(AudioBar));
    expect(bar.top, greaterThanOrEqualTo(header.bottom));
    expect(
      bar.bottom,
      lessThanOrEqualTo(tester.getRect(find.text('the screen')).top),
    );
    // The row of the post is nowhere in sight, and the sound goes on.
    expect(find.byType(AudioPlayerWidget), findsNothing);
    expect(sessions.playing.value, isTrue);

    // The full-screen viewer has the screen to itself; the bar waits under it.
    MediaViewerScreen.showing.value++;
    await tester.pumpAndSettle();
    expect(find.byType(AudioBar), findsNothing);
    MediaViewerScreen.showing.value--;
    await tester.pumpAndSettle();
    expect(find.byType(AudioBar), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(AudioBar),
        matching: find.byTooltip('Pause'),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(engine.calls.last, 'pause');

    await tester.tap(
      find.descendant(
        of: find.byType(AudioBar),
        matching: find.byTooltip('Stop'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AudioBar), findsNothing);
    expect(sessions.track.value, isNull);
  });

  testWidgets('the bar shares the banner with the pause: the bar on top, the '
      'line and its button under it', (tester) async {
    paused.value = true;
    addTearDown(() => paused.value = false);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('Resume'), findsOneWidget);
    expect(find.byType(AudioBar), findsNothing);

    await sessions.play(
      const AudioTrack(path: '/a.mp3', label: 'A song', durationSeconds: 30),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AudioBar), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
    expect(
      tester.getRect(find.byType(AudioBar)).bottom,
      lessThanOrEqualTo(tester.getRect(find.text('Resume')).top),
    );
    await tester.tap(find.text('Resume'));
    expect(resumes, 1);

    // The music stops: the line about the pause stays, alone again.
    await tester.runAsync(sessions.stop);
    await tester.pumpAndSettle();
    expect(find.byType(AudioBar), findsNothing);
    expect(find.text('Resume'), findsOneWidget);
  });

  testWidgets('a tap on the bar opens the player for music: seek, previous '
      'and next, repeat, shuffle and the list', (tester) async {
    final engines = <FakeEngine>[];
    sessions = AudioSessions(
      engine: () {
        final e = FakeEngine();
        engines.add(e);
        return e;
      },
    );
    final queue = [
      for (var i = 1; i <= 3; i++)
        AudioItem(
          id: i,
          label: 'Song $i',
          durationSeconds: 30,
          isVoice: false,
          load: () async => '/s$i',
        ),
    ];
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await sessions.play(
      const AudioTrack(
        path: '/s2',
        label: 'Song 2',
        durationSeconds: 30,
        id: 2,
      ),
      queue: queue,
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(of: find.byType(AudioBar), matching: find.text('Song 2')),
    );
    await tester.pumpAndSettle();
    final sheet = find.byType(AudioPlayerSheet);
    expect(sheet, findsOneWidget);
    // The list, newest on top, with the piece that plays marked.
    for (final song in ['Song 1', 'Song 2', 'Song 3']) {
      expect(
        find.descendant(of: sheet, matching: find.text(song)),
        findsWidgets,
      );
    }
    expect(
      tester.getTopLeft(find.widgetWithText(ListTile, 'Song 3')).dy,
      lessThan(tester.getTopLeft(find.widgetWithText(ListTile, 'Song 1')).dy),
    );
    expect(find.byIcon(Icons.graphic_eq), findsOneWidget);

    Future<void> turns() async {
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 10));
      }
    }

    await tester.tap(find.byTooltip('Next'));
    await turns();
    expect(sessions.track.value!.id, 3);
    // Nothing after the newest while repeat is off: the button rests.
    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.skip_next))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byTooltip('Repeat: off'));
    await tester.pump();
    expect(sessions.repeat.value, AudioRepeat.all);
    expect(find.byTooltip('Repeat: the whole list'), findsOneWidget);
    await tester.tap(find.byTooltip('Next'));
    await turns();
    expect(sessions.track.value!.id, 1);

    await tester.tap(find.byTooltip('Previous'));
    await turns();
    expect(sessions.track.value!.id, 3);
    await tester.tap(find.byTooltip('Shuffle: off'));
    await tester.pump();
    expect(sessions.shuffle.value, isTrue);
    expect(find.byTooltip('Shuffle: on'), findsOneWidget);

    // A tap in the list plays that piece.
    await tester.tap(find.widgetWithText(ListTile, 'Song 2'));
    await turns();
    expect(sessions.track.value!.id, 2);

    // Dragging the bar seeks once, when the finger lifts.
    engines.last.calls.clear();
    await tester.drag(
      find.descendant(of: sheet, matching: find.byType(Slider)),
      const Offset(120, 0),
    );
    await tester.pump();
    expect(engines.last.calls.where((c) => c.startsWith('seek')), hasLength(1));

    // The music stops: the player closes with it.
    await tester.runAsync(sessions.stop);
    await tester.pumpAndSettle();
    expect(find.byType(AudioPlayerSheet), findsNothing);
  });

  testWidgets('a tap on the bar of a voice message goes to its post and opens '
      'no player', (tester) async {
    var shown = 0;
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await sessions.play(
      const AudioTrack(
        path: '/v1',
        label: 'Voice message',
        durationSeconds: 30,
        id: 1,
        isVoice: true,
      ),
      queue: [
        AudioItem(
          id: 1,
          label: 'Voice message',
          durationSeconds: 30,
          isVoice: true,
          load: () async => '/v1',
          onShow: () => shown++,
        ),
      ],
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AudioBar),
        matching: find.text('Voice message'),
      ),
    );
    await tester.pumpAndSettle();
    expect(shown, 1);
    expect(find.byType(AudioPlayerSheet), findsNothing);
    await tester.runAsync(sessions.stop);
    await tester.pumpAndSettle();
  });

  testWidgets('a long press on the speed offers a slider and 0.5x to 2x', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await sessions.play(
      const AudioTrack(path: '/a.mp3', label: 'A song', durationSeconds: 30),
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.text('1x'));
    await tester.pumpAndSettle();
    for (final speed in ['0.5x', '1.5x', '2x']) {
      expect(find.text(speed), findsOneWidget);
    }
    final slider = find.descendant(
      of: find.byType(SpeedSlider),
      matching: find.byType(Slider),
    );
    expect(tester.widget<Slider>(slider).min, 0.5);
    expect(tester.widget<Slider>(slider).max, 2.0);
    // The sound follows the slider while the menu is open.
    tester.widget<Slider>(slider).onChanged!(1.24);
    await tester.pump();
    expect(engine.calls.last, 'speed 1.2');

    await tester.tap(find.text('0.5x'));
    await tester.pumpAndSettle();
    expect(engine.calls.last, 'speed 0.5');
    expect(sessions.speed.value, 0.5);
    // A tap from a speed the button does not name goes to the first it names.
    await tester.tap(find.text('0.5x'));
    await tester.pumpAndSettle();
    expect(sessions.speed.value, 1.0);
    await tester.runAsync(sessions.stop);
    await tester.pumpAndSettle();
  });

  test('voice messages and music keep a speed each', () async {
    final engines = <FakeEngine>[];
    final s = AudioSessions(
      engine: () {
        final e = FakeEngine();
        engines.add(e);
        return e;
      },
    );
    await s.play(
      const AudioTrack(
        path: '/v',
        label: 'Voice',
        durationSeconds: 9,
        isVoice: true,
      ),
    );
    await s.setSpeed(2);
    await s.play(
      const AudioTrack(path: '/m', label: 'Song', durationSeconds: 9),
    );
    // The song does not run because the voice message did.
    expect(s.speed.value, 1.0);
    expect(engines.last.calls, containsAllInOrder(['open /m', 'speed 1.0']));
    await s.setSpeed(1.5);
    await s.play(
      const AudioTrack(
        path: '/v2',
        label: 'Voice',
        durationSeconds: 9,
        isVoice: true,
      ),
    );
    expect(s.speed.value, 2.0);
    expect(engines.last.calls, containsAllInOrder(['open /v2', 'speed 2.0']));
    await s.play(
      const AudioTrack(path: '/m2', label: 'Song', durationSeconds: 9),
    );
    expect(s.speed.value, 1.5);
  });
}
