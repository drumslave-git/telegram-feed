import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/post_card.dart';
import 'package:telegram_feed/feeds/reaction_glyph.dart';
import 'package:telegram_feed/feeds/sticker_view.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fixtures.dart';

final class _EmojiGateway extends TimelineGateway {
  _EmojiGateway() : super(const {});

  @override
  Future<Map<String, StickerMedia>> customEmoji(List<String> ids) async => {
    for (final id in ids)
      id: const StickerMedia(
        file: FileRef(id: 9, remoteId: 'r', size: 1),
        format: StickerFormat.webp,
        width: 64,
        height: 64,
      ),
  };
}

/// A post's reactions show whatever they are: an emoji, a custom emoji's sticker, or the
/// star of the paid reaction.
void main() {
  Future<void> pump(WidgetTester tester, Reaction r, {VoidCallback? onTap}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ReactionPill(
                reaction: r,
                gateway: _EmojiGateway(),
                onTap: onTap,
              ),
            ),
          ),
        ),
      );

  testWidgets('a plain emoji is text beside its count', (tester) async {
    await pump(tester, const Reaction(emoji: '🔥', count: 1234));
    expect(find.text('🔥 1.2K'), findsOneWidget);
    expect(find.byType(ReactionGlyph), findsNothing);
  });

  testWidgets('a custom emoji is its sticker', (tester) async {
    await pump(tester, Reaction(emoji: customReaction('77'), count: 7));
    await tester.pump();
    await tester.pump();
    expect(find.byType(StickerView), findsOneWidget);
    expect(find.text(' 7'), findsOneWidget);
    expect(find.textContaining('custom:'), findsNothing);
  });

  testWidgets('the paid reaction is a star', (tester) async {
    await pump(tester, const Reaction(emoji: paidReaction, count: 3));
    expect(find.byIcon(Icons.star_rounded), findsOneWidget);
    expect(find.text(' 3'), findsOneWidget);
    expect(find.textContaining(paidReaction), findsNothing);
  });
}
