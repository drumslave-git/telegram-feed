import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/post_card.dart';
import 'package:telegram_feed/feeds/sticker_view.dart';
import 'package:telegram_feed/media/media_viewer.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'media_view_test.dart' show DownloadGateway, onePixelPng;

void main() {
  late DownloadGateway gw;
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('sticker');
    path = '${dir.path}/sticker.webp';
    File(path).writeAsBytesSync(onePixelPng);
    gw = DownloadGateway(path);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  Widget card(Media media) => MaterialApp(
    home: Scaffold(
      body: PostCard(
        item: TimelineItem(
          Post(
            chatId: -1001,
            messageId: 5,
            date: 1700000000,
            text: '',
            media: media,
          ),
        ),
        channelTitle: 'Alpha News',
        gateway: gw,
      ),
    ),
  );

  testWidgets('a sticker keeps its proportions and its own size', (
    tester,
  ) async {
    await tester.pumpWidget(
      card(
        const StickerMedia(
          file: FileRef(id: 9, remoteId: 'r9', size: 100),
          format: StickerFormat.webp,
          width: 512,
          height: 256,
          emoji: 'A',
        ),
      ),
    );
    await tester.pump();
    final view = find.byType(StickerView);
    expect(view, findsOneWidget);
    final size = tester.getSize(view);
    // Half as tall as it is wide, and nowhere near the width of the bubble.
    expect(size.width, 180);
    expect(size.height, 90);
  });

  testWidgets('a round video message is drawn as a circle', (tester) async {
    await tester.pumpWidget(
      card(
        const VideoMedia(
          file: FileRef(id: 5, remoteId: 'r5', size: 100),
          durationSeconds: 12,
          isVideoNote: true,
        ),
      ),
    );
    await tester.pump();
    final oval = find.byType(ClipOval);
    expect(oval, findsWidgets);
    expect(tester.getSize(oval.first), const Size(200, 200));
  });

  testWidgets('neither of them opens the viewer', (tester) async {
    expect(
      MediaViewerScreen.viewable(const [
        StickerMedia(
          file: FileRef(id: 9, remoteId: 'r9', size: 1),
          format: StickerFormat.webp,
        ),
        VideoMedia(
          file: FileRef(id: 5, remoteId: 'r5', size: 1),
          durationSeconds: 1,
          isVideoNote: true,
        ),
        PhotoMedia(sizes: [FileRef(id: 1, remoteId: 'r1', size: 1)]),
      ]),
      hasLength(1),
    );
  });

  test('a sticker says what it stands for where words are needed', () {
    expect(
      mediaLabel(
        const StickerMedia(
          file: FileRef(id: 9, remoteId: 'r9', size: 1),
          format: StickerFormat.webp,
          emoji: 'A',
        ),
      ),
      'A Sticker',
    );
    expect(
      mediaLabel(
        const VideoMedia(
          file: FileRef(id: 5, remoteId: 'r5', size: 1),
          durationSeconds: 1,
          isVideoNote: true,
        ),
      ),
      'Video message',
    );
  });
}
