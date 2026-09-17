import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/host/app_host.dart';
import 'package:telegram_feed/main.dart';

void main() {
  testWidgets('shows progress while the core starts', (tester) async {
    await tester.pumpWidget(TelegramFeedApp(host: Completer<AppHost>().future));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows the error when the core cannot start', (tester) async {
    final host = Completer<AppHost>();
    await tester.pumpWidget(TelegramFeedApp(host: host.future));
    host.completeError(StateError('no libtdjson'));
    await tester.pump();
    expect(find.textContaining('Could not start the core'), findsOneWidget);
  });
}
