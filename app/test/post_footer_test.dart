import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/post_card.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

void main() {
  Future<void> pump(WidgetTester tester, Post post, {double width = 300}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: PostFooter(post: post, color: Colors.grey),
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('the signature stands before "edited" and the time, the pin '
      'before the views', (tester) async {
    await pump(
      tester,
      const Post(
        chatId: -1,
        messageId: 1,
        date: 1700000000,
        text: 'x',
        views: 1200,
        editDate: 1700000100,
        signature: 'Ada',
        isPinned: true,
      ),
    );
    final pin = tester.getRect(find.byIcon(Icons.push_pin));
    final eye = tester.getRect(find.byIcon(Icons.visibility_outlined));
    final name = tester.getRect(find.text('Ada, '));
    final edited = tester.getRect(find.text('edited'));
    expect(pin.right, lessThanOrEqualTo(eye.left));
    expect(eye.right, lessThan(name.left));
    expect(name.right, lessThanOrEqualTo(edited.left));
    expect(find.bySemanticsLabel('Pinned'), findsOneWidget);
  });

  testWidgets('a plain post has neither', (tester) async {
    await pump(
      tester,
      const Post(chatId: -1, messageId: 1, date: 1700000000, text: 'x'),
    );
    expect(find.byIcon(Icons.push_pin), findsNothing);
    expect(find.textContaining(', '), findsNothing);
  });

  testWidgets('a long signature gives way to the time', (tester) async {
    await pump(
      tester,
      const Post(
        chatId: -1,
        messageId: 1,
        date: 1700000000,
        text: 'x',
        signature: 'A very long name of an author who signs every post',
      ),
      width: 160,
    );
    expect(tester.takeException(), isNull);
    final footer = tester.getRect(find.byType(PostFooter));
    expect(footer.width, lessThanOrEqualTo(160));
  });

  test('a text of nothing but emoji is drawn large, the larger the fewer', () {
    expect(emojiOnlyCount('🎉'), 1);
    expect(emojiOnlyCount('🎉 🎉'), 2);
    expect(emojiOnlyCount('👨‍👩‍👧'), 1); // one family, joined
    expect(emojiOnlyCount('🇺🇦'), 1); // a flag is two letters
    expect(emojiOnlyCount('1️⃣'), 1);
    expect(emojiOnlyCount('party 🎉'), 0);
    expect(emojiOnlyCount('42'), 0);
    expect(emojiOnlyCount(''), 0);

    expect(emojiOnlySize('🎉', const []), 40.8);
    expect(emojiOnlySize('🎉🎉🎉', const []), 33.6);
    expect(emojiOnlySize('🎉🎉🎉🎉', const []), 26.4);
    expect(emojiOnlySize('🎉🎉🎉🎉🎉🎉🎉🎉', const []), 22.8);
    expect(emojiOnlySize('party 🎉', const []), isNull);
    // Custom emoji alone are larger still.
    expect(
      emojiOnlySize('🎉', const [
        TextEntity(
          offset: 0,
          length: 2,
          kind: TextEntityKind.customEmoji,
          customEmojiId: '1',
        ),
      ]),
      81.6,
    );
    // Formatting makes it a text like any other.
    expect(
      emojiOnlySize('🎉', const [
        TextEntity(offset: 0, length: 2, kind: TextEntityKind.bold),
      ]),
      isNull,
    );
  });

  test('counts are cut to one decimal, never rounded up', () {
    expect(formatCount(0), '0');
    expect(formatCount(999), '999');
    expect(formatCount(1000), '1K');
    expect(formatCount(1099), '1K');
    expect(formatCount(1950), '1.9K');
    expect(formatCount(12345), '12.3K');
    expect(formatCount(999999), '999.9K');
    expect(formatCount(1000000), '1M');
    expect(formatCount(1250000), '1.2M');
    expect(formatCount(19990000), '19.9M');
  });
}
