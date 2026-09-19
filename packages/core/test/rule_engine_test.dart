import 'dart:async';

import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:rules/rules.dart';
import 'package:telegram_gateway/telegram_gateway.dart';
import 'package:test/test.dart';

Post post(int chat, int id, String text) =>
    Post(chatId: chat, messageId: id, date: 1, text: text);

RuleSpec rule(
  int id,
  String cond, {
  int? chat,
  RulePriority priority = RulePriority.normal,
  bool readAloud = false,
  bool enabled = true,
  Schedule? schedule,
}) => RuleSpec(
  id: id,
  name: 'r$id',
  condition: RuleParser.parse(cond),
  scopeChatId: chat,
  priority: priority,
  readAloud: readAloud,
  enabled: enabled,
  schedule: schedule,
);

void main() {
  test('scope, priority merge and read-aloud flag', () {
    final e = RuleEngine()
      ..update(
        rules: [
          rule(1, 'btc', priority: RulePriority.silent),
          rule(
            2,
            'bitcoin OR btc',
            chat: -1,
            priority: RulePriority.urgent,
            readAloud: true,
          ),
          rule(3, 'eth', chat: -2),
          rule(4, 'btc', enabled: false, priority: RulePriority.urgent),
        ],
        watched: {-1, -2},
      );
    final m1 = e.evaluate(post(-1, 1, 'BTC up'))!;
    expect(m1.rules.map((r) => r.id), [1, 2]);
    expect(m1.priority, RulePriority.urgent);
    expect(m1.readAloud, isTrue);

    final m2 = e.evaluate(post(-2, 2, 'btc up'))!;
    expect(m2.rules.map((r) => r.id), [
      1,
    ]); // rule 2 is scoped to -1, rule 4 disabled
    expect(m2.priority, RulePriority.silent);
    expect(m2.readAloud, isFalse);

    expect(e.evaluate(post(-2, 3, 'nothing here')), isNull);
    expect(e.evaluate(post(-3, 4, 'btc')), isNull); // not watched
    expect(e.evaluate(post(-1, 5, '')), isNull); // media without caption
  });

  test('RuleSpec.fromRow parses a database row', () {
    final spec = RuleSpec.fromRow(
      Rule(
        id: 7,
        name: 'crypto',
        enabled: true,
        scopeKind: 'channel',
        scopeChatId: -1,
        conditionJson: '{"or":[{"term":"btc"},{"term":"eth","whole":false}]}',
        priority: 'urgent',
        readAloud: true,
        scheduleJson: '{"weekdays":[1,2],"from":"09:00","to":"18:00"}',
        createdAt: DateTime(2026),
      ),
    );
    expect(spec.scopeChatId, -1);
    expect(spec.priority, RulePriority.urgent);
    expect(spec.readAloud, isTrue);
    expect(spec.condition, RuleParser.parse('btc OR ~eth'));
    expect(spec.schedule!.weekdays, {1, 2});
    final global = RuleSpec.fromRow(
      Rule(
        id: 8,
        name: 'g',
        enabled: false,
        scopeKind: 'global',
        scopeChatId: -5, // ignored for global rules
        conditionJson: '{"term":"x"}',
        priority: 'silent',
        readAloud: false,
        scheduleJson: null,
        createdAt: DateTime(2026),
      ),
    );
    expect(global.scopeChatId, isNull);
    expect(global.enabled, isFalse);
  });

  test('schedule filters candidates with an injectable clock', () {
    var now = DateTime(2026, 9, 14, 10); // Monday 10:00
    final e = RuleEngine(clock: () => now)
      ..update(
        rules: [
          rule(
            1,
            'x',
            schedule: Schedule(weekdays: {1}, from: 9 * 60, to: 12 * 60),
          ),
        ],
        watched: {-1},
      );
    expect(e.evaluate(post(-1, 1, 'x')), isNotNull);
    now = DateTime(2026, 9, 14, 13);
    expect(e.evaluate(post(-1, 2, 'x')), isNull);
    now = DateTime(2026, 9, 15, 10); // Tuesday
    expect(e.evaluate(post(-1, 3, 'x')), isNull);
  });

  test(
    'attached to a gateway: adds match, edits ignored, deletes cancel',
    () async {
      final events = StreamController<PostEvent>();
      final e = RuleEngine()..update(rules: [rule(1, 'hello')], watched: {-1});
      final matches = <RuleMatch>[];
      final cancels = <PostsDeleted>[];
      e.matches.listen(matches.add);
      e.cancellations.listen(cancels.add);
      final sub = e.attach(events.stream);

      events.add(PostAdded(post(-1, 1, 'hello world')));
      events.add(PostEdited(post(-1, 2, 'hello edited'))); // ignored
      events.add(PostAdded(post(-1, 3, 'bye')));
      events.add(const PostsDeleted(chatId: -1, messageIds: [1]));
      events.add(
        const PostsDeleted(chatId: -9, messageIds: [1]),
      ); // not watched
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(matches.map((m) => m.post.messageId), [1]);
      expect(cancels.map((c) => c.messageIds), [
        [1],
      ]);
      await e.close();
    },
  );

  test(
    'a post every feed hides raises nothing; one feed that shows it is enough',
    () {
      const mediaOnly = FeedFilter(media: MediaPresence.withMedia);
      final e = RuleEngine()
        ..update(
          rules: [rule(1, 'btc')],
          watched: {-1, -2, -3},
          filters: {
            -1: [mediaOnly],
            -2: [mediaOnly, FeedFilter.none],
          },
        );
      expect(e.evaluate(post(-1, 1, 'btc up')), isNull);
      expect(e.evaluate(post(-2, 1, 'btc up')), isNotNull);
      expect(e.evaluate(post(-3, 1, 'btc up')), isNotNull); // no filter known
    },
  );
}
