import 'dart:convert';

import 'package:app_db/app_db.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/rules/rule_editor_screen.dart';
import 'package:telegram_feed/rules/rules_screen.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'timeline_screen_test.dart' show TimelineGateway;

void main() {
  late AppDatabase db;
  late TimelineGateway gw;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    gw = TimelineGateway({
      -1: [
        Post(chatId: -1, messageId: 2, date: 2, text: 'BTC breaks out'),
        Post(chatId: -1, messageId: 1, date: 1, text: 'quiet day'),
      ],
    });
    final f = await db.createFeed('F');
    await db.addSource(f.id, -1, title: 'Crypto');
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

  Widget editor({Rule? rule, bool policy = true}) => MaterialApp(
    home: RuleEditorScreen(
      db: db,
      gateway: gw,
      rule: rule,
      policyGranted: () async => policy,
      openPolicySettings: () async {},
    ),
  );

  testWidgets(
    'builder: terms, NOT, OR group; saves JSON, scope and read-aloud',
    (tester) async {
      await tester.pumpWidget(editor());
      await settle(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'Crypto alerts',
      );
      await tester.pump();
      // TextFields in tree order: 0 = name, then one per term.
      await tester.enterText(find.byType(TextField).at(1), 'btc');
      await tester.pump();
      await tester.tap(find.text('AND another word'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(2), 'airdrop');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.block).last);
      await tester.pump();
      await tester.tap(find.text('OR alternative'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(3), 'ethereum');
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Read the post aloud'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Read the post aloud'));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Read the post aloud'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(find.textContaining('needs a word'), findsNothing);
      expect(find.textContaining('Give the rule'), findsNothing);

      final rule = (await db.allRules()).single;
      expect(rule.name, 'Crypto alerts');
      expect(rule.scopeKind, 'global');
      expect(rule.readAloud, isTrue);
      expect(rule.priority, 'normal');
      expect(
        jsonDecode(rule.conditionJson),
        jsonDecode(
          '{"or":[{"and":[{"term":"btc","whole":true,"case":false},{"not":{"term":"airdrop","whole":true,"case":false}}]},{"term":"ethereum","whole":true,"case":false}]}',
        ),
      );
      await unmount(tester);
    },
  );

  testWidgets('text mode: parse errors shown, valid text saved with schedule', (
    tester,
  ) async {
    await tester.pumpWidget(editor());
    await settle(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Name'),
      'Night watch',
    );
    await tester.pump();
    await tester.tap(find.text('Text'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), '(a OR b');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.textContaining('rule syntax'), findsOneWidget);
    expect(await db.allRules(), isEmpty);

    await tester.enterText(find.byType(TextField).at(1), '(a OR b) AND NOT c');
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Only at certain times'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Only at certain times'));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Only at certain times'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Sat'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Sat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sat'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await settle(tester);
    final rule = (await db.allRules()).single;
    expect(rule.scheduleJson, isNotNull);
    final s = jsonDecode(rule.scheduleJson!) as Map;
    expect(s['weekdays'], [1, 2, 3, 4, 5, 7]);
    expect(s['from'], '09:00');
    await unmount(tester);
  });

  testWidgets(
    'urgent without policy access asks to open settings; edit loads existing',
    (tester) async {
      await tester.pumpWidget(editor(policy: false));
      await settle(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Hacks');
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'word or phrase'),
        'hack',
      );
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Urgent'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Urgent'));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Urgent').last);
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Show urgent posts in Do Not Disturb?'), findsOneWidget);
      await tester.tap(find.text('Later'));
      await settle(tester);
      final rule = (await db.allRules()).single;
      expect(rule.priority, 'urgent');

      await unmount(tester); // fresh State, not the scrolled one
      await tester.pumpWidget(editor(rule: rule));
      await settle(tester);
      expect(find.text('Edit rule'), findsOneWidget);
      final texts = tester
          .widgetList<TextField>(find.byType(TextField))
          .map((f) => f.controller?.text)
          .toList();
      expect(texts, containsAll(['Hacks', 'hack']));
      await unmount(tester);
    },
  );

  testWidgets('test on recent posts lists matches', (tester) async {
    await tester.pumpWidget(editor());
    await settle(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'word or phrase'),
      'btc',
    );
    await tester.pump();
    await tester.tap(find.text('Test on recent posts'));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('1 of the last 2 posts match:'), findsOneWidget);
    expect(find.text('BTC breaks out'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('rules list shows rules and toggles enabled', (tester) async {
    await db.insertRule(
      RulesCompanion.insert(
        name: 'One',
        scopeKind: 'channel',
        scopeChatId: const Value(-1),
        conditionJson: '{"term":"x"}',
        priority: 'silent',
        createdAt: DateTime(2026),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: RulesScreen(db: db, gateway: gw),
      ),
    );
    await settle(tester);
    expect(find.text('One'), findsOneWidget);
    expect(find.textContaining('Crypto · x'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await settle(tester);
    expect((await db.allRules()).single.enabled, isFalse);
    await unmount(tester);
  });
}
