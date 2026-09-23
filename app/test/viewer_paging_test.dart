import 'dart:io';

import 'package:app_db/app_db.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/timeline_screen.dart';
import 'package:telegram_feed/media/media_viewer.dart';
import 'package:telegram_feed/media/video_stage.dart';
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

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows holds on to a picture the viewer showed until the run ends.
    }
  });

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
      gw.readPositions[-1] = 40;
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
    // The pictures of a feed grow as older ones load, so no "N of M" is shown.
    expect(find.textContaining(' of '), findsNothing);

    // Swiping to the second page is already within two of the end: more are asked for.
    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(asked, 1);
    expect(find.textContaining(' of '), findsNothing);
    await unmount(tester);
  });

  testWidgets('the viewer names the channel, the day, and can share and save', (
    tester,
  ) async {
    final shared = <String>[];
    var saved = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => MediaViewerScreen.open(
              context,
              items: [
                PhotoMedia(
                  sizes: [
                    FileRef(
                      id: 1,
                      remoteId: 'r1',
                      size: 10,
                      width: 90,
                      height: 90,
                      localPath: '${dir.path}/p.png',
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
              onSave: (i) => saved = i,
              share: (path, {required mimeType}) async =>
                  shared.add('$path $mimeType'),
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

    // A tap takes the bar and the words off the picture, and another brings them back.
    await tester.tap(find.byType(ZoomablePhoto));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Alpha News'), findsNothing);
    expect(find.text('what the post said'), findsNothing);
    await tester.tap(find.byType(ZoomablePhoto));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('what the post said'), findsOneWidget);
    // One picture: no counter, but the day of the post.
    expect(find.textContaining('of 1'), findsNothing);

    // The channel and the day keep to one line each, whatever room the buttons leave
    // them: in landscape the bar used to break them into a letter per line.
    final lines = tester.widgetList<Text>(
      find.descendant(
        of: find.byType(ViewerTopBar),
        matching: find.byType(Text),
      ),
    );
    expect(lines, hasLength(2));
    expect(lines.every((t) => t.maxLines == 1), isTrue);

    // Share hands the picture itself to the system sheet, not the post's words.
    await tester.tap(find.byTooltip('Share'));
    await tester.pump();
    await tester.pump();
    expect(shared, ['${dir.path}/p.png image/jpeg']);

    // Saving is behind the three dots, so that the bar fits a phone.
    expect(find.text('Save to Saved Messages'), findsNothing);
    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Save to Saved Messages'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(saved, 0);
    await unmount(tester);
  });

  testWidgets('sharing a video that is not on the device says so', (
    tester,
  ) async {
    final shared = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => MediaViewerScreen.open(
              context,
              items: const [
                VideoMedia(
                  file: FileRef(
                    id: 5,
                    remoteId: 'r5',
                    size: 100,
                    width: 640,
                    height: 360,
                  ),
                  durationSeconds: 30,
                ),
              ],
              gateway: gw,
              share: (path, {required mimeType}) async =>
                  shared.add('$path $mimeType'),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);

    await tester.tap(find.byTooltip('Share'));
    await tester.pump();
    await tester.pump();
    expect(shared, isEmpty);
    expect(find.text('Download the video first to share it.'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets("a video's words go off the picture with its controls", (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => MediaViewerScreen.open(
              context,
              items: const [
                VideoMedia(
                  file: FileRef(
                    id: 6,
                    remoteId: 'r6',
                    size: 100,
                    width: 640,
                    height: 360,
                  ),
                  durationSeconds: 30,
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
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    expect(find.text('what the post said'), findsOneWidget);

    // Beside the play button, on the picture itself.
    await tester.tapAt(const Offset(150, 200));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('what the post said'), findsNothing);
    expect(find.text('Alpha News'), findsNothing);
    await unmount(tester);
  });
}
