import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/timeline_screen.dart';
import 'package:telegram_feed/media/media_viewer.dart';
import 'package:telegram_feed/media/video_stage.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fake_video_platform.dart';
import 'media_view_test.dart' show DownloadGateway, onePixelPng;

void main() {
  late Directory tmp;
  late String pngPath;

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('tf_viewer');
    pngPath = '${tmp.path}/p.png';
    File(pngPath).writeAsBytesSync(onePixelPng);
  });
  tearDownAll(() => tmp.deleteSync(recursive: true));

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

  /// Album parts are newest first; the card shows them oldest first.
  Widget card(
    DownloadGateway gw, {
    required Media older,
    required Media newer,
  }) => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: PostCard(
          item: TimelineItem(
            Post(
              chatId: -1,
              messageId: 12,
              date: 1,
              albumId: 7,
              text: 'cap',
              media: newer,
            ),
            [
              Post(
                chatId: -1,
                messageId: 11,
                date: 1,
                albumId: 7,
                text: '',
                media: older,
              ),
            ],
          ),
          channelTitle: 'C',
          gateway: gw,
        ),
      ),
    ),
  );

  testWidgets('tapping an album photo opens the viewer on that photo', (
    tester,
  ) async {
    final gw = DownloadGateway(pngPath);
    await tester.pumpWidget(card(gw, older: photo(1), newer: photo(2)));
    await tester.pump();
    await tester.ensureVisible(find.byType(Image).last);
    await tester.pump();
    await tester.tap(find.byType(Image).last);
    await tester.pumpAndSettle();
    expect(find.byType(MediaViewerScreen), findsOneWidget);
    expect(find.text('2 of 2'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(find.text('1 of 2'), findsOneWidget);
  });

  testWidgets('an album pages from a photo to its video and back', (
    tester,
  ) async {
    final platform = FakeVideoPlatform.install();
    final gw = DownloadGateway(pngPath);
    const video = VideoMedia(
      file: FileRef(id: 4, remoteId: 'd', size: 100, width: 640, height: 360),
      durationSeconds: 30,
    );
    await tester.pumpWidget(card(gw, older: photo(1), newer: video));
    await tester.pump();
    await tester.tap(find.byType(Image).first);
    await tester.pumpAndSettle();
    expect(find.text('1 of 2'), findsOneWidget);
    // The video next door is not touched before its page is in front.
    expect(platform.sources, isEmpty);

    Future<void> settle() async {
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
    }

    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await settle();
    expect(find.text('2 of 2'), findsOneWidget);
    expect(find.byType(VideoStage), findsOneWidget);
    expect(platform.sources, hasLength(1));
    expect(platform.log, contains('play 1'));

    // Turning the page ends the video like leaving the viewer does.
    await tester.drag(find.byType(PageView), const Offset(500, 0));
    await settle();
    expect(find.text('1 of 2'), findsOneWidget);
    expect(find.byType(VideoStage), findsNothing);
    expect(platform.log, containsAllInOrder(['pause 1', 'dispose 1']));
    expect(gw.cancelled, [4]);

    await tester.tap(find.byType(BackButton));
    await settle();
    expect(find.byType(MediaViewerScreen), findsNothing);
  });
}
