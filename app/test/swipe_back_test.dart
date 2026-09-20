import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/main.dart' show appPageTransitions;

/// A screen must close with a drag from the left edge, as everywhere in the official app.
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

    // From the very edge: further in, the drag belongs to the screen itself.
    final gesture = await tester.startGesture(const Offset(2, 300));
    await gesture.moveBy(const Offset(400, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('second screen'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('a drag in the middle leaves the screen where it is', (
    tester,
  ) async {
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
    await tester.dragFrom(const Offset(400, 300), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(find.text('second screen'), findsOneWidget);
  });
}
