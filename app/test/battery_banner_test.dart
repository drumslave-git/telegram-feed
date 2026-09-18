import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/rules/rules_screen.dart';

void main() {
  testWidgets('banner goes away when the app resumes with the exemption', (
    tester,
  ) async {
    var exempt = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BatteryBanner(exempt: () async => exempt)),
      ),
    );
    await tester.pump();
    expect(find.text('Allow'), findsOneWidget);

    // The user grants it in Android's settings and comes back.
    exempt = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(find.text('Allow'), findsNothing);
  });

  testWidgets('banner goes away right after the system dialog grants it', (
    tester,
  ) async {
    var exempt = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BatteryBanner(
            exempt: () async => exempt,
            onRequest: () async => exempt = true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Allow'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Allow'), findsNothing);
  });
}
