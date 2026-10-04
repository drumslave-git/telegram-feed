import 'dart:io';

import 'package:app_db/app_db.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/timeline_screen.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fixtures.dart';

/// A transparent pixel as a PNG the codec really decodes: the pictures here are drawn.
const _pixel = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

void main() {
  late AppDatabase db;
  late TimelineGateway gw;
  late Directory dir;
  late String filePath;
  const channel = Channel(chatId: -1, title: 'One', lastMessageId: 9);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dir = Directory.systemTemp.createTempSync('save');
    filePath = '${dir.path}/file.bin';
    File(filePath).writeAsBytesSync(_pixel);
  });

  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
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

  Future<void> open(WidgetTester tester, List<Post> posts) async {
    gw = TimelineGateway({-1: posts}, channels: const [channel])
      ..readPositions[-1] = 9;
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(db: db, gateway: gw, channel: channel),
      ),
    );
    await settle(tester);
    await tester.pumpAndSettle();
  }

  /// A tap on the post's words opens its menu once no second tap has come.
  Future<void> menu(WidgetTester tester, String words) async {
    await tester.tap(find.text(words));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
  }

  /// What the app asked the phone to keep, as the arguments of each call.
  List<Map<Object?, Object?>> recordSaves(WidgetTester tester) {
    final saves = <Map<Object?, Object?>>[];
    const channel = MethodChannel('tf/gallery');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      saves.add(call.arguments as Map<Object?, Object?>);
      return 'content://saved';
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    return saves;
  }

  FileRef file(int id) =>
      FileRef(id: id, remoteId: 'f$id', size: 68, localPath: filePath);

  testWidgets('the menu offers to keep what the post carries: a document goes '
      'to Downloads', (tester) async {
    final saves = recordSaves(tester);
    await open(tester, [
      Post(
        chatId: -1,
        messageId: 5,
        date: 500,
        text: 'the report',
        media: DocumentMedia(
          file: file(1),
          fileName: 'report.pdf',
          mimeType: 'application/pdf',
        ),
      ),
    ]);
    await menu(tester, 'the report');
    expect(find.text('Save to downloads'), findsOneWidget);
    expect(find.text('Save to gallery'), findsNothing);
    expect(find.text('Save to music'), findsNothing);

    await tester.tap(find.text('Save to downloads'));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(saves.single, {
      'path': filePath,
      'name': 'report.pdf',
      'mimeType': 'application/pdf',
      'to': 'downloads',
    });
    expect(find.text('File saved to Downloads.'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('music goes to Music, a picture to the gallery, a voice message '
      'nowhere', (tester) async {
    final saves = recordSaves(tester);
    await open(tester, [
      Post(
        chatId: -1,
        messageId: 7,
        date: 700,
        text: 'a voice',
        media: AudioMedia(file: file(4), durationSeconds: 3, isVoice: true),
      ),
      Post(
        chatId: -1,
        messageId: 6,
        date: 600,
        text: 'a song',
        media: AudioMedia(
          file: file(2),
          durationSeconds: 61,
          title: 'Tide',
          performer: 'The Quay',
          mimeType: 'audio/mpeg',
        ),
      ),
      Post(
        chatId: -1,
        messageId: 5,
        date: 500,
        text: 'a picture',
        media: PhotoMedia(
          sizes: [
            FileRef(
              id: 3,
              remoteId: 'p',
              size: 68,
              width: 1,
              height: 1,
              localPath: filePath,
            ),
          ],
        ),
      ),
    ]);

    await menu(tester, 'a song');
    expect(find.text('Save to gallery'), findsNothing);
    await tester.tap(find.text('Save to music'));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(saves.last['to'], 'music');
    expect(saves.last['name'], 'The Quay - Tide.mp3');
    expect(find.text('Audio saved to Music.'), findsOneWidget);

    await menu(tester, 'a picture');
    await tester.tap(find.text('Save to gallery'));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(saves.last['to'], 'gallery');
    expect(saves.last['mimeType'], 'image/jpeg');

    await menu(tester, 'a voice');
    expect(find.text('Save to music'), findsNothing);
    expect(find.text('Save to downloads'), findsNothing);
    await unmount(tester);
  });

  testWidgets('an album goes to the gallery whole, its pictures and its video, '
      'oldest first', (tester) async {
    final saves = recordSaves(tester);
    PhotoMedia photo(int id) => PhotoMedia(
      sizes: [
        FileRef(
          id: id,
          remoteId: 'p$id',
          size: 68,
          width: 1,
          height: 1,
          localPath: filePath,
        ),
      ],
    );
    await open(tester, [
      Post(
        chatId: -1,
        messageId: 7,
        date: 700,
        albumId: 9,
        text: 'three of them',
        media: VideoMedia(
          file: FileRef(
            id: 23,
            remoteId: 'v',
            size: 68,
            width: 1,
            height: 1,
            localPath: filePath,
          ),
          durationSeconds: 5,
        ),
      ),
      Post(
        chatId: -1,
        messageId: 6,
        date: 700,
        albumId: 9,
        text: '',
        media: photo(22),
      ),
      Post(
        chatId: -1,
        messageId: 5,
        date: 700,
        albumId: 9,
        text: '',
        media: photo(21),
      ),
    ]);

    await menu(tester, 'three of them');
    await tester.tap(find.text('Save to gallery'));
    await settle(tester);
    await tester.pumpAndSettle();
    expect([for (final s in saves) s['to']], ['gallery', 'gallery', 'gallery']);
    expect(
      [for (final s in saves) s['mimeType']],
      ['image/jpeg', 'image/jpeg', 'video/mp4'],
    );
    // Three files, each under a name of its own.
    expect({for (final s in saves) s['name']}, hasLength(3));
    await unmount(tester);
  });

  testWidgets('a protected post offers nothing to keep', (tester) async {
    recordSaves(tester);
    await open(tester, [
      Post(
        chatId: -1,
        messageId: 5,
        date: 500,
        text: 'the report',
        canBeSaved: false,
        media: DocumentMedia(
          file: file(1),
          fileName: 'report.pdf',
          mimeType: 'application/pdf',
        ),
      ),
    ]);
    await menu(tester, 'the report');
    expect(find.text('Save to downloads'), findsNothing);
    // Reporting is still there.
    expect(find.text('Report'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('Report asks the questions of Telegram and sends the report', (
    tester,
  ) async {
    await open(tester, [
      const Post(chatId: -1, messageId: 5, date: 500, text: 'a bad post'),
    ]);
    await menu(tester, 'a bad post');
    await tester.tap(find.text('Report'));
    await settle(tester);
    await tester.pumpAndSettle();
    // The reasons, as Telegram names them.
    expect(find.text('Spam'), findsOneWidget);
    expect(find.text('Violence'), findsOneWidget);

    await tester.tap(find.text('Spam'));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(gw.reports, ['-1/5 spam']);
    expect(find.textContaining('Your report will be reviewed'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a reason that needs words waits for them; leaving sends '
      'nothing', (tester) async {
    await open(tester, [
      const Post(chatId: -1, messageId: 5, date: 500, text: 'a bad post'),
    ]);
    await menu(tester, 'a bad post');
    await tester.tap(find.text('Report'));
    await settle(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other'));
    await settle(tester);
    await tester.pumpAndSettle();

    // Nothing to send yet.
    final send = find.widgetWithText(TextButton, 'Send report');
    expect(tester.widget<TextButton>(send).onPressed, isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(gw.reports, isEmpty);

    await menu(tester, 'a bad post');
    await tester.tap(find.text('Report'));
    await settle(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other'));
    await settle(tester);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'it sells keys');
    await tester.pump();
    await tester.tap(send);
    await settle(tester);
    await tester.pumpAndSettle();
    expect(gw.reports, ['-1/5 other! it sells keys']);
    await unmount(tester);
  });
}
