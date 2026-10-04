import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/formatted_text.dart';
import 'package:telegram_feed/media/media_viewer.dart';
import 'package:telegram_feed/media/video_stage.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fake_video_platform.dart';
import 'media_view_test.dart' show DownloadGateway, onePixelPng;

void main() {
  late Directory tmp;
  late String pngPath;

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('tf_viewer_actions');
    pngPath = '${tmp.path}/p.png';
    File(pngPath).writeAsBytesSync(onePixelPng);
  });
  tearDownAll(() {
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows keeps a file that an image was just read from for a moment; the
      // system's temporary directory is cleaned without this test.
    }
  });

  PhotoMedia photo(int id) => PhotoMedia(
    sizes: [
      FileRef(
        id: id,
        remoteId: 'r$id',
        size: 5,
        width: 100,
        height: 100,
        localPath: pngPath,
      ),
    ],
  );

  Widget opener(
    DownloadGateway gw,
    List<Media> items, {
    List<ViewerDetail> details = const [],
    bool newestFirst = false,
    int initialIndex = 0,
  }) => MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => MediaViewerScreen.open(
            context,
            items: items,
            gateway: gw,
            details: details,
            newestFirst: newestFirst,
            initialIndex: initialIndex,
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  testWidgets(
    'the menu goes to the post and opens the picture in another app',
    (tester) async {
      final calls = <MethodCall>[];
      const app = MethodChannel('tf/app');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(app, (
        call,
      ) async {
        calls.add(call);
        return true;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          app,
          null,
        ),
      );
      var shown = 0;
      final gw = DownloadGateway(pngPath);
      await tester.pumpWidget(
        opener(
          gw,
          [photo(1)],
          details: [
            ViewerDetail(channel: 'A', date: 1, onShowInChat: () => shown++),
          ],
        ),
      );
      await open(tester);

      await tester.tap(find.byTooltip('More'));
      await settle(tester);
      expect(find.text('Show in chat'), findsOneWidget);
      await tester.tap(find.text('Open in…'));
      await settle(tester);
      final opened = calls.singleWhere((c) => c.method == 'openFile');
      expect((opened.arguments as Map)['path'], pngPath);
      expect((opened.arguments as Map)['mime'], 'image/jpeg');
      expect(find.byType(MediaViewerScreen), findsOneWidget);

      // "Show in chat" leaves the viewer and hands over to the timeline.
      await tester.tap(find.byTooltip('More'));
      await settle(tester);
      await tester.tap(find.text('Show in chat'));
      await settle(tester);
      expect(shown, 1);
      expect(find.byType(MediaViewerScreen), findsNothing);
    },
  );

  testWidgets('a picture that came with no timeline has no "Show in chat", and '
      'a protected one opens nowhere else', (tester) async {
    final gw = DownloadGateway(pngPath);
    await tester.pumpWidget(opener(gw, [photo(1)]));
    await open(tester);
    await tester.tap(find.byTooltip('More'));
    await settle(tester);
    expect(find.text('Show in chat'), findsNothing);
    expect(find.text('Open in…'), findsOneWidget);
    await tester.tapAt(const Offset(10, 300));
    await settle(tester);
    await tester.tap(find.byType(BackButton));
    await settle(tester);

    await tester.pumpWidget(
      opener(
        gw,
        [photo(1)],
        details: [
          ViewerDetail(
            channel: 'A',
            date: 1,
            protected: true,
            onShowInChat: () {},
          ),
        ],
      ),
    );
    await open(tester);
    await tester.tap(find.byTooltip('More'));
    await settle(tester);
    expect(find.text('Show in chat'), findsOneWidget);
    expect(find.text('Open in…'), findsNothing);
    expect(find.text('Save to gallery'), findsNothing);
  });

  testWidgets('a tap near a side edge turns the page; at the last page and in '
      'the middle it is a tap on the picture', (tester) async {
    final gw = DownloadGateway(pngPath);
    await tester.pumpWidget(opener(gw, [photo(1), photo(2), photo(3)]));
    await open(tester);
    expect(find.text('1 of 3'), findsOneWidget);
    final size = tester.getSize(find.byType(MediaViewerScreen));
    final right = Offset(size.width - 10, size.height / 2);
    final left = Offset(10, size.height / 2);

    // A single tap is told from a double one first, then the page slides.
    Future<void> tapAt(Offset at) async {
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
    }

    await tapAt(right);
    expect(find.text('2 of 3'), findsOneWidget);
    await tapAt(right);
    expect(find.text('3 of 3'), findsOneWidget);
    // No page further on: the tap takes the bar off the picture, like any other.
    await tapAt(right);
    expect(find.text('3 of 3'), findsNothing);
    await tapAt(right);
    expect(find.text('3 of 3'), findsOneWidget);

    await tapAt(left);
    expect(find.text('2 of 3'), findsOneWidget);
    // In the middle a tap hides the bar and turns nothing.
    await tapAt(Offset(size.width / 2, size.height / 2));
    expect(find.text('2 of 3'), findsNothing);
    await tapAt(Offset(size.width / 2, size.height / 2));
    expect(find.text('2 of 3'), findsOneWidget);
    // Up where the bar is, the edge is no edge.
    await tapAt(Offset(size.width - 10, 70));
    expect(find.text('3 of 3'), findsNothing);
  });

  testWidgets('where the newest comes first, the left edge goes to the older '
      'picture', (tester) async {
    final gw = DownloadGateway(pngPath);
    await tester.pumpWidget(
      opener(gw, [photo(1), photo(2), photo(3)], newestFirst: true),
    );
    await open(tester);
    final size = tester.getSize(find.byType(MediaViewerScreen));
    // The pages lie the other way round: the second item is on the left.
    await tester.tapAt(Offset(10, size.height / 2));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('2 of 3'), findsOneWidget);
    await tester.tapAt(Offset(size.width - 10, size.height / 2));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('1 of 3'), findsOneWidget);
  });

  testWidgets('the caption keeps its formatting, and a link in it closes the '
      'viewer and opens where the timeline opens links', (tester) async {
    final opened = <String>[];
    final gw = DownloadGateway(pngPath);
    await tester.pumpWidget(
      opener(
        gw,
        [photo(1)],
        details: [
          ViewerDetail(
            channel: 'A',
            date: 1,
            caption: 'Bold words and the source',
            entities: const [
              TextEntity(offset: 0, length: 4, kind: TextEntityKind.bold),
              TextEntity(
                offset: 19,
                length: 6,
                kind: TextEntityKind.link,
                url: 'https://t.me/harbour/5',
              ),
            ],
            onOpenLink: opened.add,
          ),
        ],
      ),
    );
    await open(tester);
    final text = tester.widget<FormattedText>(find.byType(FormattedText));
    expect(text.text, 'Bold words and the source');
    expect(text.entities, hasLength(2));
    // Drawn on the dark band whatever the app's theme is.
    expect(
      Theme.of(tester.element(find.byType(FormattedText))).brightness,
      Brightness.dark,
    );

    // The word "source" is the link: its end is the end of the caption.
    final box = tester.getRect(find.byType(FormattedText));
    await tester.tapAt(box.centerRight - const Offset(12, 0));
    await settle(tester);
    expect(opened, ['https://t.me/harbour/5']);
    expect(find.byType(MediaViewerScreen), findsNothing);
  });

  testWidgets('a landscape video has a rotate button, which lays the screen on '
      'its side and gives the choice back on leaving', (tester) async {
    FakeVideoPlatform.install();
    // A phone held upright.
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final orientations = <List<Object?>>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          orientations.add(call.arguments as List<Object?>);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final gw = DownloadGateway('unused');
    await tester.pumpWidget(
      opener(gw, const [
        VideoMedia(
          file: FileRef(
            id: 4,
            remoteId: 'd',
            size: 100,
            width: 640,
            height: 360,
          ),
          durationSeconds: 100,
        ),
      ]),
    );
    await open(tester);
    expect(find.byType(VideoStage), findsOneWidget);
    expect(orientations, isEmpty);

    await tester.tap(find.byTooltip('Rotate'));
    await tester.pump();
    expect(orientations.single, [
      'DeviceOrientation.landscapeLeft',
      'DeviceOrientation.landscapeRight',
    ]);

    await tester.tap(find.byType(BackButton));
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    expect(find.byType(MediaViewerScreen), findsNothing);
    // The device decides again.
    expect(orientations.last, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('dragging the seek bar of a video that is on the phone shows the '
      'frame under the finger; one that is still downloading waits for the '
      'finger to lift', (tester) async {
    final platform = FakeVideoPlatform.install();
    final mp4 = '${tmp.path}/v.mp4';
    File(mp4).writeAsBytesSync(const [0, 0, 0, 0]);
    final gw = DownloadGateway('unused');

    Future<List<String>> seeksWhileDragging(
      VideoMedia video,
      int player,
    ) async {
      await tester.pumpWidget(opener(gw, [video]));
      await open(tester);
      platform.log.clear();
      final bar = tester.getRect(find.byType(Slider));
      final drag = await tester.startGesture(
        Offset(bar.left + bar.width * 0.25, bar.center.dy),
      );
      await tester.pump();
      await drag.moveBy(Offset(bar.width * 0.25, 0));
      await tester.pump();
      final during = platform.log
          .where((l) => l.startsWith('seek $player '))
          .toList();
      await drag.up();
      await settle(tester);
      // Lifting the finger seeks to where it was, in both cases.
      expect(
        platform.log.lastWhere((l) => l.startsWith('seek $player ')),
        isNot('seek $player 0'),
      );
      await tester.tap(find.byType(BackButton));
      await settle(tester);
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      return during;
    }

    final local = await seeksWhileDragging(
      VideoMedia(
        file: FileRef(
          id: 5,
          remoteId: 'e',
          size: 4,
          width: 640,
          height: 360,
          localPath: mp4,
        ),
        durationSeconds: 100,
      ),
      1,
    );
    expect(local, isNotEmpty);

    final streaming = await seeksWhileDragging(
      const VideoMedia(
        file: FileRef(id: 6, remoteId: 'f', size: 100, width: 640, height: 360),
        durationSeconds: 100,
      ),
      2,
    );
    expect(streaming, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
