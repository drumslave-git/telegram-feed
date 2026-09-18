import 'dart:convert';

import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:telegram_feed/ai/semantic_gate.dart';
import 'package:telegram_feed/settings/ai_settings_screen.dart';

import 'semantic_gate_test.dart' show MemorySecrets;

void main() {
  late AppDatabase db;
  late MemorySecrets secrets;
  var answer = '2';

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    secrets = MemorySecrets();
    answer = '2';
  });

  Future<void> settle(WidgetTester tester) => tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await tester.pump();
  });

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  Widget app() => MaterialApp(
    home: AiSettingsScreen(
      db: db,
      secrets: secrets,
      client: SemanticClient(
        client: MockClient(
          (r) async => http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': answer},
                },
              ],
            }),
            200,
          ),
        ),
      ),
    ),
  );

  testWidgets('saves endpoint and model to settings, the key to the keystore', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await settle(tester);
    await settle(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Endpoint'),
      'http://10.0.2.2:11434/v1',
    );
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Model'), 'llama3');
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'API key'), 'sk-1');
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('not encrypted'), findsOneWidget);

    await tester.tap(find.text('Save and test'));
    await settle(tester);
    await settle(tester);
    expect(find.textContaining('Works'), findsOneWidget);
    expect(
      await tester.runAsync(() => db.setting(AiKeys.baseUrl)),
      'http://10.0.2.2:11434/v1',
    );
    expect(await tester.runAsync(() => db.setting(AiKeys.model)), 'llama3');
    expect(secrets.values[AiKeys.apiKeySecret], 'sk-1');
    // The key never touches the database.
    final all = await tester.runAsync(
      () => db.customSelect('SELECT value FROM settings').get(),
    );
    expect(all!.map((r) => r.read<String>('value')), isNot(contains('sk-1')));
    await unmount(tester);
  });

  testWidgets('a model that answers wrongly is reported', (tester) async {
    answer = '1, 2';
    await tester.pumpWidget(app());
    await settle(tester);
    await settle(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Endpoint'),
      'https://llm.example/v1',
    );
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Model'), 'tiny');
    await tester.pump();
    await tester.tap(find.text('Save and test'));
    await settle(tester);
    await settle(tester);
    expect(find.textContaining('not as expected'), findsOneWidget);
    expect(find.textContaining('not encrypted'), findsNothing);
    await unmount(tester);
  });
}
