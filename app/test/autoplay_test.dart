import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/media_view.dart';
import 'package:telegram_feed/media/media_viewer.dart';
import 'package:telegram_feed/media/video_sessions.dart';
import 'package:telegram_feed/media/video_stage.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fake_video_platform.dart';
import 'media_view_test.dart' show DownloadGateway;

VideoMedia _video({int seconds = 20, int megabytes = 5, bool gif = false}) =>
    VideoMedia(
      file: FileRef(
        id: 9,
        remoteId: 'v',
        size: megabytes * 1024 * 1024,
        width: 640,
        height: 360,
      ),
      durationSeconds: seconds,
      isAnimation: gif,
    );

void main() {
  Future<void> startUp(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
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

  Widget list(DownloadGateway gw, {required bool autoplay}) {
    final v = _video();
    return MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            const SizedBox(
              height: 900,
            ), // pushes the video below the 600 px window
            VideoView(video: v, gateway: gw, autoplay: autoplay),
            const SizedBox(height: 900),
          ],
        ),
      ),
    );
  }

  testWidgets(
    'starts muted when scrolled into view, pauses when scrolled out',
    (tester) async {
      final platform = FakeVideoPlatform.install();
      final gw = DownloadGateway('unused');
      await tester.pumpWidget(list(gw, autoplay: true));
      await startUp(tester);
      expect(platform.sources, isEmpty);

      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await startUp(tester);
      expect(platform.sources, hasLength(1));
      expect(platform.log, containsAllInOrder(['volume 1 0.0', 'play 1']));
      expect(find.byIcon(Icons.volume_off), findsOneWidget);

      // A tap opens the viewer with sound on the same player, and the video the row was
      // playing somewhere in the middle starts over.
      final session = VideoSessions.of(gw).find(9)!;
      await tester.runAsync(() => session.seekBy(const Duration(seconds: 30)));
      platform.log.clear();
      await tester.tap(find.byType(InlineVideo));
      await tester.pumpAndSettle();
      expect(find.byType(MediaViewerScreen), findsOneWidget);
      expect(platform.log, contains('volume 1 1.0'));
      expect(platform.log, contains('seek 1 0'));
      expect(platform.sources, hasLength(1));

      // Leaving it: muted autoplay in the row again, nothing is cancelled.
      platform.log.clear();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await startUp(tester);
      expect(platform.log, containsAllInOrder(['volume 1 0.0', 'play 1']));
      expect(platform.log, isNot(contains('dispose 1')));
      expect(gw.cancelled, isEmpty);
      expect(find.byIcon(Icons.volume_off), findsOneWidget);

      platform.log.clear();
      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await startUp(tester);
      expect(platform.log, contains('pause 1'));
      await unmount(tester);
    },
  );

  testWidgets('videos outside the policy wait for a tap', (tester) async {
    final platform = FakeVideoPlatform.install();
    final gw = DownloadGateway('unused');
    await tester.pumpWidget(list(gw, autoplay: false));
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await startUp(tester);
    expect(platform.sources, isEmpty);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    await unmount(tester);
  });
}
