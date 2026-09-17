import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/media_view.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'feeds_screen_test.dart' show ChannelsGateway;

/// 1x1 transparent PNG.
const _png = [
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
    File(pngPath).writeAsBytesSync(_png);
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

  testWidgets('video shows duration and downloads only on play', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const VideoMedia(
          file: FileRef(
            id: 4,
            remoteId: 'd',
            size: 100,
            width: 640,
            height: 360,
          ),
          durationSeconds: 754,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('12:34'), findsOneWidget);
    expect(gw.completers, isEmpty);
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();
    expect(gw.completers.keys, [4]);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
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
