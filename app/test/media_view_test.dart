import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/media_view.dart';
import 'package:telegram_feed/media/media_viewer.dart';
import 'package:telegram_feed/media/video_stage.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fake_video_platform.dart';
import 'feeds_screen_test.dart' show ChannelsGateway;

/// 1x1 transparent PNG.
const onePixelPng = [
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  1,
  8,
  6,
  0,
  0,
  0,
  31,
  21, //
  196,
  137,
  0,
  0,
  0,
  13,
  73,
  68,
  65,
  84,
  120,
  218,
  99,
  248,
  255,
  255,
  63,
  0,
  5,
  254,
  2,
  254,
  167,
  53,
  129, //
  132, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
];

/// Completes downloads by hand so progress can be observed.
class DownloadGateway extends ChannelsGateway {
  DownloadGateway(this.localPath) : super(const []);
  final String localPath;
  final progress = StreamController<FileProgress>.broadcast();
  final completers = <int, Completer<FileRef>>{};

  @override
  Stream<FileProgress> fileProgress(int fileId) =>
      progress.stream.where((p) => p.fileId == fileId);

  @override
  Future<FileRef> download(FileRef ref, {int priority = 16}) {
    final c = Completer<FileRef>();
    completers[ref.id] = c;
    return c.future;
  }

  /// (file id, offset) of every [downloadFrom].
  final aimed = <(int, int)>[];
  final priorities = <int>[];
  final cancelled = <int>[];

  @override
  Future<FileProgress> downloadFrom(
    int fileId, {
    int offset = 0,
    int priority = 32,
  }) async {
    aimed.add((fileId, offset));
    priorities.add(priority);
    return FileProgress(fileId: fileId, downloaded: 0, total: 100);
  }

  @override
  Future<void> cancelDownload(int fileId) async => cancelled.add(fileId);

  void finish(int fileId) {
    progress.add(
      FileProgress(
        fileId: fileId,
        downloaded: 10,
        total: 10,
        localPath: localPath,
      ),
    );
    completers[fileId]!.complete(
      FileRef(id: fileId, remoteId: 'r', size: 10, localPath: localPath),
    );
  }
}

