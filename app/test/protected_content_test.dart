import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/post_card.dart';
import 'package:telegram_feed/host/secure_window.dart';
import 'package:telegram_feed/media/media_viewer.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'media_view_test.dart' show DownloadGateway, onePixelPng;

/// A channel that protects its content: its posts are not copied, shared or saved, and no
/// screenshot is taken of them, as in the official app.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const appChannel = MethodChannel('tf/app');
  late List<bool> secure;
  late Directory tmp;
  late String pngPath;

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('tf_protected');
    pngPath = '${tmp.path}/p.png';
    File(pngPath).writeAsBytesSync(onePixelPng);
  });
  tearDownAll(() => tmp.deleteSync(recursive: true));

  setUp(() {
    secure = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(appChannel, (call) async {
          if (call.method == 'secure') secure.add(call.arguments as bool);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(appChannel, null);
  });

  Widget card(Post post) => MaterialApp(
    home: Scaffold(
      body: PostCard(
        item: TimelineItem(post),
        channelTitle: 'Alpha News',
        gateway: DownloadGateway('/nonexistent.png'),
        onCopyText: () {},
        onCopyLink: () {},
        onShare: () {},
        onSave: () {},
        onSelect: () {},
      ),
    ),
  );

  testWidgets('the menu of a protected post has no Copy text, Share or Save, '
      'and says why', (tester) async {
    await tester.pumpWidget(
      card(
        const Post(
          chatId: -1001,
          messageId: 5,
          date: 1700000000,
          text: 'for members only',
          canBeSaved: false,
        ),
      ),
    );
    await tester.tap(find.text('for members only'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('Copy text'), findsNothing);
    expect(find.text('Share'), findsNothing);
    expect(find.text('Save to Saved Messages'), findsNothing);
    expect(
      find.text('Copying and forwarding is not allowed in this channel.'),
      findsOneWidget,
    );
    // The link to the post is not its content.
    expect(find.text('Copy link'), findsOneWidget);
  });

  testWidgets('the menu of any other post keeps all of them', (tester) async {
    await tester.pumpWidget(
      card(
        const Post(
          chatId: -1001,
          messageId: 5,
          date: 1700000000,
          text: 'for everyone',
        ),
      ),
    );
    await tester.tap(find.text('for everyone'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('Copy text'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Save to Saved Messages'), findsOneWidget);
    expect(
      find.text('Copying and forwarding is not allowed in this channel.'),
      findsNothing,
    );
  });

  test('an album is protected when any of its parts is', () {
    const open = Post(chatId: -1, messageId: 2, date: 1, text: '');
    const closed = Post(
      chatId: -1,
      messageId: 1,
      date: 1,
      text: '',
      canBeSaved: false,
    );
    expect(TimelineItem(open).isProtected, isFalse);
    expect(TimelineItem(open, [closed]).isProtected, isTrue);
  });

  testWidgets('the viewer of a protected picture offers neither Share nor a '
      'save, and blocks screenshots while it is open', (tester) async {
    final photo = PhotoMedia(
      sizes: [
        FileRef(
          id: 1,
          remoteId: 'r1',
          size: 5,
          width: 100,
          height: 100,
          localPath: pngPath,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MediaViewerScreen(
          items: [photo],
          gateway: DownloadGateway(pngPath),
          details: const [
            ViewerDetail(channel: 'Alpha News', date: 1, protected: true),
          ],
          onSave: (_) {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byTooltip('Share'), findsNothing);
    expect(secure, [true]);

    // Neither save is left, so the dots that held them are gone too.
    expect(find.byTooltip('More'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(secure, [true, false]);
  });

  test('the window stays secure until the last holder lets go', () async {
    await SecureWindow.hold('lock');
    await SecureWindow.hold('viewer');
    await SecureWindow.release('viewer');
    expect(secure, [true]);
    await SecureWindow.release('lock');
    expect(secure, [true, false]);
    // Letting go of what was not held changes nothing.
    await SecureWindow.release('lock');
    expect(secure, [true, false]);
  });
}
