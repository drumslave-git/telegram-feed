import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/media/gallery.dart';
import 'package:telegram_feed/media/media_viewer.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'media_view_test.dart' show DownloadGateway;

void main() {
  test('the name says the app, the day and the file', () {
    expect(
      Gallery.nameFor(fileId: 7, video: false, now: DateTime(2026, 9, 21)),
      'telegram-feed-20260921-7.jpg',
    );
    expect(
      Gallery.nameFor(fileId: 7, video: true, now: DateTime(2026, 1, 2)),
      'telegram-feed-20260102-7.mp4',
    );
  });

  testWidgets('Save to gallery hands the downloaded file to MediaStore', (
    tester,
  ) async {
    final calls = <Map<Object?, Object?>>[];
    final channel = const MethodChannel('tf/gallery');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add({'method': call.method, ...call.arguments as Map});
          return 'content://media/1';
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final gw = DownloadGateway('/tmp/ready.jpg');
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
                      id: 7,
                      remoteId: 'r7',
                      size: 10,
                      width: 90,
                      height: 90,
                      localPath: '/tmp/ready.jpg',
                    ),
                  ],
                ),
              ],
              gateway: gw,
              gallery: Gallery(channel: channel),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Save to gallery'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(calls.single['method'], 'save');
    expect(calls.single['path'], '/tmp/ready.jpg');
    expect(calls.single['mimeType'], 'image/jpeg');
    expect((calls.single['name']! as String).endsWith('-7.jpg'), isTrue);
    expect(find.textContaining('saved to gallery'), findsOneWidget);
  });
}
