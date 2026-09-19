import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/media_view.dart';
import 'package:telegram_feed/media/media_viewer.dart';
import 'package:telegram_feed/media/mini_player.dart';
import 'package:telegram_feed/media/system_pip.dart';
import 'package:telegram_feed/media/video_stage.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fake_video_platform.dart';
import 'media_view_test.dart' show DownloadGateway;

const _video = VideoMedia(
  file: FileRef(id: 4, remoteId: 'd', size: 100, width: 640, height: 360),
  durationSeconds: 754,
);

void main() {
  late DownloadGateway gw;
  setUp(() => gw = DownloadGateway('unused'));

  Widget app() => MaterialApp(
    builder: (context, child) => PipHost(child: child!),
    home: Scaffold(
      body: SizedBox(
        width: 400,
        child: MediaView(media: _video, gateway: gw),
      ),
    ),
  );

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    MiniPlayer.dismiss();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
  }

  testWidgets('mini player: the video goes on over the timeline, and back', (
    tester,
  ) async {
    final platform = FakeVideoPlatform.install();
    await tester.pumpWidget(app());
    await tester.tap(find.byIcon(Icons.play_arrow));
    await settle(tester);

    await tester.tap(find.byTooltip('Picture-in-picture'));
    await settle(tester);
    expect(find.byType(MediaViewerScreen), findsNothing);
    expect(MiniPlayer.isShowing, isTrue);
    expect(find.byTooltip('Back to full screen'), findsOneWidget);
    // The same player, still running; the row under it is a poster again.
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(platform.log, isNot(contains('dispose 1')));
    expect(platform.log.last, isNot('pause 1'));
    expect(gw.cancelled, isEmpty);

    // A tap on the little window pauses and plays.
    await tester.tap(find.byType(VideoPicture));
    await tester.pump();
    expect(platform.log.last, 'pause 1');
    platform.log.clear();
    await tester.tap(find.byType(VideoPicture));
    await tester.pump();
    expect(platform.log, contains('play 1'));

    await tester.tap(find.byTooltip('Back to full screen'));
    await settle(tester);
    expect(find.byType(MediaViewerScreen), findsOneWidget);
    expect(MiniPlayer.isShowing, isFalse);
    expect(platform.sources, hasLength(1));
    expect(platform.log, isNot(contains('dispose 1')));

    // Closing the little window ends the video as leaving the viewer would.
    await tester.tap(find.byTooltip('Picture-in-picture'));
    await settle(tester);
    await tester.tap(find.byTooltip('Close'));
    await settle(tester);
    expect(MiniPlayer.isShowing, isFalse);
    expect(platform.log, containsAllInOrder(['pause 1', 'dispose 1']));
    expect(gw.cancelled, [4]);
    await unmount(tester);
  });

  testWidgets(
    'system window: armed while a video plays, shows only the video',
    (tester) async {
      final platform = FakeVideoPlatform.install();
      const channel = MethodChannel('tf/pip');
      final armed = <Map<Object?, Object?>>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'arm') armed.add(call.arguments as Map);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      Future<void> system(bool inWindow) => messenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(MethodCall('pipChanged', inWindow)),
        (_) {},
      );

      await tester.pumpWidget(app());
      await tester.tap(find.byIcon(Icons.play_arrow));
      await settle(tester);
      expect(armed.last, {'enabled': true, 'width': 640, 'height': 360});

      // The user leaves the app; Android shrinks the activity.
      await system(true);
      await tester.pump();
      expect(find.byType(VideoPicture), findsOneWidget);
      expect(
        find.byType(MediaViewerScreen),
        findsNothing,
      ); // kept, but offstage
      expect(
        find.byType(MediaViewerScreen, skipOffstage: false),
        findsOneWidget,
      );

      // The window is closed instead of opened again: no sound from the background.
      await system(false);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(platform.log.last, 'pause 1');
      expect(armed.last['enabled'], isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.byType(MediaViewerScreen), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await settle(tester);
      expect(armed.last['enabled'], isFalse);
      await unmount(tester);
    },
  );
}
