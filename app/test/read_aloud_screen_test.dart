import 'dart:convert';

import 'package:app_db/app_db.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/service/tts_service.dart';
import 'package:telegram_feed/settings/read_aloud_screen.dart';

void main() {
  late AppDatabase db;
  final previews = <Map<String, Object?>>[];

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    previews.clear();
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
    home: ReadAloudScreen(
      db: db,
      voices: () async => const [
        {'name': 'en-us-x-a', 'locale': 'en-US'},
        {'name': 'en-gb-x-b', 'locale': 'en-GB'},
        {'name': 'ru-ru-x-c', 'locale': 'ru-RU'},
      ],
      stopPreview: () async {},
      preview: ({required text, required language, voice, rate, pitch}) async {
        previews.add({
          'text': text,
          'language': language,
          'voice': voice,
          'rate': rate,
          'pitch': pitch,
        });
      },
    ),
  );

  testWidgets('a voice is added by language name, stored, and previewed', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await settle(tester);
    // Nothing chosen yet: no language rows, only the way to add one.
    expect(find.text('English'), findsOneWidget); // the "when unknown" dropdown
    expect(find.text('Add language'), findsOneWidget);

    await tester.tap(find.text('Add language'));
    await tester.pumpAndSettle();
    expect(find.text('Russian'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'eng');
    await tester.pump();
    expect(find.text('Russian'), findsNothing);
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();
    // The voices of English, by a readable name.
    expect(find.text('Voice B · GB'), findsOneWidget);
    await tester.tap(find.text('Voice B · GB'));
    await tester.pumpAndSettle();
    await settle(tester);
    final stored =
        jsonDecode((await db.setting(TtsKeys.voiceFor('en')))!) as Map;
    expect(stored['name'], 'en-gb-x-b');
    expect(find.text('Voice B · GB'), findsOneWidget); // the new row

    await tester.tap(find.byIcon(Icons.volume_up));
    await settle(tester);
    expect(previews.single['language'], 'en');
    expect((previews.single['voice'] as Map)['name'], 'en-gb-x-b');
    expect(previews.single['rate'], 0.5);

    // Back to the default: the row goes.
    await tester.tap(find.byTooltip('Use the default voice'));
    await settle(tester);
    expect(await db.setting(TtsKeys.voiceFor('en')), '');
    expect(find.text('Voice B · GB'), findsNothing);
    await unmount(tester);
  });

  test('voice names read like names', () {
    expect(
      voiceLabel({'name': 'en-us-x-sfg#female_1-local', 'locale': 'en-US'}),
      'Female 1 · US',
    );
    expect(
      voiceLabel({'name': 'uk-ua-x-hfd-network', 'locale': 'uk-UA'}),
      'Voice HFD · UA · online',
    );
    expect(languageName('uk'), 'Ukrainian');
    expect(languageName('xx'), 'XX');
  });

  testWidgets('max length and default language are persisted', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);
    await tester.tap(find.widgetWithText(DropdownButton<int>, '600'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1200').last);
    await tester.pumpAndSettle();
    await settle(tester);
    expect(await db.setting(TtsKeys.maxChars), '1200');

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Russian').last);
    await tester.pumpAndSettle();
    await settle(tester);
    expect(await db.setting(TtsKeys.defaultLanguage), 'ru');
    await unmount(tester);
  });
}
