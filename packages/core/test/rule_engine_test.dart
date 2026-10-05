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

  test('a service message is not a post: no rule matches it', () {
    // A rule without a condition notifies about every post.
    const everyPost = RuleSpec(
      id: 1,
      name: 'every',
      condition: And([]),
      feedId: 1,
    );
    final e = RuleEngine()..update(rules: [everyPost], feeds: oneFeed);
    expect(e.evaluate(post(-1, 1, '')), isNotNull);
    expect(
      e.evaluate(
        const Post(
          chatId: -1,
          messageId: 2,
          date: 1,
          text: '',
          media: ServiceNote(ServiceKind.pinned, messageId: 1),
        ),
      ),
      isNull,
    );
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

  group('marks and catch-up', () {
    RuleEngine engine() =>
        RuleEngine()..update(rules: [rule(1, 'hello')], feeds: oneFeed);

    Future<List<int>> matchedIds(
      RuleEngine e,
      void Function(StreamController<PostEvent> live) act,
    ) async {
      final got = <int>[];
      final sub = e.matches.listen((m) => got.add(m.post.messageId));
      final live = StreamController<PostEvent>();
      final attached = e.attach(live.stream);
      act(live);
      await Future<void>.delayed(Duration.zero);
      await attached.cancel();
      await sub.cancel();
      return got;
    }

    test('a channel without a mark starts at its newest post', () async {
      final e = engine();
      final got = await matchedIds(e, (_) {
        e.catchUp(
          -1,
          [post(-1, 5, 'hello'), post(-1, 4, 'hello')],
          lastReadMessageId: 0,
          lastMessageId: 5,
        );
      });
      expect(got, isEmpty);
      expect(e.marks, {-1: 5});
    });

    test('what came after the mark is evaluated oldest first, each post once, '
        'read posts left out', () async {
      final e = engine()..restoreMarks({-1: 10});
      final got = await matchedIds(e, (live) {
        // Live before the catch-up: evaluated, but the mark stays where the
        // catch-up has to start.
        live.add(PostAdded(post(-1, 12, 'hello live')));
      });
      expect(got, [12]);
      expect(e.marks, {-1: 10});

      final caught = await matchedIds(e, (_) {
        e.catchUp(
          -1,
          [
            post(-1, 14, 'hello 14'),
            post(-1, 13, 'hello 13'),
            post(-1, 12, 'hello live'),
            post(-1, 11, 'hello read'),
            post(-1, 10, 'hello old'),
          ],
          lastReadMessageId: 11,
          lastMessageId: 14,
        );
      });
      expect(caught, [13, 14]);
      expect(e.marks, {-1: 14});

      final after = await matchedIds(e, (live) {
        live
          ..add(PostAdded(post(-1, 14, 'hello 14'))) // seen
          ..add(PostAdded(post(-1, 9, 'hello older'))) // below the mark
          ..add(PostAdded(post(-1, 15, 'hello 15')));
      });
      expect(after, [15]);
      expect(e.marks, {-1: 15});
    });

    test('an album that came while nothing ran is one post', () {
      final e = RuleEngine()
        ..update(rules: [rule(1, 'quay')], feeds: oneFeed)
        ..restoreMarks({-1: 1});
      final got = <RuleMatch>[];
      e.matches.listen(got.add);
      Post part(int id, String text) =>
          Post(chatId: -1, messageId: id, date: 1, text: text, albumId: 7);
      e.catchUp(
        -1,
        [part(4, ''), part(3, 'the quay'), part(2, '')],
        lastReadMessageId: 0,
        lastMessageId: 4,
      );
      return Future<void>.delayed(Duration.zero, () {
        expect(got.single.post.messageId, 3);
      });
    });

    test('a schedule is judged by when the post came', () async {
      final e = RuleEngine()
        ..update(
          rules: [
            rule(
              1,
              'x',
              // Mondays, 9:00 to 12:00.
              schedule: const Schedule(weekdays: {1}, from: 540, to: 720),
            ),
          ],
          feeds: oneFeed,
        )
        ..restoreMarks({-1: 1});
      final got = <int>[];
      e.matches.listen((m) => got.add(m.post.messageId));
      int at(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;
      e.catchUp(
        -1,
        [
          Post(
            chatId: -1,
            messageId: 2,
            date: at(DateTime(2026, 9, 14, 10)),
            text: 'x',
          ),
          Post(
            chatId: -1,
            messageId: 3,
            date: at(DateTime(2026, 9, 14, 13)),
            text: 'x',
          ),
        ],
        lastReadMessageId: 0,
        lastMessageId: 3,
      );
      await Future<void>.delayed(Duration.zero);
      expect(got, [2]);
    });

    test('a quiet engine looks without matching, and the pause stays quiet '
        'afterwards', () async {
      final e = engine()
        ..restoreMarks({-1: 1})
        ..quiet = true;
      final got = await matchedIds(e, (live) {
        e.catchUp(
          -1,
          [post(-1, 2, 'hello')],
          lastReadMessageId: 0,
          lastMessageId: 2,
        );
        live.add(PostAdded(post(-1, 3, 'hello')));
      });
      expect(got, isEmpty);
      expect(e.marks, {-1: 3});
      e.quiet = false;
      final later = await matchedIds(e, (_) {
        e.catchUp(
          -1,
          [post(-1, 3, 'hello'), post(-1, 2, 'hello')],
          lastReadMessageId: 0,
          lastMessageId: 3,
        );
      });
      expect(later, isEmpty);
    });
  });

  group('albums', () {
    const file = FileRef(id: 1, remoteId: 'r', size: 1);
    Post part(int id, {String text = ''}) => Post(
      chatId: -1,
      messageId: id,
      date: 1,
      text: text,
      albumId: 7,
      media: const PhotoMedia(sizes: [file]),
    );
    const everyPost = RuleSpec(
      id: 1,
      name: 'every',
      condition: And([]),
      feedId: 1,
    );

    test('an album raises one match, on the part with the caption', () async {
      final events = StreamController<PostEvent>();
      final e = RuleEngine(albumWait: const Duration(milliseconds: 40))
        ..update(rules: [everyPost, rule(2, 'quay')], feeds: oneFeed);
      final matches = <RuleMatch>[];
      e.matches.listen(matches.add);
      final sub = e.attach(events.stream);

      events
        ..add(PostAdded(part(10)))
        ..add(PostAdded(part(11, text: 'Three views of the quay')))
        ..add(PostAdded(part(12)));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(matches, isEmpty); // still waiting for more parts
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(matches, hasLength(1));
      expect(matches.single.post.messageId, 11);
      expect(matches.single.rules.map((r) => r.id), [1, 2]);
      await sub.cancel();
      await e.close();
    });

    test('an album without a caption matches a rule with no condition, once, '
        'on its first part', () {
      final e = RuleEngine()
        ..update(rules: [everyPost, rule(2, 'quay')], feeds: oneFeed);
      final m = e.evaluateAlbum([part(12), part(10), part(11)])!;
      expect(m.post.messageId, 10);
      expect(m.rules.map((r) => r.id), [1]);
    });

    test('an album its feed hides raises nothing', () {
      final e = RuleEngine()
        ..update(
          rules: [everyPost],
          feeds: const {
            1: RuleFeed({-1}, FeedFilter(media: MediaPresence.textOnly)),
          },
        );
      expect(e.evaluateAlbum([part(10), part(11)]), isNull);
    });
  });

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

  test(
    "a post the feed's words leave out raises nothing, minimized or not",
    () {
      const noAds = FeedFilter(text: Not(Term('#ad', wholeWord: false)));
      final e = RuleEngine()
        ..update(
          rules: [rule(1, 'btc', feed: 1), rule(2, 'btc', feed: 2)],
          feeds: {
            1: const RuleFeed({-1}, noAds),
            2: RuleFeed({-2}, noAds.copyWith(minimize: true)),
          },
        );
      expect(e.evaluate(post(-1, 1, 'btc up')), isNotNull);
      expect(e.evaluate(post(-1, 2, 'btc up #ad')), isNull);
      expect(e.evaluate(post(-2, 1, 'btc up #ad')), isNull);
    },
  );

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
