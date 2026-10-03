import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/bubble_text.dart';
import 'package:telegram_feed/feeds/formatted_text.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

void main() {
  const style = TextStyle(fontSize: 16);

  Widget app(Widget child) => MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: 320, child: child),
      ),
    ),
  );

  /// The words of every piece of rich text under [of], in their order on the screen.
  List<String> wordsOf(WidgetTester tester, Finder of) => [
    for (final t in tester.widgetList<Text>(
      find.descendant(
        of: of,
        matching: find.byWidgetPredicate(
          (w) => w is Text && w.textSpan != null,
        ),
      ),
    ))
      t.textSpan!.toPlainText(),
  ];

  const long =
      'one two three four five six seven eight nine ten eleven twelve thirteen '
      'fourteen fifteen sixteen seventeen eighteen nineteen twenty twenty-one '
      'twenty-two twenty-three twenty-four twenty-five twenty-six twenty-seven '
      'twenty-eight twenty-nine thirty';

  testWidgets('a quote is a block of its own between the words around it', (
    tester,
  ) async {
    const text = 'before\nthe quoted words\nafter';
    await tester.pumpWidget(
      app(
        const FormattedText(
          text: text,
          style: style,
          entities: [
            TextEntity(offset: 7, length: 16, kind: TextEntityKind.quote),
          ],
        ),
      ),
    );
    expect(find.byType(QuoteBlock), findsOneWidget);
    // The line breaks around the block are its edges, not lines of their own.
    expect(wordsOf(tester, find.byType(FormattedText)), [
      'before',
      'the quoted words',
      'after',
    ]);
    expect(wordsOf(tester, find.byType(QuoteBlock)), ['the quoted words']);
    final before = tester.getRect(find.text('before', findRichText: true));
    final quote = tester.getRect(find.byType(QuoteBlock));
    final after = tester.getRect(find.text('after', findRichText: true));
    expect(quote.top, greaterThanOrEqualTo(before.bottom));
    expect(after.top, greaterThanOrEqualTo(quote.bottom));
    // A plain quote is all there and answers no tap of its own.
    expect(find.byIcon(Icons.expand_more), findsNothing);
  });

  testWidgets('an expandable quote shows three lines until it is tapped', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const FormattedText(
          text: long,
          style: style,
          entities: [
            TextEntity(
              offset: 0,
              length: long.length,
              kind: TextEntityKind.quote,
              expandable: true,
            ),
          ],
        ),
      ),
    );
    Text quoted() => tester.widget<Text>(
      find.descendant(
        of: find.byType(QuoteBlock),
        matching: find.byWidgetPredicate(
          (w) => w is Text && w.textSpan != null,
        ),
      ),
    );
    expect(quoted().maxLines, QuoteBlock.closedLines);
    expect(find.byIcon(Icons.expand_more), findsOneWidget);
    final closed = tester.getSize(find.byType(QuoteBlock)).height;

    await tester.tap(find.byType(QuoteBlock));
    await tester.pump();
    expect(quoted().maxLines, isNull);
    expect(find.byIcon(Icons.expand_less), findsOneWidget);
    expect(tester.getSize(find.byType(QuoteBlock)).height, greaterThan(closed));

    await tester.tap(find.byType(QuoteBlock));
    await tester.pump();
    expect(quoted().maxLines, QuoteBlock.closedLines);
  });

  testWidgets('an expandable quote of a line or two is simply shown', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const FormattedText(
          text: 'short one',
          style: style,
          entities: [
            TextEntity(
              offset: 0,
              length: 9,
              kind: TextEntityKind.quote,
              expandable: true,
            ),
          ],
        ),
      ),
    );
    expect(find.byIcon(Icons.expand_more), findsNothing);
    expect(find.byIcon(Icons.expand_less), findsNothing);
  });

  testWidgets(
    'a code block names its language and has the copy button; a block '
    'without a language has only the button',
    (tester) async {
      const text = 'run it:\nprint(1)\nor\nls -l';
      await tester.pumpWidget(
        app(
          const FormattedText(
            text: text,
            style: style,
            entities: [
              TextEntity(
                offset: 8,
                length: 8,
                kind: TextEntityKind.pre,
                language: 'python',
              ),
              TextEntity(offset: 20, length: 5, kind: TextEntityKind.pre),
            ],
          ),
        ),
      );
      expect(find.byType(CodeBlock), findsNWidgets(2));
      expect(find.text('python'), findsOneWidget);
      expect(find.byIcon(Icons.content_copy), findsNWidgets(2));
      expect(wordsOf(tester, find.byType(FormattedText)), [
        'run it:',
        'print(1)',
        'or',
        'ls -l',
      ]);
      final code = tester.widget<Text>(
        find.descendant(
          of: find.byType(CodeBlock).first,
          matching: find.byWidgetPredicate(
            (w) => w is Text && w.textSpan != null,
          ),
        ),
      );
      expect(code.style!.fontFamily, 'monospace');
    },
  );

  testWidgets('a protected post offers no copy button on its code', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const FormattedText(
          text: 'ls -l',
          style: style,
          canCopy: false,
          entities: [
            TextEntity(
              offset: 0,
              length: 5,
              kind: TextEntityKind.pre,
              language: 'sh',
            ),
          ],
        ),
      ),
    );
    expect(find.text('sh'), findsOneWidget);
    expect(find.byIcon(Icons.content_copy), findsNothing);
  });

  testWidgets('the footer shares the last line of the words after a block, and '
      'stands under a text that ends with a block', (tester) async {
    Widget bubble(String text, List<TextEntity> entities) => app(
      BubbleText(
        text: FormattedText(text: text, style: style, entities: entities),
        footer: const Text('12:00', key: Key('footer')),
      ),
    );

    await tester.pumpWidget(
      bubble('quoted\nwords', const [
        TextEntity(offset: 0, length: 6, kind: TextEntityKind.quote),
      ]),
    );
    final words = tester.getRect(find.text('words', findRichText: true));
    var footer = tester.getRect(find.byKey(const Key('footer')));
    expect(footer.bottom, closeTo(words.bottom, 4));
    expect(footer.top, lessThan(words.bottom));

    await tester.pumpWidget(
      bubble('words\nquoted', const [
        TextEntity(offset: 6, length: 6, kind: TextEntityKind.quote),
      ]),
    );
    final quote = tester.getRect(find.byType(QuoteBlock));
    footer = tester.getRect(find.byKey(const Key('footer')));
    expect(footer.top, greaterThanOrEqualTo(quote.bottom));
  });
}
