import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/main.dart' show appPageTransitions;

/// A screen closes with a swipe to the right, from the edge or from anywhere on it, as
/// everywhere in the official app.
void main() {
  testWidgets('a drag from the left edge closes the screen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(pageTransitionsTheme: appPageTransitions),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('second screen')),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('second screen'), findsOneWidget);

    final gesture = await tester.startGesture(const Offset(2, 300));
    await gesture.moveBy(const Offset(400, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('second screen'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  Widget app(Widget second) => MaterialApp(
    theme: ThemeData(pageTransitionsTheme: appPageTransitions),
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () =>
              Navigator.of(context)
                  .push(MaterialPageRoute<void>(builder: (_) => second)),
          child: const Text('open'),
        ),
      ),
    ),
  );

  testWidgets('a swipe to the right from the middle of the screen closes it '
      'too, as in the official app', (tester) async {
    await tester.pumpWidget(app(const Scaffold(body: Text('second screen'))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.dragFrom(const Offset(400, 300), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(find.text('second screen'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('a short swipe, a swipe to the left and a scroll leave the '
      'screen where it is', (tester) async {
    await tester.pumpWidget(
      app(
        Scaffold(
          body: ListView(
            children: [
              const Text('second screen'),
              for (var i = 0; i < 40; i++)
                SizedBox(height: 60, child: Text('row $i')),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // Less than a third of the width, let go without a fling.
    final short = await tester.startGesture(const Offset(300, 300));
    await short.moveBy(const Offset(40, 0));
    await short.moveBy(const Offset(100, 0));
    await tester.pump(const Duration(seconds: 1));
    await short.up();
    await tester.pumpAndSettle();
    expect(find.text('second screen'), findsOneWidget);

    await tester.dragFrom(const Offset(600, 300), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('second screen'), findsOneWidget);

    // A scroll that drifts sideways is still a scroll.
    await tester.dragFrom(const Offset(400, 400), const Offset(30, -200));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsNothing);
    expect(find.text('row 5'), findsOneWidget);
  });

  testWidgets('what scrolls sideways inside a screen keeps its own drags', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        Scaffold(
          appBar: AppBar(title: const Text('second screen')),
          body: PageView(
            controller: PageController(initialPage: 1),
            children: const [Text('page one'), Text('page two')],
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('page two'), findsOneWidget);
    await tester.dragFrom(const Offset(100, 300), const Offset(650, 0));
    await tester.pumpAndSettle();
    // The pages turned; the screen stayed.
    expect(find.text('page one'), findsOneWidget);
    expect(find.text('second screen'), findsOneWidget);
  });

  testWidgets('a screen that must not be left yet is not swiped away', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const PopScope(
          canPop: false,
          child: Scaffold(body: Text('second screen')),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.dragFrom(const Offset(400, 300), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(find.text('second screen'), findsOneWidget);
  });
}
