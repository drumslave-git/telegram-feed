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
  int feed = 1,
  int? chat,
  RulePriority priority = RulePriority.normal,
  bool readAloud = false,
  bool enabled = true,
  Schedule? schedule,
}) => RuleSpec(
  id: id,
  name: 'r$id',
  condition: RuleParser.parse(cond),
  feedId: feed,
  scopeChatId: chat,
  priority: priority,
  readAloud: readAloud,
  enabled: enabled,
  schedule: schedule,
);

/// Feed 1 holds channels -1 and -2.
const oneFeed = {
  1: RuleFeed({-1, -2}),
};

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
        feeds: oneFeed,
      );
    final m1 = e.evaluate(post(-1, 1, 'BTC up'))!;
    expect(m1.rules.map((r) => r.id), [1, 2]);
    expect(m1.priority, RulePriority.urgent);
    expect(m1.readAloud, isTrue);

    final m2 = e.evaluate(post(-2, 2, 'btc up'))!;
    expect(m2.rules.map((r) => r.id), [
      1,
    ]); // rule 2 watches -1 only, rule 4 is off
    expect(m2.priority, RulePriority.silent);
    expect(m2.readAloud, isFalse);

    expect(e.evaluate(post(-2, 3, 'nothing here')), isNull);
    expect(e.evaluate(post(-3, 4, 'btc')), isNull); // in no feed
    expect(e.evaluate(post(-1, 5, '')), isNull); // media without caption
  });

  test("a rule watches its own feed's channels only", () {
    final e = RuleEngine()
      ..update(
        rules: [
          rule(1, 'btc', feed: 1),
          rule(2, 'btc', feed: 2, priority: RulePriority.urgent),
        ],
        feeds: const {
          1: RuleFeed({-1}),
          2: RuleFeed({-1, -2}),
        },
      );
    expect(e.evaluate(post(-1, 1, 'btc'))!.rules.map((r) => r.id), [1, 2]);
    expect(e.evaluate(post(-2, 2, 'btc'))!.rules.map((r) => r.id), [2]);
    // The notification opens the post in the feed of the rule that decides.
    expect(MatchEvent.fromMatch(e.evaluate(post(-1, 3, 'btc'))!).feedId, 2);
    // A rule of a feed that is gone watches nothing.
    e.update(
      feeds: const {
        1: RuleFeed({-1}),
      },
    );
    expect(e.evaluate(post(-2, 4, 'btc')), isNull);
  });

  test('RuleSpec.fromRow parses a database row', () {
    final spec = RuleSpec.fromRow(
      Rule(
        id: 7,
        name: 'crypto',
        enabled: true,
        feedId: 3,
        scopeChatId: -1,
        conditionJson: '{"or":[{"term":"btc"},{"term":"eth","whole":false}]}',
        priority: 'urgent',
        readAloud: true,
        scheduleJson: '{"weekdays":[1,2],"from":"09:00","to":"18:00"}',
        createdAt: DateTime(2026),
      ),
    );
    expect(spec.feedId, 3);
    expect(spec.scopeChatId, -1);
    expect(spec.priority, RulePriority.urgent);
    expect(spec.readAloud, isTrue);
    expect(spec.condition, RuleParser.parse('btc OR ~eth'));
    expect(spec.schedule!.weekdays, {1, 2});
    final whole = RuleSpec.fromRow(
      Rule(
        id: 8,
        name: 'g',
        enabled: false,
        feedId: 3,
        conditionJson: '{"term":"x"}',
        priority: 'silent',
        readAloud: false,
        scheduleJson: null,
        createdAt: DateTime(2026),
      ),
    );
    expect(whole.scopeChatId, isNull);
    expect(whole.enabled, isFalse);
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
        feeds: oneFeed,
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
      final e = RuleEngine()..update(rules: [rule(1, 'hello')], feeds: oneFeed);
      final matches = <RuleMatch>[];
      final cancels = <PostsDeleted>[];
      e.matches.listen(matches.add);
      e.cancellations.listen(cancels.add);
      final sub = e.attach(events.stream);

      events.add(PostAdded(post(-1, 1, 'hello world')));
      events.add(PostEdited(post(-1, 2, 'hello edited'))); // ignored
      events.add(PostAdded(post(-1, 3, 'bye')));
      events.add(const PostsDeleted(chatId: -1, messageIds: [1]));
      events.add(const PostsDeleted(chatId: -9, messageIds: [1])); // in no feed
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(matches.map((m) => m.post.messageId), [1]);
      expect(cancels.map((c) => c.messageIds), [
        [1],
      ]);
      await e.close();
    },
  );

  test("a post the rule's feed hides raises nothing from that rule", () {
    const mediaOnly = FeedFilter(media: MediaPresence.withMedia);
    final e = RuleEngine()
      ..update(
        rules: [rule(1, 'btc', feed: 1), rule(2, 'btc', feed: 2)],
        feeds: const {
          1: RuleFeed({-1}, mediaOnly),
          2: RuleFeed({-2}),
        },
      );
    expect(e.evaluate(post(-1, 1, 'btc up')), isNull);
    expect(e.evaluate(post(-2, 1, 'btc up'))!.rules.single.id, 2);
  });

  test('a rule with no condition notifies about a post without text', () {
    final silent = Post(
      chatId: -1,
      messageId: 1,
      date: 1,
      text: '',
      media: const PhotoMedia(sizes: [FileRef(id: 1, remoteId: 'r', size: 1)]),
    );
    const everyPost = RuleSpec(
      id: 1,
      name: 'every',
      condition: And([]),
      feedId: 1,
    );
    expect(everyPost.matchesEverything, isTrue);
    expect(rule(2, 'btc').matchesEverything, isFalse);

    final e = RuleEngine()..update(rules: [everyPost], feeds: oneFeed);
    expect(e.evaluate(silent), isNotNull);
    expect(e.evaluate(silent)!.rules.single.id, 1);

    // A keyword has nothing to match, and an AI rule nothing to send to the model.
    e.update(rules: [rule(2, 'btc')]);
    expect(e.evaluate(silent), isNull);
    e.update(
      rules: [
        const RuleSpec(
          id: 3,
          name: 'ai',
          condition: And([]),
          feedId: 1,
          semanticPrompt: 'anything at all',
        ),
      ],
    );
    expect(e.evaluate(silent), isNull);
  });

  test('the caption of an album notifies when the feed shows whole posts', () {
    const videos = FeedFilter(kinds: {MediaKind.video});
    // The caption of an album sits on its first picture, which a video feed drops.
    Post caption(int chat) => Post(
      chatId: chat,
      messageId: 1,
      date: 1,
      text: 'btc up',
      albumId: 9,
      media: const PhotoMedia(sizes: [FileRef(id: 1, remoteId: 'r', size: 1)]),
    );
    final e = RuleEngine()
      ..update(
        rules: [rule(1, 'btc', feed: 1), rule(2, 'btc', feed: 2)],
        feeds: {
          1: const RuleFeed({-1}, videos),
          2: RuleFeed({-2}, videos.copyWith(wholePost: false)),
        },
      );
    expect(e.evaluate(caption(-1)), isNotNull); // the row shows it
    expect(e.evaluate(caption(-2)), isNull); // there only the video shows
  });
}
