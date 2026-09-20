import 'dart:io';

import 'package:app_db/app_db.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/timeline_screen.dart';
import 'package:telegram_feed/media/media_viewer.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fake_video_platform.dart';
import 'media_view_test.dart' show onePixelPng;
import 'fixtures.dart';

void main() {
  late AppDatabase db;
  late TimelineGateway gw;
  late Feed feed;
  late Directory dir;

  /// A post with one photo, so every row adds exactly one page to the viewer.
  Post photoPost(int id) => Post(
    chatId: -1,
    messageId: id,
    date: id * 100,
    text: 'post $id',
    media: PhotoMedia(
      sizes: [
        FileRef(id: id, remoteId: 'r$id', size: 10, width: 90, height: 90),
      ],
    ),
  );

  setUpAll(FakeVideoPlatform.install);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('viewer');
    final path = '${dir.path}/p.png';
    File(path).writeAsBytesSync(onePixelPng);
    db = AppDatabase(NativeDatabase.memory());
    // Forty posts, so the first page of the timeline holds thirty of them.
    gw = TimelineGateway(
      {
        -1: [for (var id = 40; id >= 1; id--) photoPost(id)],
      },
      channels: const [Channel(chatId: -1, title: 'One')],
    );
  });

  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> settle(WidgetTester tester) => tester.runAsync(() async {
    for (var i = 0; i < 3; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await tester.pump();
    }
  });

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('the viewer pages through the timeline, not one album', (
    tester,
  ) async {
    await tester.runAsync(() async {
      feed = await db.createFeed('Pictures');
      await db.addSource(feed.id, -1, title: 'One');
      await db.markRead(feed.id, -1, 40);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(db: db, gateway: gw, feed: feed),
      ),
    );
    await settle(tester);

    final state = tester.state<TimelineViewState>(find.byType(TimelineView));
    // The timeline loaded its first page: thirty posts, thirty pictures.
    final media = state.viewerMediaForTest();
    expect(media.length, 30);

    // Asking for more pages the timeline and answers with everything again.
    final more = await tester.runAsync(state.moreViewerMediaForTest);
    expect(more!.length, greaterThan(30));
    await unmount(tester);
  });

  testWidgets('the viewer grows when the reader reaches the older end', (
    tester,
  ) async {
    var asked = 0;
    final items = <Media>[
      for (var i = 0; i < 3; i++)
        PhotoMedia(
          sizes: [
            FileRef(id: i, remoteId: 'r$i', size: 10, width: 90, height: 90),
          ],
        ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => MediaViewerScreen.open(
              context,
              items: items,
              gateway: gw,
              initialIndex: 0,
              onNeedOlder: () async {
                asked++;
                return [
                  ...items,
                  const PhotoMedia(
                    sizes: [
                      FileRef(
                        id: 99,
                        remoteId: 'r99',
                        size: 10,
                        width: 90,
                        height: 90,
                      ),
                    ],
                  ),
                ];
              },
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(); // the route is pushed
    await tester.pump(const Duration(milliseconds: 400)); // the fade finishes
    expect(find.text('1 of 3'), findsOneWidget);

    // Swiping to the second page is already within two of the end: more are asked for.
    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(asked, 1);
    // Both the page in front and its neighbour carry the counter.
    expect(find.text('2 of 4'), findsWidgets);
    await unmount(tester);
  });

  testWidgets('the viewer names the channel, the day, and can share and save', (
    tester,
  ) async {
    var shared = -1;
    var saved = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => MediaViewerScreen.open(
              context,
              items: const [
                PhotoMedia(
                  sizes: [
                    FileRef(
                      id: 1,
                      remoteId: 'r1',
                      size: 10,
                      width: 90,
                      height: 90,
                    ),
                  ],
                ),
              ],
              gateway: gw,
              details: const [
                ViewerDetail(
                  channel: 'Alpha News',
                  date: 1700000000,
                  caption: 'what the post said',
                ),
              ],
              onShare: (i) => shared = i,
              onSave: (i) => saved = i,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Alpha News'), findsOneWidget);
    expect(find.text('what the post said'), findsOneWidget);
    // One picture: no counter, but the day of the post.
    expect(find.textContaining('of 1'), findsNothing);

    await tester.tap(find.byTooltip('Share'));
    await tester.pump();
    expect(shared, 0);
    await tester.tap(find.byTooltip('Save to Saved Messages'));
    await tester.pump();
    expect(saved, 0);
    await unmount(tester);
  });
}
