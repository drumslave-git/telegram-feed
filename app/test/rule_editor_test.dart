import 'dart:async';
import 'dart:convert';

import 'package:app_db/app_db.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/ai/semantic_gate.dart';
import 'package:telegram_feed/feeds/feed_editor_screen.dart';
import 'package:telegram_feed/rules/rule_editor_screen.dart';
import 'package:telegram_feed/rules/rules_screen.dart';
import 'package:rules/rules.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fixtures.dart';

void main() {
  late AppDatabase db;
  late TimelineGateway gw;

  /// Feed F holds Crypto (-1); feed G holds Other (-2).
  late int feedF;
  late int feedG;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    gw = TimelineGateway({
      -1: [
        Post(chatId: -1, messageId: 2, date: 2, text: 'BTC breaks out'),
        Post(chatId: -1, messageId: 1, date: 1, text: 'quiet day'),
      ],
      -2: [Post(chatId: -2, messageId: 1, date: 1, text: 'BTC elsewhere')],
    });
    feedF = (await db.createFeed('F')).id;
    await db.addSource(feedF, -1, title: 'Crypto');
    feedG = (await db.createFeed('G')).id;
    await db.addSource(feedG, -2, title: 'Other');
  });

  Future<void> settle(WidgetTester tester) => tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await tester.pump();
  });

  /// The editor is a long lazy list; a tall window keeps every field built and tappable.
  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  Widget editor({
    Rule? rule,
    int? feedId,
    bool policy = true,
    SemanticCheck? semanticCheck,
  }) => MaterialApp(
    home: RuleEditorScreen(
      db: db,
      gateway: gw,
      rule: rule,
      feedId: feedId,
      policyGranted: () async => policy,
      openPolicySettings: () async {},
      semanticCheck: semanticCheck,
    ),
  );

  testWidgets(
    'builder: terms, NOT, OR group; saves JSON, scope and read-aloud',
    (tester) async {
      tall(tester);
      await tester.pumpWidget(editor());
      await settle(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'Crypto alerts',
      );
      await tester.pump();
      // A new rule has no condition; the first term is added by hand.
      await tester.tap(find.text('Add a term'));
      await tester.pump();
      // TextFields in tree order: 0 = name, then one per term; the AI description
      // is there only while "Also ask the AI" is on.
      await tester.enterText(find.byType(TextField).at(1), 'btc');
      await tester.pump();
      await tester.tap(find.text('AND another word'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(2), 'airdrop');
      await tester.pump();
      await tester.tap(find.text('Must not contain').last);
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
      // A new rule goes into the first feed and watches all of its channels.
      expect(rule.feedId, feedF);
      expect(rule.scopeChatId, isNull);
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

  testWidgets("the channels to pick are those of the rule's feed", (
    tester,
  ) async {
    tall(tester);
    await tester.pumpWidget(editor(feedId: feedF));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Mine');
    await tester.tap(find.text('Every channel of the feed'));
    await tester.pumpAndSettle();
    expect(find.text('Crypto'), findsWidgets);
    expect(find.text('Other'), findsNothing);
    await tester.tap(find.text('Crypto').last);
    await tester.pumpAndSettle();

    // Another feed: its own channels, and the choice of one starts over.
    await tester.tap(find.text('F'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('G').last);
    await settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('Every channel of the feed'), findsOneWidget);
    await tester.tap(find.text('Every channel of the feed'));
    await tester.pumpAndSettle();
    expect(find.text('Other'), findsWidgets);
    expect(find.text('Crypto'), findsNothing);
    await tester.tap(find.text('Other').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await settle(tester);
    final rule = (await db.allRules()).single;
    expect(rule.feedId, feedG);
    expect(rule.scopeChatId, -2);
    await unmount(tester);
  });

  testWidgets('without a feed there is no rule to save', (tester) async {
    await tester.runAsync(() async {
      await db.deleteFeed(feedF);
      await db.deleteFeed(feedG);
    });
    tall(tester);
    await tester.pumpWidget(editor());
    await settle(tester);
    expect(find.textContaining('create one first'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Orphan');
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(await tester.runAsync(db.allRules), isEmpty);
    await unmount(tester);
  });

  testWidgets('text mode: parse errors shown, valid text saved with schedule', (
    tester,
  ) async {
    tall(tester);
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
    // The error says what is wrong in words; the cursor marks where.
    expect(find.textContaining('where the cursor is'), findsOneWidget);
    expect(find.textContaining('rule syntax'), findsNothing);
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
      tall(tester);
      await tester.pumpWidget(editor(policy: false));
      await settle(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Hacks');
      await tester.pump();
      await tester.tap(find.text('Add a term'));
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
      // The question comes with the choice, not at save time.
      await tester.tap(find.text('Urgent').last);
      await tester.pumpAndSettle();
      expect(find.text('Show urgent posts in Do Not Disturb?'), findsOneWidget);
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await settle(tester);
      final rule = (await db.allRules()).single;
      expect(rule.priority, 'urgent');

      await unmount(tester); // fresh State, not the scrolled one
      tall(tester);
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
    tall(tester);
    await tester.pumpWidget(editor());
    await settle(tester);
    await tester.tap(find.text('Add a term'));
    await tester.pump();
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
        feedId: feedF,
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

  testWidgets(
    'AI rule without keywords: warns, saves the description, dry run asks the model',
    (tester) async {
      final asked = <String>[];
      tall(tester);
      await tester.pumpWidget(
        editor(
          semanticCheck: (text, criteria) async {
            asked.add('$text|${criteria.single}');
            return text.contains('BTC') ? {0} : <int>{};
          },
        ),
      );
      await settle(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'Breakouts',
      );
      await tester.pump();
      await tester.ensureVisible(find.text('Also ask the AI'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Also ask the AI'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'What the post should be about'),
        ' price breakouts ',
      );
      await tester.pump();
      expect(find.textContaining('goes to the AI'), findsOneWidget);
      expect(find.textContaining('not set up yet'), findsOneWidget);

      await tester.ensureVisible(find.text('Test on recent posts'));
      await tester.tap(find.text('Test on recent posts'));
      await settle(tester);
      await tester.pumpAndSettle();
      expect(asked, [
        'BTC breaks out|price breakouts',
        'quiet day|price breakouts',
      ]);
      expect(find.textContaining('The AI matched 1 of the 2'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await settle(tester);
      final rule = (await tester.runAsync(db.allRules))!.single;
      expect(rule.semanticPrompt, 'price breakouts');
      expect(jsonDecode(rule.conditionJson), {'and': <Object?>[]});
      expect(RuleSpec.fromRow(rule).isSemantic, isTrue);

      // Reopening shows the description, empty keywords and no parse error.
      await unmount(tester);
      tall(tester);
      await tester.pumpWidget(editor(rule: rule));
      await settle(tester);
      expect(find.text('price breakouts'), findsOneWidget);
      expect(find.textContaining('goes to the AI'), findsOneWidget);
      await unmount(tester);
    },
  );

  testWidgets('removing a term leaves the next one its own words', (
    tester,
  ) async {
    tall(tester);
    await tester.pumpWidget(editor());
    await settle(tester);
    await tester.tap(find.text('Add a term'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), 'first');
    await tester.pump();
    await tester.tap(find.text('AND another word'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(2), 'second');
    await tester.pump();
    await tester.tap(find.byTooltip('Remove').first);
    await tester.pump();
    final words = tester
        .widgetList<TextField>(find.byType(TextField))
        .skip(1)
        .map((f) => f.controller!.text)
        .toList();
    expect(words, ['second']);
    await unmount(tester);
  });

  testWidgets('switching between builder and text never strands the words', (
    tester,
  ) async {
    tall(tester);
    await tester.pumpWidget(editor());
    await settle(tester);
    // An empty text form goes back to an empty builder.
    await tester.tap(find.text('Text'));
    await tester.pump();
    await tester.tap(find.text('Builder'));
    await tester.pump();
    expect(find.text('Add a term'), findsOneWidget);
    expect(find.textContaining('where the cursor is'), findsNothing);

    // Terms typed so far go to the text form, rows without words stay behind.
    await tester.tap(find.text('Add a term'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), 'btc');
    await tester.pump();
    await tester.tap(find.text('AND another word'));
    await tester.pump();
    await tester.tap(find.text('Text'));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
      'btc',
    );
    await unmount(tester);
  });

  testWidgets('leaving with changes asks first; unchanged leaves at once', (
    tester,
  ) async {
    final nav = GlobalKey<NavigatorState>();
    tall(tester);
    await tester.pumpWidget(
      MaterialApp(navigatorKey: nav, home: const Text('rules')),
    );
    void push() => unawaited(
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => RuleEditorScreen(
            db: db,
            gateway: gw,
            policyGranted: () async => true,
            openPolicySettings: () async {},
          ),
        ),
      ),
    );
    push();
    await settle(tester);
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('rules'), findsOneWidget);

    push();
    await settle(tester);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Half');
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('New rule'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('rules'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets(
    'rules list: AI rules show their description; failures show a quiet warning',
    (tester) async {
      await db.insertRule(
        RulesCompanion.insert(
          name: 'Rates',
          feedId: feedF,
          conditionJson: '{"term":"rate"}',
          priority: 'normal',
          semanticPrompt: const Value('central bank decisions'),
          createdAt: DateTime(2026),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: RulesScreen(db: db, gateway: gw),
        ),
      );
      await settle(tester);
      expect(
        find.textContaining('AI: central bank decisions · only if rate'),
        findsOneWidget,
      );
      expect(find.text('AI rules are being skipped'), findsNothing);

      await tester.runAsync(
        () => db.setSetting(
          AiKeys.lastError,
          jsonEncode({
            'message': 'The AI endpoint answered 401: bad key',
            'at': 0,
          }),
        ),
      );
      await settle(tester);
      expect(find.text('AI rules are being skipped'), findsOneWidget);
      expect(find.textContaining('401: bad key'), findsOneWidget);
      await unmount(tester);
    },
  );

  testWidgets('a rule with no condition notifies about every post', (
    tester,
  ) async {
    tall(tester);
    await tester.pumpWidget(editor());
    await settle(tester);
    expect(find.textContaining('every new post'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Name'),
      'Everything',
    );
    await tester.pump();
    await tester.tap(find.text('Save'));
    await settle(tester);
    final rule = (await db.allRules()).single;
    expect(
      RuleSpec.fromRow(rule).condition,
      isA<And>().having((a) => a.items, 'items', isEmpty),
    );
    await unmount(tester);

    // The list says so rather than showing an empty condition.
    await tester.pumpWidget(
      MaterialApp(
        home: RulesScreen(db: db, gateway: gw),
      ),
    );
    await settle(tester);
    expect(find.textContaining('Every channel · every post'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets(
    'the overview groups the rules by feed; a feed shows its own on a tab',
    (tester) async {
      Future<void> rule(String name, int feed) => db.insertRule(
        RulesCompanion.insert(
          name: name,
          feedId: feed,
          conditionJson: '{"term":"x"}',
          priority: 'normal',
          createdAt: DateTime(2026),
        ),
      );
      await tester.runAsync(() async {
        await rule('Of F', feedF);
        await rule('Of G', feedG);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: RulesScreen(db: db, gateway: gw),
        ),
      );
      await settle(tester);
      // A header per feed, each above its rules.
      expect(find.text('F'), findsOneWidget);
      expect(find.text('G'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('F')).dy,
        lessThan(tester.getTopLeft(find.text('Of F')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Of F')).dy,
        lessThan(tester.getTopLeft(find.text('G')).dy),
      );
      await unmount(tester);

      // The feed's info screen opens on its Rules tab, with that feed's rules only.
      await tester.pumpWidget(
        MaterialApp(
          home: FeedEditorScreen(
            db: db,
            gateway: gw,
            feedId: feedG,
            initialTab: FeedEditorScreen.rulesTab,
          ),
        ),
      );
      await settle(tester);
      await tester.pumpAndSettle();
      expect(find.text('Of G'), findsOneWidget);
      expect(find.text('Of F'), findsNothing);
      expect(find.text('New rule'), findsOneWidget);
      await tester.tap(find.text('New rule'));
      await tester.pumpAndSettle();
      await settle(tester);
      await tester.pumpAndSettle();
      // A new rule from there goes into that feed.
      expect(find.byType(RuleEditorScreen), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DropdownButtonFormField<int>),
          matching: find.text('G'),
        ),
        findsOneWidget,
      );
      await unmount(tester);
    },
  );

  testWidgets('typing a term takes the every-post hint away', (tester) async {
    tall(tester);
    await tester.pumpWidget(editor());
    await settle(tester);
    expect(find.textContaining('every new post'), findsOneWidget);
    await tester.tap(find.text('Text'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), 'bitcoin');
    await tester.pump();
    expect(find.textContaining('every new post'), findsNothing);
    await unmount(tester);
  });

  testWidgets('the first word typed in a term keeps the cursor in that term', (
    tester,
  ) async {
    tall(tester);
    await tester.pumpWidget(editor());
    await settle(tester);
    await tester.tap(find.text('Add a term'));
    await tester.pump();
    final term = find.byType(EditableText).at(1);
    await tester.tap(term);
    await tester.pump();
    final before = tester.state<EditableTextState>(term);
    await tester.enterText(term, 'b');
    await tester.pump();
    // The every-post note above went away; the field is still the one typed into.
    expect(find.textContaining('every new post'), findsNothing);
    final after = tester.state<EditableTextState>(
      find.byType(EditableText).at(1),
    );
    expect(after, same(before));
    expect(after.widget.focusNode.hasFocus, isTrue);
    await unmount(tester);
  });
}
