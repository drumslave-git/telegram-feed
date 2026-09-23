import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/post_card.dart';
import 'package:telegram_feed/media/media_viewer.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fixtures.dart';
import 'media_view_test.dart' show onePixelPng;

/// A picture flies from the row it was tapped in into the viewer and back. Both sides
/// work the name out on their own, so these tests hold that they agree on it.
void main() {
  late Directory dir;
  late ChannelsGateway gw;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hero');
    File('${dir.path}/p.png').writeAsBytesSync(onePixelPng);
    gw = ChannelsGateway(const []);
  });

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows holds on to a picture that was shown until the run ends.
    }
  });

  PhotoMedia photo(int id) => PhotoMedia(
    sizes: [
      FileRef(
        id: id,
        remoteId: 'r$id',
        size: 10,
        width: 90,
        height: 90,
        localPath: '${dir.path}/p.png',
      ),
    ],
  );

  testWidgets('a post and the viewer name the same picture alike', (
    tester,
  ) async {
    const chatId = -1001;
    const messageId = 7;
    // The album of one post: its parts are named by their place in it.
    final item =
        TimelineItem(
            Post(
              chatId: chatId,
              messageId: messageId,
              date: 1700000000,
              text: 'two pictures',
              albumId: 3,
              media: photo(1),
            ),
          )
          ..parts.add(
            Post(
              chatId: chatId,
              messageId: messageId + 1,
              date: 1700000000,
              text: '',
              albumId: 3,
              media: photo(2),
            ),
          );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostCard(item: item, channelTitle: 'A', gateway: gw),
        ),
      ),
    );
    await tester.pump();

    final tags = tester
        .widgetList<Hero>(find.byType(Hero))
        .map((h) => h.tag)
        .toList();
    expect(tags, [
      mediaHeroTag('$chatId:$messageId', 0),
      mediaHeroTag('$chatId:$messageId', 1),
    ]);

    // The viewer is handed the same post twice, one detail per picture, and gives the
    // page in front the name the row carries.
    const detail = ViewerDetail(
      channel: 'A',
      date: 1700000000,
      postKey: '$chatId:$messageId',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MediaViewerScreen(
          items: [photo(1), photo(2)],
          gateway: gw,
          initialIndex: 1,
          details: const [detail, detail],
        ),
      ),
    );
    await tester.pump();
    expect(tester.widgetList<Hero>(find.byType(Hero)).map((h) => h.tag), [
      mediaHeroTag('$chatId:$messageId', 1),
    ]);
  });

  test('a picture with no post behind it flies under no name', () {
    expect(mediaHeroTag('', 0), isNull);
    expect(mediaHeroTag('-1:2', 0), 'media:-1:2:0');
  });
}
