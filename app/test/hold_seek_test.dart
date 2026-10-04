import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/media/media_viewer.dart';
import 'package:telegram_feed/media/video_stage.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fake_video_platform.dart';
import 'media_view_test.dart' show DownloadGateway;

const _video = VideoMedia(
  file: FileRef(id: 4, remoteId: 'd', size: 100, width: 640, height: 360),
  durationSeconds: 100,
);

void main() {
  test('a hold on a short video starts at 2×, follows the slide, and turns '
      'round under 0.4×', () {
    // In the middle or on the right: forwards.
    final hold = HoldSeek.short(x: 400, width: 600);
    expect(hold.speed, 2.0);
    hold.slideTo(440);
    expect(hold.speed, 3.0);
    hold.slideTo(420);
    expect(hold.speed, 2.5);
    // Forty pixels for a whole step, down to 0.4×.
    hold.slideTo(340);
    expect(hold.speed, closeTo(0.5, 0.001));
    // Under 0.4× the video runs backwards, from 1.5× on.
    hold.slideTo(332);
    expect(hold.speed, closeTo(-1.6, 0.001));
    hold.slideTo(320);
    expect(hold.speed, closeTo(-1.9, 0.01));
    // No faster than 6× backwards and 10× forwards.
    hold.slideTo(-1000);
    expect(hold.speed, -6.0);
    hold.slideTo(5000);
    expect(hold.speed, 10.0);

    // On the left third it rewinds from the start.
    final back = HoldSeek.short(x: 100, width: 600);
    expect(back.speed, closeTo(-2.0, 0.001));
    // A slide to the right brings it round to forwards.
    back.slideTo(124);
    expect(back.speed, closeTo(0.5, 0.001));
  });

  test('a hold on a long video goes in three steps and follows no slide', () {
    final forward = HoldSeek.long(forward: true);
    expect(forward.speed, 4.0);
    forward.slideTo(900);
    expect(forward.speed, 4.0);
    expect(forward.nextStep(), isTrue);
    expect(forward.speed, 7.0);
    expect(forward.nextStep(), isTrue);
    expect(forward.speed, 13.0);
    expect(forward.nextStep(), isFalse);
    expect(forward.speed, 13.0);

    final back = HoldSeek.long(forward: false);
    expect(back.speed, -3.0);
    back.nextStep();
    expect(back.speed, -6.0);
    back.nextStep();
    expect(back.speed, -12.0);
  });

  test('a speed is written in tenths, whole where it is whole', () {
    expect(speedLabel(2), '2×');
    expect(speedLabel(0.2), '0.2×');
    expect(speedLabel(1.25), '1.3×');
    expect(speedLabel(13), '13×');
  });

  group('in the viewer', () {
    Future<void> startUp(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump();
      await tester.pump();
    }

    Future<FakeVideoPlatform> open(
      WidgetTester tester, {
      Duration duration = const Duration(seconds: 100),
    }) async {
      final platform = FakeVideoPlatform.install()..duration = duration;
      final gw = DownloadGateway('unused');
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => MediaViewerScreen.open(
                context,
                items: const [_video],
                gateway: gw,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await startUp(tester);
      await tester.pumpAndSettle();
      platform.log.clear();
      return platform;
    }

    Future<void> leave(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }

    List<String> speeds(FakeVideoPlatform p) =>
        p.log.where((l) => l.startsWith('speed 1 ')).toList();
    List<int> seeks(FakeVideoPlatform p) => [
      for (final l in p.log)
        if (l.startsWith('seek 1 ')) int.parse(l.split(' ').last),
    ];

    testWidgets('a held finger plays at 2×, a slide to the right goes faster, '
        'and lifting it gives the speed back', (tester) async {
      final platform = await open(tester);
      final box = tester.getRect(find.byType(VideoStage));
      final finger = await tester.startGesture(
        box.center - const Offset(0, 80),
      );
      await tester.pump(const Duration(milliseconds: 700));
      expect(speeds(platform), ['speed 1 2.0']);
      expect(find.text('2×'), findsOneWidget);

      await finger.moveBy(const Offset(40, 0));
      await tester.pump();
      expect(speeds(platform).last, 'speed 1 3.0');
      expect(find.text('3×'), findsOneWidget);
      await finger.moveBy(const Offset(-60, 0));
      await tester.pump();
      expect(speeds(platform).last, 'speed 1 1.5');
      expect(find.text('1.5×'), findsOneWidget);

      await finger.up();
      await tester.pump();
      expect(platform.log.last, 'speed 1 1.0');
      expect(find.text('1.5×'), findsNothing);
      // It played before and plays on: nothing paused it.
      expect(platform.log, isNot(contains('pause 1')));
      await leave(tester);
    });

    testWidgets('a hold on the left third runs the video backwards, and it '
        'goes on from where the finger lifted', (tester) async {
      final platform = await open(tester);
      // Somewhere in the middle of the video.
      platform.positions[1] = const Duration(seconds: 50);
      await tester.pump(const Duration(milliseconds: 600));
      platform.log.clear();
      final box = tester.getRect(find.byType(VideoStage));
      final finger = await tester.startGesture(
        Offset(box.left + 60, box.center.dy - 80),
      );
      await tester.pump(const Duration(milliseconds: 700));
      // The player stands still and is walked backwards.
      expect(platform.log, contains('pause 1'));
      expect(find.byIcon(Icons.fast_rewind), findsOneWidget);
      expect(find.text('2×'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      final back = seeks(platform);
      expect(back.length, greaterThan(3));
      for (var i = 1; i < back.length; i++) {
        expect(back[i], lessThanOrEqualTo(back[i - 1]));
      }
      // Two seconds at twice the speed: four seconds back, and the hold's own start.
      expect(back.last, inInclusiveRange(43, 47));

      platform.log.clear();
      await finger.up();
      await tester.pump();
      expect(platform.log, contains('play 1'));
      expect(platform.log.last, 'speed 1 1.0');
      expect(find.byIcon(Icons.fast_rewind), findsNothing);
      await leave(tester);
    });

    testWidgets('on a video of more than three minutes the right third speeds '
        'up in steps, the left third rewinds and the middle does nothing', (
      tester,
    ) async {
      final platform = await open(
        tester,
        duration: const Duration(minutes: 10),
      );
      final box = tester.getRect(find.byType(VideoStage));

      var finger = await tester.startGesture(box.center - const Offset(0, 80));
      await tester.pump(const Duration(milliseconds: 700));
      expect(speeds(platform), isEmpty);
      await finger.up();
      await tester.pump();

      finger = await tester.startGesture(
        Offset(box.right - 60, box.center.dy - 80),
      );
      await tester.pump(const Duration(milliseconds: 700));
      expect(speeds(platform), ['speed 1 4.0']);
      expect(find.text('4×'), findsOneWidget);
      // A slide changes nothing here.
      await finger.moveBy(const Offset(-40, 0));
      await tester.pump();
      expect(speeds(platform), ['speed 1 4.0']);
      await tester.pump(const Duration(seconds: 2));
      expect(speeds(platform).last, 'speed 1 7.0');
      await tester.pump(const Duration(seconds: 2));
      expect(speeds(platform).last, 'speed 1 13.0');
      expect(find.text('13×'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      expect(speeds(platform).last, 'speed 1 13.0');
      await finger.up();
      await tester.pump();
      expect(platform.log.last, 'speed 1 1.0');

      platform.positions[1] = const Duration(minutes: 5);
      await tester.pump(const Duration(milliseconds: 600));
      platform.log.clear();
      finger = await tester.startGesture(
        Offset(box.left + 60, box.center.dy - 80),
      );
      await tester.pump(const Duration(milliseconds: 700));
      expect(platform.log, contains('pause 1'));
      expect(find.text('3×'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('6×'), findsOneWidget);
      // Two seconds at three times the speed: about six seconds back.
      expect(seeks(platform).last, inInclusiveRange(291, 296));
      await finger.up();
      await tester.pump();
      await leave(tester);
    });

    testWidgets('a video of under eight seconds is not sought by holding', (
      tester,
    ) async {
      final platform = await open(tester, duration: const Duration(seconds: 7));
      final box = tester.getRect(find.byType(VideoStage));
      final finger = await tester.startGesture(
        box.center - const Offset(0, 80),
      );
      await tester.pump(const Duration(milliseconds: 700));
      expect(speeds(platform), isEmpty);
      expect(find.text('2×'), findsNothing);
      await finger.up();
      await tester.pump();
      await leave(tester);
    });

    testWidgets('the speed menu names five speeds from 0.2× and has a slider '
        'for any speed up to 2.5×', (tester) async {
      final platform = await open(tester);
      await tester.tap(find.byTooltip('Speed'));
      await tester.pumpAndSettle();
      for (final speed in ['0.2×', '0.5×', '1.5×', '2×']) {
        expect(find.text(speed), findsOneWidget);
      }
      // "1×" is a line of the menu and what the slider stands on.
      expect(find.text('1×'), findsNWidgets(2));
      final slider = find.descendant(
        of: find.byType(SpeedSlider),
        matching: find.byType(Slider),
      );
      expect(tester.widget<Slider>(slider).min, 0.2);
      expect(tester.widget<Slider>(slider).max, 2.5);

      // The video follows the slider while the menu is open.
      tester.widget<Slider>(slider).onChanged!(1.26);
      await tester.pump();
      expect(speeds(platform).last, 'speed 1 1.3');
      expect(find.text('1.3×'), findsOneWidget);

      await tester.tap(find.text('0.2×'));
      await tester.pumpAndSettle();
      expect(speeds(platform).last, 'speed 1 0.2');
      await leave(tester);
    });
  });
}
