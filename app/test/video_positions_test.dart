import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/media_view.dart';
import 'package:telegram_feed/media/media_viewer.dart';
import 'package:telegram_feed/media/video_positions.dart';
import 'package:telegram_feed/media/video_sessions.dart';
import 'package:telegram_feed/media/video_stage.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fake_video_platform.dart';
import 'media_view_test.dart' show DownloadGateway;

VideoMedia _video(int seconds, {int id = 9, bool gif = false}) => VideoMedia(
  file: FileRef(
    id: id,
    remoteId: 'v$id',
    size: 5 * 1024 * 1024,
    width: 640,
    height: 360,
  ),
  durationSeconds: seconds,
  isAnimation: gif,
);

void main() {
  const file = FileRef(id: 1, remoteId: 'a', size: 10);
  const other = FileRef(id: 2, remoteId: 'b', size: 10);

  setUp(VideoPositions.wipe);

  test('a video of ten seconds or more has a place; a shorter one, and a '
      'place at the start or the end, starts over', () {
    const minute = Duration(minutes: 1);
    expect(VideoPositions.of(file, minute), isNull);

    VideoPositions.leave(file, const Duration(seconds: 15), minute);
    expect(VideoPositions.of(file, minute), const Duration(seconds: 15));
    expect(VideoPositions.of(other, minute), isNull);

    // Left at the very end, or brought back to the start: no place.
    VideoPositions.leave(file, minute, minute);
    expect(VideoPositions.of(file, minute), isNull);
    VideoPositions.leave(file, Duration.zero, minute);
    expect(VideoPositions.of(file, minute), isNull);

    // Nine seconds are too short to have one.
    const short = Duration(seconds: 9);
    VideoPositions.leave(other, const Duration(seconds: 4), short);
    expect(VideoPositions.of(other, short), isNull);
  });

  test('the place of a video of five minutes or more survives the app; a '
      'shorter one is kept only while it runs', () async {
    final dir = Directory.systemTemp.createTempSync('positions');
    addTearDown(() => dir.deleteSync(recursive: true));
    final kept = File('${dir.path}/video-positions.json');
    await VideoPositions.attach(kept);

    const long = Duration(minutes: 20);
    const brief = Duration(minutes: 2);
    VideoPositions.leave(file, const Duration(minutes: 5), long);
    VideoPositions.leave(other, const Duration(minutes: 1), brief);
    expect(VideoPositions.of(other, brief), const Duration(minutes: 1));

    // A new start of the app: only what the file holds is there.
    await VideoPositions.attach(kept);
    expect(VideoPositions.of(file, long), const Duration(minutes: 5));
    expect(VideoPositions.of(other, brief), isNull);
    expect((jsonDecode(kept.readAsStringSync()) as Map).keys, ['a']);

    // The file holds a hundred places; the one left longest ago goes first.
    for (var i = 0; i < VideoPositions.maxKept; i++) {
      VideoPositions.leave(
        FileRef(id: 100 + i, remoteId: 'n$i', size: 1),
        const Duration(minutes: 1),
        long,
      );
    }
    await VideoPositions.attach(kept);
    expect(VideoPositions.of(file, long), isNull);
    expect(
      VideoPositions.of(const FileRef(id: 100, remoteId: 'n0', size: 1), long),
      const Duration(minutes: 1),
    );

    // A file that cannot be read costs the places and nothing else.
    kept.writeAsStringSync('not json');
    await VideoPositions.attach(kept);
    expect(VideoPositions.of(file, long), isNull);

    // A logout forgets everything, the file included.
    VideoPositions.leave(file, const Duration(minutes: 5), long);
    await VideoPositions.wipe();
    expect(kept.existsSync(), isFalse);
    expect(VideoPositions.of(file, long), isNull);
  });

  group('in the viewer', () {
    Future<void> startUp(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump();
      await tester.pump();
    }

    Future<void> unmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }

    Widget opener(DownloadGateway gw, VideoMedia video) => MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () =>
              MediaViewerScreen.open(context, items: [video], gateway: gw),
          child: const Text('open'),
        ),
      ),
    );

    Future<void> open(WidgetTester tester) async {
      await tester.tap(find.text('open'));
      await startUp(tester);
      await tester.pumpAndSettle();
    }

    Future<void> close(WidgetTester tester) async {
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await startUp(tester);
      // The session without a widget is closed after its grace period.
      await tester.pump(const Duration(seconds: 1));
      await startUp(tester);
    }

    testWidgets('a video opens again where it was left', (tester) async {
      final platform = FakeVideoPlatform.install();
      await tester.runAsync(VideoPositions.wipe);
      final gw = DownloadGateway('unused');
      final video = _video(100);
      await tester.pumpWidget(opener(gw, video));

      await open(tester);
      // The first time from its start: nothing is sought.
      expect(platform.log.where((l) => l.startsWith('seek')), isEmpty);
      final session = VideoSessions.of(gw).find(9)!;
      await tester.runAsync(() => session.seekBy(const Duration(seconds: 40)));
      await close(tester);
      expect(platform.log, contains('dispose 1'));

      // A new player, at the place the last one was left at.
      await open(tester);
      expect(platform.sources, hasLength(2));
      expect(platform.log, containsAllInOrder(['seek 2 40', 'play 2']));
      await close(tester);
      await unmount(tester);
    });

    testWidgets('a video of up to half a minute starts over at its end, and '
        'so does a GIF', (tester) async {
      final platform = FakeVideoPlatform.install()
        ..duration = const Duration(seconds: 30);
      final gw = DownloadGateway('unused');
      await tester.pumpWidget(opener(gw, _video(30)));
      await open(tester);
      expect(platform.looping[1], isTrue);
      await close(tester);

      platform.duration = const Duration(seconds: 100);
      await tester.pumpWidget(opener(gw, _video(100, id: 10, gif: true)));
      await open(tester);
      expect(platform.looping[2], isTrue);
      await close(tester);
      await unmount(tester);
    });

    testWidgets('a longer video goes back to its start at its end and waits '
        'there with the controls shown', (tester) async {
      final platform = FakeVideoPlatform.install();
      final gw = DownloadGateway('unused');
      await tester.pumpWidget(opener(gw, _video(100)));
      await open(tester);
      expect(platform.looping[1], isFalse);

      // The controls go away while it plays.
      await tester.pump(const Duration(seconds: 4));
      expect(find.byType(Slider), findsNothing);

      platform.log.clear();
      platform.finish(1);
      await startUp(tester);
      await startUp(tester);
      // The player stops on its last frame; the viewer brings it back to the start.
      expect(platform.log.where((l) => l.startsWith('seek 1 ')), [
        'seek 1 100',
        'seek 1 0',
      ]);
      expect(platform.log, isNot(contains('play 1')));
      expect(find.byType(Slider), findsOneWidget);
      expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);
      // And they stay: nothing plays.
      await tester.pump(const Duration(seconds: 4));
      expect(find.byType(Slider), findsOneWidget);

      // Left at its start, it has no place to come back to.
      await close(tester);
      await open(tester);
      expect(platform.log.where((l) => l.startsWith('seek 2 ')), isEmpty);
      await close(tester);
      await unmount(tester);
    });

    testWidgets('a long video that autoplays in its row loops there and not '
        'in the viewer, and opens again where the viewer left it', (
      tester,
    ) async {
      final platform = FakeVideoPlatform.install();
      final gw = DownloadGateway('unused');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                VideoView(video: _video(100), gateway: gw, autoplay: true),
                const SizedBox(height: 900),
              ],
            ),
          ),
        ),
      );
      await startUp(tester);
      await startUp(tester);
      expect(platform.sources, hasLength(1));
      expect(platform.looping[1], isTrue);

      await tester.tap(find.byType(InlineVideo));
      await tester.pumpAndSettle();
      await startUp(tester);
      expect(find.byType(MediaViewerScreen), findsOneWidget);
      expect(platform.looping[1], isFalse);
      // Never opened before: from its start.
      expect(platform.log, contains('seek 1 0'));

      final session = VideoSessions.of(gw).find(9)!;
      await tester.runAsync(() => session.seekBy(const Duration(seconds: 25)));
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await startUp(tester);
      // Back in the row: the same player, looping again.
      expect(platform.looping[1], isTrue);
      expect(platform.log, isNot(contains('dispose 1')));

      // The row plays on; the viewer opens at the place it was left at.
      await tester.runAsync(() => session.seekBy(const Duration(seconds: 30)));
      platform.log.clear();
      await tester.tap(find.byType(InlineVideo));
      await tester.pumpAndSettle();
      await startUp(tester);
      expect(platform.log, contains('seek 1 25'));
      expect(platform.log, isNot(contains('seek 1 0')));

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await startUp(tester);
      await unmount(tester);
    });
  });
}
