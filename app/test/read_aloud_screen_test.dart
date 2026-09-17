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

  testWidgets('lists languages from voices, stores a voice, previews with it', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await settle(tester);
    expect(find.text('en'), findsWidgets);
    expect(find.text('ru'), findsWidgets);

    // Pick a voice for English.
    await tester.tap(
      find.widgetWithText(DropdownButton<String?>, 'Default').first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('en-gb-x-b').last);
    await tester.pumpAndSettle();
    await settle(tester);
    final stored =
        jsonDecode((await db.setting(TtsKeys.voiceFor('en')))!) as Map;
    expect(stored['name'], 'en-gb-x-b');
    expect(find.text('en-gb-x-b'), findsWidgets);

    await tester.tap(find.byIcon(Icons.volume_up));
    await settle(tester);
    expect(previews.single['language'], 'en');
    expect((previews.single['voice'] as Map)['name'], 'en-gb-x-b');
    expect(previews.single['rate'], 0.5);
    await unmount(tester);
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
    await tester.tap(find.text('ru').last);
    await tester.pumpAndSettle();
    await settle(tester);
    expect(await db.setting(TtsKeys.defaultLanguage), 'ru');
    await unmount(tester);
  });
}
