import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/photo_viewer.dart';
import 'package:telegram_feed/feeds/timeline_screen.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

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

  testWidgets('tapping an album photo opens the viewer on that photo', (
    tester,
  ) async {
    final gw = DownloadGateway(pngPath);
    // Album parts are newest first; the card shows them oldest first.
    final item = TimelineItem(
      Post(
        chatId: -1,
        messageId: 12,
        date: 1,
        albumId: 7,
        text: 'cap',
        media: photo(2),
      ),
      [
        Post(
          chatId: -1,
          messageId: 11,
          date: 1,
          albumId: 7,
          text: '',
          media: photo(1),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PostCard(item: item, channelTitle: 'C', gateway: gw),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.ensureVisible(find.byType(Image).last);
    await tester.pump();
    await tester.tap(find.byType(Image).last);
    await tester.pumpAndSettle();
    expect(find.byType(PhotoViewerScreen), findsOneWidget);
    expect(find.text('2 of 2'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(find.text('1 of 2'), findsOneWidget);
  });
}
