import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/bubble_text.dart';
import 'package:telegram_feed/feeds/formatted_text.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

void main() {
  const style = TextStyle(fontSize: 16);

  Widget app(Widget child) => MaterialApp(
    home: Scaffold(
      body: Align(alignment: Alignment.topLeft, child: child),
    ),
  );

  List<TextSpan> spansOf(WidgetTester tester) {
    final text = tester.widget<Text>(find.byType(Text));
    return [
      for (final s in (text.textSpan! as TextSpan).children!) s as TextSpan,
    ];
  }

  testWidgets('overlapping entities: every piece gets the styles covering it', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const FormattedText(
          text: 'bold both italic plain',
          style: style,
          entities: [
            TextEntity(offset: 0, length: 9, kind: TextEntityKind.bold),
            TextEntity(offset: 5, length: 11, kind: TextEntityKind.italic),
          ],
        ),
      ),
    );
    // The plain text stays findable as one string.
    expect(find.text('bold both italic plain'), findsOneWidget);
    final spans = spansOf(tester);
    expect(spans.map((s) => s.text), ['bold ', 'both', ' italic', ' plain']);
    expect(spans[0].style!.fontWeight, FontWeight.w700);
    expect(spans[0].style!.fontStyle, isNull);
    expect(spans[1].style!.fontWeight, FontWeight.w700);
    expect(spans[1].style!.fontStyle, FontStyle.italic);
    expect(spans[2].style!.fontWeight, isNull);
    expect(spans[2].style!.fontStyle, FontStyle.italic);
    expect(spans[3].style!.fontStyle, isNull);
  });

  testWidgets('a link opens, a spoiler is covered until tapped', (
    tester,
  ) async {
    final opened = <String>[];
    await tester.pumpWidget(
      app(
        FormattedText(
          text: 'see site, secret',
          style: style,
          onOpenLink: opened.add,
          entities: const [
            TextEntity(
              offset: 4,
              length: 4,
              kind: TextEntityKind.link,
              url: 'https://example.org',
            ),
            TextEntity(offset: 10, length: 6, kind: TextEntityKind.spoiler),
          ],
        ),
      ),
    );
    var spans = spansOf(tester);
    (spans[1].recognizer! as TapGestureRecognizer).onTap!();
    expect(opened, ['https://example.org']);

    final secret = spans.last;
    expect(secret.text, 'secret');
    expect(secret.style!.color, Colors.transparent);
    (secret.recognizer! as TapGestureRecognizer).onTap!();
    await tester.pump();
    spans = spansOf(tester);
    expect(spans.last.style!.color, isNot(Colors.transparent));
    expect(spans.last.recognizer, isNull);
  });

  testWidgets('entities outside the text are ignored', (tester) async {
    await tester.pumpWidget(
      app(
        const FormattedText(
          text: 'short',
          style: style,
          entities: [
            TextEntity(offset: 3, length: 10, kind: TextEntityKind.bold),
          ],
        ),
      ),
    );
    expect(tester.widget<Text>(find.byType(Text)).data, 'short');
  });

  group('BubbleText', () {
    Widget bubble(String text, double width) => app(
      SizedBox(
        width: width,
        child: BubbleText(
          text: FormattedText(text: text, style: style, entities: const []),
          footer: const SizedBox(key: Key('footer'), width: 60, height: 14),
        ),
      ),
    );

    testWidgets('the footer shares the last line when there is room', (
      tester,
    ) async {
      await tester.pumpWidget(bubble('short', 300));
      final text = tester.getRect(find.byType(FormattedText));
      final footer = tester.getRect(find.byKey(const Key('footer')));
      expect(footer.right, 300);
      expect(footer.bottom, text.bottom);
      expect(footer.left, greaterThan(text.right));
    });

    testWidgets('the footer takes a line of its own when the text fills it', (
      tester,
    ) async {
      // Ahem: every glyph is a 16 px square, so 17 of them leave no room for 60 px.
      await tester.pumpWidget(bubble('x' * 17, 300));
      final text = tester.getRect(find.byType(FormattedText));
      final footer = tester.getRect(find.byKey(const Key('footer')));
      expect(footer.top, text.bottom);
      expect(footer.right, 300);
    });
  });
}
