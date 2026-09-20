import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/formatted_text.dart';
import 'package:telegram_feed/feeds/sticker_view.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'media_view_test.dart' show DownloadGateway, onePixelPng;

/// Answers with one sticker for the id the text carries, and counts the requests.
class EmojiGateway extends DownloadGateway {
  EmojiGateway(super.localPath, {this.known = true});
  final bool known;
  final asked = <List<String>>[];

  @override
  Future<Map<String, StickerMedia>> customEmoji(List<String> ids) async {
    asked.add(ids);
    if (!known) return const {};
    return {
      for (final id in ids)
        id: const StickerMedia(
          file: FileRef(
            id: 9,
            remoteId: 'r9',
            size: 10,
            width: 100,
            height: 100,
          ),
          format: StickerFormat.webp,
          width: 100,
          height: 100,
          emoji: 'A',
        ),
    };
  }
}

void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('emoji');
    path = '${dir.path}/emoji.webp';
    File(path).writeAsBytesSync(onePixelPng);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  Widget text(EmojiGateway gw) => MaterialApp(
    home: Scaffold(
      body: FormattedText(
        text: 'hi A there',
        entities: const [
          TextEntity(
            offset: 3,
            length: 1,
            kind: TextEntityKind.customEmoji,
            customEmojiId: '555',
          ),
        ],
        style: const TextStyle(fontSize: 16),
        gateway: gw,
      ),
    ),
  );

  testWidgets('a custom emoji is drawn as its sticker, asked for once', (
    tester,
  ) async {
    final gw = EmojiGateway(path);
    await tester.pumpWidget(text(gw));
    await tester.pump();
    await tester.pump();
    expect(gw.asked, [
      ['555'],
    ]);
    final sticker = find.byType(StickerView);
    expect(sticker, findsOneWidget);
    // At the size of a line of the text, not the sticker's own 180 px.
    expect(tester.getSize(sticker).width, 20);
  });

  testWidgets('an emoji Telegram does not know stays the plain one', (
    tester,
  ) async {
    final gw = EmojiGateway(path, known: false);
    await tester.pumpWidget(text(gw));
    await tester.pump();
    await tester.pump();
    expect(find.byType(StickerView), findsNothing);
    expect(find.textContaining('hi A there'), findsWidgets);
  });

  testWidgets('without a gateway nothing is asked and the text stands', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FormattedText(
            text: 'hi A there',
            entities: [
              TextEntity(
                offset: 3,
                length: 1,
                kind: TextEntityKind.customEmoji,
                customEmojiId: '555',
              ),
            ],
            style: TextStyle(fontSize: 16),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(StickerView), findsNothing);
  });
}
