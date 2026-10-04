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
  setUp(() {
    gw = DownloadGateway('unused');
    MiniPlayer.forgetPlace();
  });

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

    // Its buttons are there for a moment, then the picture is alone.
    expect(find.byTooltip('Pause'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(find.byTooltip('Pause'), findsNothing);
    expect(find.byTooltip('Back to full screen'), findsNothing);
    expect(find.byTooltip('Close'), findsNothing);

    // A tap on the little window brings them back; it does not pause.
    platform.log.clear();
    await tester.tap(find.byType(VideoPicture));
    await tester.pump(const Duration(milliseconds: 350));
    expect(platform.log, isNot(contains('pause 1')));
    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    expect(platform.log.last, 'pause 1');
    // A paused video keeps its buttons.
    await tester.pump(const Duration(seconds: 4));
    platform.log.clear();
    // The row under the window has a play button of its own; the window's is on top.
    await tester.tap(find.byTooltip('Play').last);
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

  /// The viewer's video in the little window, its buttons gone.
  Future<FakeVideoPlatform> floating(WidgetTester tester) async {
    final platform = FakeVideoPlatform.install();
    await tester.pumpWidget(app());
    await tester.tap(find.byIcon(Icons.play_arrow));
    await settle(tester);
    await tester.tap(find.byTooltip('Picture-in-picture'));
    await settle(tester);
    await tester.pump(const Duration(seconds: 4));
    platform.log.clear();
    return platform;
  }

  Rect window(WidgetTester tester) => tester.getRect(find.byType(VideoPicture));

  testWidgets('mini player: a double tap seeks ten seconds, back on the left '
      'half and forwards on the right', (tester) async {
    final platform = await floating(tester);
    final box = window(tester);

    Future<void> doubleTap(Offset at) async {
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 350));
    }

    await doubleTap(box.centerRight - const Offset(20, 0));
    expect(platform.log.last, 'seek 1 10');
    platform.positions[1] = const Duration(seconds: 30);
    await tester.pump(const Duration(milliseconds: 600));
    await doubleTap(box.centerLeft + const Offset(20, 0));
    expect(platform.log.last, 'seek 1 20');
    // Neither showed the buttons nor paused.
    expect(platform.log, isNot(contains('pause 1')));
    expect(find.byTooltip('Close'), findsNothing);
    await unmount(tester);
  });

  testWidgets('mini player: a pinch resizes it, and the next one opens where '
      'this one was left, as large', (tester) async {
    await floating(tester);
    final before = window(tester);
    // It starts at the right side.
    expect(before.right, greaterThan(700));

    // Two fingers spread to twice their distance.
    final one = await tester.startGesture(before.center - const Offset(20, 0));
    final two = await tester.startGesture(before.center + const Offset(20, 0));
    await tester.pump();
    await one.moveBy(const Offset(-20, 0));
    await two.moveBy(const Offset(20, 0));
    await tester.pump();
    await one.moveBy(const Offset(-20, 0));
    await two.moveBy(const Offset(20, 0));
    await tester.pump();
    await one.up();
    await two.up();
    await tester.pump();
    final grown = window(tester);
    expect(grown.width, greaterThan(before.width * 1.5));
    // The shape of the video is kept.
    expect(
      grown.width / grown.height,
      closeTo(before.width / before.height, 0.01),
    );

    // Dragged to the left half, it rests at the left side.
    final drag = await tester.startGesture(grown.center);
    for (var i = 0; i < 6; i++) {
      await drag.moveBy(const Offset(-50, -15));
      await tester.pump(const Duration(milliseconds: 100));
    }
    // Held still before it is let go: moved, not thrown.
    await tester.pump(const Duration(milliseconds: 400));
    await drag.up();
    await tester.pump();
    final left = window(tester);
    expect(left.left, 12);
    expect(left.width, grown.width);

    // Closed and opened again: the same place and the same size.
    await tester.tap(find.byType(VideoPicture));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.byTooltip('Back to full screen'));
    await settle(tester);
    await tester.tap(find.byTooltip('Picture-in-picture'));
    await settle(tester);
    final again = window(tester);
    expect(again.left, 12);
    expect(again.top, left.top);
    expect(again.width, grown.width);
    await unmount(tester);
  });

  testWidgets('mini player: thrown off a side it closes; let go short of the '
      'edge it comes back to the side', (tester) async {
    final platform = await floating(tester);
    final box = window(tester);

    // Dragged a little over the right edge and let go slowly: it comes back.
    final slow = await tester.startGesture(box.center);
    await slow.moveBy(const Offset(30, 0));
    await tester.pump(const Duration(milliseconds: 300));
    await slow.moveBy(const Offset(20, 0));
    await tester.pump(const Duration(milliseconds: 300));
    expect(window(tester).right, greaterThan(box.right));
    await tester.pump(const Duration(milliseconds: 300));
    await slow.up();
    await tester.pump();
    expect(MiniPlayer.isShowing, isTrue);
    expect(window(tester).right, box.right);

    // Flung over the edge: gone, and the video ends as with the close button.
    await tester.flingFrom(window(tester).center, const Offset(120, 0), 2000);
    await settle(tester);
    expect(MiniPlayer.isShowing, isFalse);
    expect(platform.log, containsAllInOrder(['pause 1', 'dispose 1']));
    await unmount(tester);
  });

  testWidgets('system window: armed while a video plays, shows only the video', (
    tester,
  ) async {
    final platform = FakeVideoPlatform.install();
    const channel = MethodChannel('tf/pip');
    final armed = <Map<Object?, Object?>>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'arm') armed.add(call.arguments as Map);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    // The screen is kept on for as long as that video plays.
    const appChannel = MethodChannel('tf/app');
    final awake = <bool>[];
    messenger.setMockMethodCallHandler(appChannel, (call) async {
      if (call.method == 'keepScreenOn') awake.add(call.arguments as bool);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(appChannel, null));
    Future<void> system(bool inWindow) => messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall('pipChanged', inWindow)),
      (_) {},
    );

    await tester.pumpWidget(app());
    await tester.tap(find.byIcon(Icons.play_arrow));
    await settle(tester);
    expect(armed.last, {
      'enabled': true,
      'width': 640,
      'height': 360,
      // The window's button pauses while the video plays, and says so in words.
      'playing': true,
      'playLabel': 'Play',
      'pauseLabel': 'Pause',
    });
    expect(awake.last, isTrue);

    // The user leaves the app; Android shrinks the activity.
    await system(true);
    await tester.pump();
    expect(find.byType(VideoPicture), findsOneWidget);
    expect(find.byType(MediaViewerScreen), findsNothing); // kept, but offstage
    expect(find.byType(MediaViewerScreen, skipOffstage: false), findsOneWidget);

    // The window's own button pauses the video, and its next tap plays it again,
    // though nothing is "playing in front" by then.
    Future<void> button() => messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(const MethodCall('pipAction')),
      (_) {},
    );
    await button();
    await tester.pump();
    expect(platform.log.last, 'pause 1');
    expect(armed.last['playing'], isFalse);
    // The picture stays in the window while it is paused.
    expect(find.byType(VideoPicture), findsOneWidget);
    platform.log.clear();
    await button();
    await tester.pump();
    expect(platform.log, contains('play 1'));
    expect(armed.last['playing'], isTrue);

    // The window is closed instead of opened again: no sound from the background.
    await system(false);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(platform.log.last, 'pause 1');
    expect(armed.last['enabled'], isFalse);
    // A paused video lets the screen go dark again.
    expect(awake.last, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byType(MediaViewerScreen), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await settle(tester);
    expect(armed.last['enabled'], isFalse);
    await unmount(tester);
  });
}
