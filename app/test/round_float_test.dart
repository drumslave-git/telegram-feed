import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/media_view.dart';
import 'package:telegram_feed/media/mini_player.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fake_video_platform.dart';
import 'media_view_test.dart' show DownloadGateway;

const _note = VideoMedia(
  file: FileRef(id: 9, remoteId: 'n', size: 100, width: 384, height: 384),
  durationSeconds: 40,
  isVideoNote: true,
);

void main() {
  // A test that failed must not leave its window to the next one.
  setUp(RoundFloat.dismiss);

  Future<void> startUp(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump();
    await tester.pump();
  }

  Widget list(DownloadGateway gw) => MaterialApp(
    home: Scaffold(
      appBar: AppBar(title: const Text('Feed')),
      body: ListView(
        children: [
          const SizedBox(height: 40),
          MediaView(media: _note, gateway: gw),
          const SizedBox(height: 3000),
        ],
      ),
    ),
  );

  Future<void> scrollBy(WidgetTester tester, double dy) async {
    await tester.drag(find.byType(ListView), Offset(0, dy));
    await tester.pump();
    // The visibility of rows is reported a moment later.
    await tester.pump(const Duration(milliseconds: 600));
    await startUp(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    RoundFloat.dismiss();
    await tester.pumpWidget(const SizedBox());
    // A message that still played when its screen went asked for its window again.
    RoundFloat.dismiss();
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
  }

  testWidgets('a round video that plays with sound goes on in a round window '
      'when its post scrolls away, and back into the post with it', (
    tester,
  ) async {
    final platform = FakeVideoPlatform.install();
    final gw = DownloadGateway('unused');
    await tester.pumpWidget(list(gw));
    await startUp(tester);

    // A tap plays it where it is, with its sound.
    await tester.tap(find.byType(VideoView));
    await startUp(tester);
    await startUp(tester);
    expect(platform.sources, hasLength(1));
    expect(platform.log, contains('volume 1 1.0'));
    expect(RoundFloat.isShowing, isFalse);

    // Out of sight, not far: the window takes it over, and it plays on.
    platform.log.clear();
    await scrollBy(tester, -300);
    expect(RoundFloat.isShowing, isTrue);
    expect(platform.log, isNot(contains('pause 1')));
    expect(platform.log, isNot(contains('dispose 1')));
    final window = tester.getRect(
      find.bySemanticsLabel('Floating video player'),
    );
    expect(window.size, const Size(RoundFloat.side, RoundFloat.side));
    // In the top right corner, under the header.
    expect(window.top, greaterThan(tester.getRect(find.byType(AppBar)).bottom));
    expect(window.right, lessThan(800));
    expect(window.right, greaterThan(700));

    // Far away, where the row itself is gone: still the same player.
    await scrollBy(tester, -2000);
    expect(find.byType(VideoView), findsNothing);
    expect(RoundFloat.isShowing, isTrue);
    await tester.pump(const Duration(seconds: 2));
    expect(platform.log, isNot(contains('dispose 1')));
    expect(platform.sources, hasLength(1));

    // A tap on the window pauses and plays.
    await tester.tap(find.bySemanticsLabel('Floating video player'));
    await tester.pump();
    expect(platform.log.last, 'pause 1');
    platform.log.clear();
    await tester.tap(find.bySemanticsLabel('Floating video player'));
    await tester.pump();
    expect(platform.log, contains('play 1'));

    // Back at the post: the window goes, the message plays on in its circle.
    platform.log.clear();
    await scrollBy(tester, 2300);
    expect(find.byType(VideoView), findsOneWidget);
    expect(RoundFloat.isShowing, isFalse);
    expect(platform.log, isNot(contains('pause 1')));
    expect(platform.sources, hasLength(1));
    await unmount(tester);
  });

  testWidgets('a round video whose row goes in one fling still gets its '
      'window', (tester) async {
    final platform = FakeVideoPlatform.install();
    final gw = DownloadGateway('unused');
    await tester.pumpWidget(list(gw));
    await startUp(tester);
    await tester.tap(find.byType(VideoView));
    await startUp(tester);
    await startUp(tester);
    platform.log.clear();

    // So far in one move that the row is let go before anyone saw it leave.
    await tester.drag(find.byType(ListView), const Offset(0, -2500));
    await tester.pump();
    await tester.pump();
    expect(find.byType(VideoView), findsNothing);
    expect(RoundFloat.isShowing, isTrue);
    expect(find.bySemanticsLabel('Floating video player'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(platform.log, isNot(contains('dispose 1')));
    expect(platform.log, isNot(contains('pause 1')));
    await unmount(tester);
  });

  testWidgets('the cross ends the message, and one that has played to its end '
      'takes its window with it', (tester) async {
    final platform = FakeVideoPlatform.install()
      ..duration = const Duration(seconds: 40);
    final gw = DownloadGateway('unused');
    await tester.pumpWidget(list(gw));
    await startUp(tester);
    await tester.tap(find.byType(VideoView));
    await startUp(tester);
    await startUp(tester);
    await scrollBy(tester, -300);
    expect(RoundFloat.isShowing, isTrue);

    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    expect(RoundFloat.isShowing, isFalse);
    expect(platform.log, contains('pause 1'));

    // Played again and scrolled away again: at its end the window is gone.
    await scrollBy(tester, 300);
    await tester.tap(find.byType(VideoView));
    await startUp(tester);
    await scrollBy(tester, -300);
    expect(RoundFloat.isShowing, isTrue);
    platform.finish(1);
    await startUp(tester);
    await startUp(tester);
    expect(RoundFloat.isShowing, isFalse);
    await unmount(tester);
  });

  testWidgets('a round video that autoplays without sound stays in its post', (
    tester,
  ) async {
    FakeVideoPlatform.install();
    final gw = DownloadGateway('unused');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              const SizedBox(height: 40),
              SizedBox(
                width: 200,
                height: 200,
                child: VideoView(video: _note, gateway: gw, autoplay: true),
              ),
              const SizedBox(height: 3000),
            ],
          ),
        ),
      ),
    );
    await startUp(tester);
    await tester.pump(const Duration(milliseconds: 600));
    await startUp(tester);
    await scrollBy(tester, -400);
    expect(RoundFloat.isShowing, isFalse);
    await unmount(tester);
  });
}
