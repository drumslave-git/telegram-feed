import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    // The formatted text alone: a snack bar or a menu on the screen has plain ones.
    final text = tester.widget<Text>(
      find.byWidgetPredicate((w) => w is Text && w.textSpan != null),
    );
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
              url: 'https://site',
            ),
            TextEntity(offset: 10, length: 6, kind: TextEntityKind.spoiler),
          ],
        ),
      ),
    );
    var spans = spansOf(tester);
    (spans[1].recognizer! as TapGestureRecognizer).onTap!();
    expect(opened, ['https://site']);

    final secret = spans.last;
    expect(secret.text, 'secret');
    expect(secret.style!.color, Colors.transparent);
    (secret.recognizer! as TapGestureRecognizer).onTap!();
    await tester.pump();
    spans = spansOf(tester);
    expect(spans.last.style!.color, isNot(Colors.transparent));
    expect(spans.last.recognizer, isNull);
  });

  group('links, as in the official app', () {
    late List<String> opened;
    late List<String> tags;
    late List<String> clipboard;

    setUp(() {
      opened = [];
      tags = [];
      clipboard = [];
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

    //                    0         1         2         3         4         5         6
    //                    0123456789012345678901234567890123456789012345678901234567890
    const words =
        'read here or example.org, see #pier, call 555-0199, run ls -l';
    Future<void> pump(WidgetTester tester, {bool canCopy = true}) =>
        tester.pumpWidget(
          app(
            FormattedText(
              text: words,
              style: style,
              canCopy: canCopy,
              onOpenLink: opened.add,
              onOpenHashtag: tags.add,
              entities: const [
                TextEntity(
                  offset: 5,
                  length: 4,
                  kind: TextEntityKind.link,
                  url: 'https://hidden.example/x',
                ),
                TextEntity(
                  offset: 13,
                  length: 11,
                  kind: TextEntityKind.link,
                  url: 'https://example.org',
                ),
                TextEntity(offset: 30, length: 5, kind: TextEntityKind.hashtag),
                TextEntity(
                  offset: 42,
                  length: 8,
                  kind: TextEntityKind.phone,
                  url: 'tel:5550199',
                ),
                TextEntity(offset: 56, length: 5, kind: TextEntityKind.code),
              ],
            ),
          ),
        );

    GestureRecognizer? recognizerOf(WidgetTester tester, String piece) =>
        spansOf(tester).firstWhere((s) => s.text == piece).recognizer;

    void tapLink(WidgetTester tester, String piece) =>
        (recognizerOf(tester, piece)! as TapGestureRecognizer).onTap!();

    void tapAt(WidgetTester tester, String piece) =>
        (recognizerOf(tester, piece)! as TapGestureRecognizer).onTapUp!(
          TapUpDetails(
            kind: PointerDeviceKind.touch,
            globalPosition: const Offset(100, 100),
          ),
        );

    testWidgets('a link that shows its own address opens at once', (
      tester,
    ) async {
      await pump(tester);
      tapLink(tester, 'example.org');
      await tester.pump();
      expect(opened, ['https://example.org']);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('a link hidden behind other words asks first', (tester) async {
      await pump(tester);
      tapLink(tester, 'here');
      await tester.pumpAndSettle();
      expect(find.text('Open Link'), findsOneWidget);
      expect(
        find.text('Do you want to open https://hidden.example/x?'),
        findsOneWidget,
      );
      expect(opened, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(opened, isEmpty);

      tapLink(tester, 'here');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(opened, ['https://hidden.example/x']);
    });

    test('links into Telegram, mentions and addresses that are no web pages '
        'are never asked about', () {
      bool asks(String url, String shown) =>
          FormattedTextState.hidesTarget(url, shown);
      expect(asks('https://t.me/durov', '@durov'), isFalse);
      expect(asks('https://t.me/c/123/4', 'this post'), isFalse);
      expect(asks('mailto:a@b.io', 'a@b.io'), isFalse);
      expect(asks('tel:5550199', '555-0199'), isFalse);
      expect(asks('https://example.org/', 'Example.org'), isFalse);
      expect(asks('http://example.org', 'https://example.org'), isFalse);
      expect(asks('https://evil.example', 'example.org'), isTrue);
    });

    testWidgets('a long press on a link offers to open or copy it', (
      tester,
    ) async {
      await pump(tester);
      (recognizerOf(tester, 'example.org')! as TapOrHoldRecognizer).holdForTest(
        const Offset(100, 100),
      );
      await tester.pumpAndSettle();
      expect(find.text('https://example.org'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
      await tester.tap(find.text('Copy link'));
      await tester.pumpAndSettle();
      expect(clipboard, ['https://example.org']);
      expect(opened, isEmpty);
    });

    testWidgets('a hashtag is searched for', (tester) async {
      await pump(tester);
      (recognizerOf(tester, '#pier')! as TapGestureRecognizer).onTap!();
      expect(tags, ['#pier']);
    });

    testWidgets('a phone number offers to call or copy', (tester) async {
      await pump(tester);
      tapAt(tester, '555-0199');
      await tester.pumpAndSettle();
      expect(find.text('Call'), findsOneWidget);
      await tester.tap(find.text('Copy number'));
      await tester.pumpAndSettle();
      expect(clipboard, ['555-0199']);

      tapAt(tester, '555-0199');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Call'));
      await tester.pumpAndSettle();
      expect(opened, ['tel:5550199']);
    });

    testWidgets('a tap on inline code copies it, unless the channel protects '
        'its content', (tester) async {
      await pump(tester);
      (recognizerOf(tester, 'ls -l')! as TapGestureRecognizer).onTap!();
      await tester.pump();
      expect(clipboard, ['ls -l']);
      expect(find.text('Code copied'), findsOneWidget);

      await pump(tester, canCopy: false);
      expect(recognizerOf(tester, 'ls -l'), isNull);
    });
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
