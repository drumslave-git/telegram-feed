import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/formatted_text.dart';
import 'package:telegram_feed/feeds/post_card.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'media_view_test.dart' show DownloadGateway;

void main() {
  late DownloadGateway gw;
  final clipboard = <String>[];

  setUp(() {
    gw = DownloadGateway('/nonexistent.png');
    clipboard.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('the post menu copies the text', (tester) async {
    var copied = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostCard(
            item: TimelineItem(
              const Post(
                chatId: -1001,
                messageId: 5,
                date: 1700000000,
                text: 'the words of the post',
              ),
            ),
            channelTitle: 'Alpha News',
            gateway: gw,
            onCopyText: () => copied++,
          ),
        ),
      ),
    );
    await tester.longPress(find.text('the words of the post'));
    await tester.pumpAndSettle();
    expect(find.text('Copy text'), findsOneWidget);
    await tester.tap(find.text('Copy text'));
    await tester.pumpAndSettle();
    expect(copied, 1);
  });

  testWidgets('a post without words has no Copy text entry', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostCard(
            item: TimelineItem(
              const Post(
                chatId: -1001,
                messageId: 5,
                date: 1700000000,
                text: '',
                media: UnsupportedMedia('messagePoll'),
              ),
            ),
            channelTitle: 'Alpha News',
            gateway: gw,
            onCopyText: () {},
            onCopyLink: () {},
          ),
        ),
      ),
    );
    await tester.longPress(find.byType(PostCard));
    await tester.pumpAndSettle();
    expect(find.text('Copy text'), findsNothing);
    expect(find.text('Copy link'), findsOneWidget);
  });

  testWidgets('a monospace block carries its own copy button', (tester) async {
    const text = 'run this: flutter test';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FormattedText(
            text: text,
            entities: const [
              TextEntity(offset: 10, length: 12, kind: TextEntityKind.pre),
            ],
            style: const TextStyle(fontSize: 16),
          ),
        ),
      ),
    );
    final button = find.byIcon(Icons.content_copy);
    expect(button, findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(clipboard, ['flutter test']);
    expect(find.text('Code copied'), findsOneWidget);
  });

  testWidgets('text without a block has no copy button', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FormattedText(
            text: 'plain words',
            entities: const [
              TextEntity(offset: 0, length: 5, kind: TextEntityKind.bold),
            ],
            style: const TextStyle(fontSize: 16),
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.content_copy), findsNothing);
  });
}