void main() {
  late Directory tmp;
  late String pngPath;
  late DownloadGateway gw;

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('tf_media');
    pngPath = '${tmp.path}/p.png';
    File(pngPath).writeAsBytesSync(onePixelPng);
  });
  tearDownAll(() => tmp.deleteSync(recursive: true));
  setUp(() => gw = DownloadGateway(pngPath));

  Widget host(Media m) => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 400,
        child: MediaView(media: m, gateway: gw),
      ),
    ),
  );

  testWidgets('photo: progress placeholder, then the downloaded image', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const PhotoMedia(
          sizes: [
            FileRef(id: 1, remoteId: 'a', size: 5, width: 100, height: 75),
            FileRef(id: 2, remoteId: 'b', size: 50, width: 1280, height: 960),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(gw.completers.keys, [
      2,
    ]); // picked the size wide enough for the viewport

    gw.progress.add(const FileProgress(fileId: 2, downloaded: 5, total: 50));
    await tester.pump();
    await tester.runAsync(() async {
      gw.finish(2);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('already downloaded photo renders immediately', (tester) async {
    await tester.pumpWidget(
      host(
        PhotoMedia(
          sizes: [
            FileRef(
              id: 3,
              remoteId: 'c',
              size: 5,
              width: 100,
              height: 100,
              localPath: pngPath,
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
    expect(gw.completers, isEmpty);
  });

  const video = VideoMedia(
    file: FileRef(id: 4, remoteId: 'd', size: 100, width: 640, height: 360),
    durationSeconds: 754,
  );

  /// Lets the player's start-up (download call, fake platform events) run.
  Future<void> startUp(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
  }

  /// Ends the session's grace period so no timer outlives the test.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    // Disposing the player is asynchronous.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
  }

  Future<void> doubleTap(WidgetTester tester, Offset at) async {
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets(
    'a tap plays in the viewer at once; leaving stops the streaming',
    (tester) async {
      final platform = FakeVideoPlatform.install();
      final orientations = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemChrome.setPreferredOrientations') {
            orientations.add(call.arguments);
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
      await tester.pumpWidget(host(video));
      await tester.pump();
      expect(find.text('12:34'), findsOneWidget);
      expect(gw.aimed, isEmpty);

      await tester.tap(find.byIcon(Icons.play_arrow));
      await startUp(tester);
      await tester.pumpAndSettle();
      expect(find.byType(MediaViewerScreen), findsOneWidget);
      // Plays through the loopback server while TDLib downloads, not after.
      expect(gw.aimed, [(4, 0)]);
      expect(platform.sources.single.uri, startsWith('http://127.0.0.1:'));
      expect(platform.log, contains('play 1'));
      // The device's rotation is left alone.
      expect(orientations, isEmpty);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      expect(find.byType(MediaViewerScreen), findsNothing);
      // No grace period: the player is gone and the download stopped with the viewer.
      expect(platform.log, containsAllInOrder(['pause 1', 'dispose 1']));
      expect(gw.cancelled, [4]);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(orientations, isEmpty);
      await unmount(tester);
    },
  );

  testWidgets('double tap on the edges of the viewer seeks', (tester) async {
    final platform = FakeVideoPlatform.install();
    await tester.pumpWidget(host(video));
    await tester.tap(find.byIcon(Icons.play_arrow));
    await startUp(tester);
    await tester.pumpAndSettle();

    final box = tester.getRect(find.byType(VideoStage));
    await doubleTap(tester, box.centerRight - const Offset(20, 0));
    expect(platform.log, contains('seek 1 10'));
    expect(find.text('10 s'), findsOneWidget);
    await doubleTap(tester, box.centerLeft + const Offset(20, 0));
    expect(platform.log.last, 'seek 1 0');
    await tester.pump(const Duration(seconds: 1));
    await unmount(tester);
  });

  testWidgets('double tap in the middle zooms, a drag moves the picture', (
    tester,
  ) async {
    FakeVideoPlatform.install();
    await tester.pumpWidget(host(video));
    await tester.tap(find.byIcon(Icons.play_arrow));
    await startUp(tester);
    await tester.pumpAndSettle();

    final zoom = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    final box = tester.getRect(find.byType(VideoStage));
    // Middle third, beside the play button that sits in the very centre.
    final at = box.center - const Offset(0, 80);
    await doubleTap(tester, at);
    expect(zoom.value.getMaxScaleOnAxis(), closeTo(2.5, 0.01));
    // The tapped point stayed where it was.
    expect(
      MatrixUtils.transformPoint(zoom.value, at - box.topLeft),
      within(distance: 0.01, from: at - box.topLeft),
    );

    final before = zoom.value.getTranslation().x;
    await tester.dragFrom(
      box.center + const Offset(0, 60),
      const Offset(-120, 0),
    );
    await tester.pumpAndSettle();
    expect(zoom.value.getTranslation().x, lessThan(before - 50));
    expect(zoom.value.getMaxScaleOnAxis(), closeTo(2.5, 0.01));

    await doubleTap(tester, at);
    expect(zoom.value.getMaxScaleOnAxis(), closeTo(1, 0.01));
    expect(find.byType(MediaViewerScreen), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a held finger plays at 2x until it lifts', (tester) async {
    final platform = FakeVideoPlatform.install();
    await tester.pumpWidget(host(video));
    await tester.tap(find.byIcon(Icons.play_arrow));
    await startUp(tester);
    await tester.pumpAndSettle();

    final box = tester.getRect(find.byType(VideoStage));
    final finger = await tester.startGesture(box.center - const Offset(0, 80));
    await tester.pump(const Duration(milliseconds: 700));
    expect(platform.log.last, 'speed 1 2.0');
    expect(find.text('2×'), findsOneWidget);

    await finger.up();
    await tester.pump();
    expect(platform.log.last, 'speed 1 1.0');
    expect(find.text('2×'), findsNothing);
    await unmount(tester);
  });

  testWidgets('a swipe down closes the viewer, a short drag swings back', (
    tester,
  ) async {
    FakeVideoPlatform.install();
    await tester.pumpWidget(host(video));
    await tester.tap(find.byIcon(Icons.play_arrow));
    await startUp(tester);
    await tester.pumpAndSettle();
    final from =
        tester.getRect(find.byType(VideoStage)).center + const Offset(0, 60);

    await tester.dragFrom(from, const Offset(0, 70));
    await tester.pumpAndSettle();
    expect(find.byType(MediaViewerScreen), findsOneWidget);
    expect(tester.getTopLeft(find.byType(VideoStage)).dy, 0);

    // Zoomed in, the same drag moves the picture instead.
    final zoom = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    await doubleTap(tester, from);
    final before = zoom.value.getTranslation().y;
    await tester.dragFrom(from, const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(find.byType(MediaViewerScreen), findsOneWidget);
    expect(zoom.value.getTranslation().y, greaterThan(before + 100));
    await doubleTap(tester, from);

    await tester.dragFrom(from, const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(find.byType(MediaViewerScreen), findsNothing);
    await unmount(tester);
  });

  testWidgets('download button: size, progress, cancel, gone when complete', (
    tester,
  ) async {
    FakeVideoPlatform.install();
    await tester.pumpWidget(host(video));
    await tester.pump();
    expect(find.text('100 B'), findsOneWidget);

    await tester.tap(find.byTooltip('Download'));
    await tester.pump();
    // The whole file from the start, below the priority of a playing video.
    expect(gw.aimed, [(4, 0)]);
    expect(gw.priorities, [16]);
    gw.progress.add(const FileProgress(fileId: 4, downloaded: 40, total: 100));
    await tester.pump();
    await tester.pump();
    expect(find.text('40 B / 100 B'), findsOneWidget);
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .value,
      closeTo(0.4, 0.001),
    );

    await tester.tap(find.byTooltip('Cancel download'));
    await tester.pump();
    expect(gw.cancelled, [4]);
    expect(find.text('100 B'), findsOneWidget);

    // Again, and this time a video that plays meanwhile must not end the download.
    await tester.tap(find.byTooltip('Download'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.play_arrow));
    await startUp(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(MediaViewerScreen), findsOneWidget);
    // The viewer has the button too, in the same state as the row under it.
    expect(find.byTooltip('Cancel download'), findsNWidgets(2));
    // No pumpAndSettle here: the progress ring never settles.
    await tester.tap(find.byType(BackButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await startUp(tester);
    expect(find.byType(MediaViewerScreen), findsNothing);
    expect(gw.cancelled, [4]); // still only the cancel from before

    gw.progress.add(
      FileProgress(fileId: 4, downloaded: 100, total: 100, localPath: pngPath),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip('Download'), findsNothing);
    expect(find.byTooltip('Cancel download'), findsNothing);
    await unmount(tester);
  });

  testWidgets('download button goes once the file got complete by streaming', (
    tester,
  ) async {
    await tester.pumpWidget(host(video));
    await tester.pump();
    expect(find.byTooltip('Download'), findsOneWidget);
    gw.progress.add(
      FileProgress(fileId: 4, downloaded: 100, total: 100, localPath: pngPath),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip('Download'), findsNothing);
    expect(gw.aimed, isEmpty);
  });

  testWidgets('a rebuilt row picks its autoplaying player up again', (
    tester,
  ) async {
    final platform = FakeVideoPlatform.install();
    Widget row() => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          child: VideoView(video: video, gateway: gw, autoplay: true),
        ),
      ),
    );
    await tester.pumpWidget(row());
    await startUp(tester);
    expect(platform.sources, hasLength(1));

    // The list drops the row and builds it again at another index.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(row());
    await tester.pump();
    expect(find.byType(InlineVideo), findsOneWidget);
    expect(platform.sources, hasLength(1));
    expect(platform.log, isNot(contains('dispose 1')));
    await unmount(tester);
  });

  testWidgets('voice message and document rows', (tester) async {
    await tester.pumpWidget(
      host(
        const AudioMedia(
          file: FileRef(id: 5, remoteId: 'e', size: 100),
          durationSeconds: 61,
          isVoice: true,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Voice message'), findsOneWidget);
    expect(find.text('1:01'), findsOneWidget);

    await tester.pumpWidget(
      host(
        const DocumentMedia(
          file: FileRef(id: 6, remoteId: 'f', size: 100),
          fileName: 'report.pdf',
          mimeType: 'application/pdf',
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Tap to download'), findsOneWidget);
    await tester.tap(find.text('Tap to download'));
    await tester.pump();
    expect(gw.completers.keys, [6]);
    expect(find.text('Downloading…'), findsOneWidget);
  });
}
