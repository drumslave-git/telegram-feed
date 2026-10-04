import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/media/audio_session.dart';
import 'package:telegram_feed/media/now_playing.dart';

import 'audio_session_test.dart' show FakeEngine;

/// Android's player (the notification, the lock screen, the headset) is told what plays,
/// and its buttons do what the app's own do.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('tf/nowPlaying');

  late List<MethodCall> sent;
  late List<FakeEngine> engines;
  late AudioSessions sessions;
  late NowPlaying nowPlaying;
  late DateTime now;

  setUp(() {
    sent = [];
    engines = [];
    now = DateTime(2026, 10, 4, 12);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      sent.add(call);
      return null;
    });
    sessions = AudioSessions(
      engine: () {
        final e = FakeEngine();
        engines.add(e);
        return e;
      },
    );
    nowPlaying = NowPlaying(sessions, now: () => now);
  });

  tearDown(() async {
    await sessions.stop();
    nowPlaying.dispose();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  Future<void> settle() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// A button of Android's player.
  Future<void> press(String method, [Object? argument]) async {
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall(method, argument),
      ),
      (_) {},
    );
    await settle();
  }

  AudioItem song(int id) => AudioItem(
    id: id,
    label: 'Song $id – The Band',
    title: 'Song $id',
    artist: 'The Band',
    durationSeconds: 30,
    isVoice: false,
    load: () async => '/s$id',
  );

  Future<void> start(int id, List<AudioItem> queue) async {
    await sessions.play(
      AudioTrack(
        path: '/s$id',
        label: 'Song $id – The Band',
        durationSeconds: 30,
        id: id,
      ),
      queue: queue,
    );
    await settle();
  }

  Map<Object?, Object?> last() => sent.last.arguments as Map<Object?, Object?>;

  test('a track that starts is shown as playing, by its piece and who plays '
      'it, and no pause is shown between two tracks', () async {
    await start(1, [song(1), song(2), song(3)]);
    expect(sent.last.method, 'show');
    expect(last(), {
      'title': 'Song 1',
      'artist': 'The Band',
      'playing': true,
      'position': 0,
      'duration': 30000,
      'speed': 1.0,
      'skips': true,
      'channelName': 'Playback',
      'play': 'Play',
      'pause': 'Pause',
      'previous': 'Previous',
      'next': 'Next',
    });

    // It plays to its end and the next one follows.
    engines.last.finish();
    await settle();
    expect(last()['title'], 'Song 2');
    expect(
      sent.map((c) => (c.arguments as Map)['playing']),
      everyElement(true),
    );
  });

  test('a track with no queue is named by its label and has no previous and '
      'next; stopped, the player goes', () async {
    await sessions.play(
      const AudioTrack(path: '/v', label: 'Voice message', durationSeconds: 7),
    );
    await settle();
    expect(last()['title'], 'Voice message');
    expect(last()['artist'], '');
    expect(last()['skips'], isFalse);

    await sessions.stop();
    await settle();
    expect(sent.last.method, 'hide');
    // Nothing is said about a player that is not there.
    final count = sent.length;
    await sessions.stop();
    await settle();
    expect(sent, hasLength(count));
  });

  test("the player's buttons: pause, play, next, previous, the seek bar, and "
      'the swipe that stops', () async {
    await start(1, [song(1), song(2), song(3)]);

    await press('pause');
    expect(engines.last.calls.last, 'pause');
    expect(last()['playing'], isFalse);
    // A second pause is not a play.
    await press('pause');
    expect(sessions.playing.value, isFalse);

    await press('play');
    expect(sessions.playing.value, isTrue);
    expect(last()['playing'], isTrue);

    await press('next');
    expect(sessions.track.value!.id, 2);
    expect(last()['title'], 'Song 2');

    await press('previous');
    expect(sessions.track.value!.id, 1);

    await press('seek', 12000);
    expect(engines.last.calls.last, 'seek 12');
    expect(last()['position'], 12000);

    await press('stop');
    expect(sessions.track.value, isNull);
    expect(sent.last.method, 'hide');
  });

  test('Android counts the position on by itself: it is told again only when '
      'the position jumps', () async {
    await start(1, [song(1)]);
    final count = sent.length;

    // Two seconds later the track is two seconds on, as counted.
    now = now.add(const Duration(seconds: 2));
    engines.last.moveTo(const Duration(seconds: 2));
    await settle();
    expect(sent, hasLength(count));

    // Dragged in the app to 0:20.
    engines.last.moveTo(const Duration(seconds: 20));
    await settle();
    expect(sent, hasLength(count + 1));
    expect(last()['position'], 20000);

    // At 2× it is counted twice as fast.
    await sessions.setSpeed(2);
    await settle();
    expect(last()['speed'], 2.0);
    final atSpeed = sent.length;
    now = now.add(const Duration(seconds: 3));
    engines.last.moveTo(const Duration(seconds: 26));
    await settle();
    expect(sent, hasLength(atSpeed));

    // Paused, it stands still.
    await press('pause');
    final paused = sent.length;
    now = now.add(const Duration(minutes: 1));
    engines.last.moveTo(const Duration(seconds: 26));
    await settle();
    expect(sent, hasLength(paused));
  });
}
