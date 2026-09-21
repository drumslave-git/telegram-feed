import 'dart:async';
import 'dart:convert';

import 'package:app_db/app_db.dart' show Rule;
import 'package:rules/rules.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'feed_filter.dart';

/// Notification priority (ARCHITECTURE.md section 6.3). Order matters: max wins.
enum RulePriority { silent, normal, urgent }

/// A rule as the engine sees it (parsed from the `rules` table by the host).
final class RuleSpec {
  const RuleSpec({
    required this.id,
    required this.name,
    required this.condition,
    required this.feedId,
    this.enabled = true,
    this.scopeChatId,
    this.priority = RulePriority.normal,
    this.readAloud = false,
    this.schedule,
    this.semanticPrompt,
  });
  final int id;
  final String name;

  /// Keyword condition. For a semantic rule it is the optional pre-filter: `And([])`
  /// matches every post, which then all go to the model.
  final Expr condition;
  final bool enabled;

  /// The feed the rule belongs to: it watches that feed's channels, as the feed shows them.
  final int feedId;

  /// Null for every channel of the feed, otherwise only this one of them.
  final int? scopeChatId;
  final RulePriority priority;
  final bool readAloud;
  final Schedule? schedule;

  /// AI semantic rule (ARCHITECTURE 6.4): what the post should be about. The engine only
  /// applies [condition]; the host asks the model before anything is shown.
  final String? semanticPrompt;

  bool get isSemantic =>
      semanticPrompt != null && semanticPrompt!.trim().isNotEmpty;

  /// True for a rule with no condition at all (`And([])`): it notifies about every post
  /// of its channels, a post without text included.
  bool get matchesEverything => switch (condition) {
    And(:final items) => items.isEmpty,
    _ => false,
  };

  /// Parses a `rules` row. Throws [FormatException] on corrupt JSON.
  factory RuleSpec.fromRow(Rule row) => RuleSpec(
    id: row.id,
    name: row.name,
    enabled: row.enabled,
    feedId: row.feedId,
    scopeChatId: row.scopeChatId,
    condition: Expr.fromJson(
      jsonDecode(row.conditionJson) as Map<Object?, Object?>,
    ),
    priority: RulePriority.values.byName(row.priority),
    readAloud: row.readAloud,
    schedule: row.scheduleJson == null
        ? null
        : Schedule.fromJson(
            jsonDecode(row.scheduleJson!) as Map<Object?, Object?>,
          ),
    semanticPrompt: row.semanticPrompt,
  );
}

/// A post that matched one or more rules.
final class RuleMatch {
  const RuleMatch({
    required this.post,
    required this.rules,
    required this.priority,
    required this.readAloud,
  });
  final Post post;
  final List<RuleSpec> rules;
  final RulePriority priority;
  final bool readAloud;
}

/// One rule of a [MatchEvent], with what the host needs to finish the decision.
final class MatchedRule {
  const MatchedRule({
    required this.name,
    required this.priority,
    required this.readAloud,
    this.feedId = 0,
    this.semanticPrompt,
  });
  final String name;

  /// The feed of the rule; its notification opens the post there.
  final int feedId;
  final RulePriority priority;
  final bool readAloud;

  /// Set for AI semantic rules: the keyword part matched, the model has not been asked yet.
  final String? semanticPrompt;

  bool get isSemantic => semanticPrompt != null;

  factory MatchedRule.of(RuleSpec r) => MatchedRule(
    name: r.name,
    priority: r.priority,
    readAloud: r.readAloud,
    feedId: r.feedId,
    semanticPrompt: r.isSemantic ? r.semanticPrompt!.trim() : null,
  );

  Map<String, Object?> encode() => {
    'name': name,
    'priority': priority.name,
    'readAloud': readAloud,
    'feedId': feedId,
    'prompt': semanticPrompt,
  };

  static MatchedRule decode(Map<Object?, Object?> m) => MatchedRule(
    name: m['name'] as String,
    priority: RulePriority.values.byName(m['priority'] as String),
    readAloud: m['readAloud'] as bool,
    feedId: m['feedId'] as int? ?? 0,
    semanticPrompt: m['prompt'] as String?,
  );
}

/// A rule match as clients receive it. [priority] and [readAloud] cover all of [rules];
/// when some are semantic the host narrows them with [withSemanticVerdicts] first.
final class MatchEvent {
  const MatchEvent({
    required this.post,
    required this.priority,
    required this.readAloud,
    required this.rules,
  });
  final Post post;
  final RulePriority priority;
  final bool readAloud;
  final List<MatchedRule> rules;

  List<String> get ruleNames => [for (final r in rules) r.name];

  /// The feed the notification opens the post in: that of the first rule of the highest
  /// priority; 0 without rules.
  int get feedId {
    for (final r in rules) {
      if (r.priority == priority) return r.feedId;
    }
    return 0;
  }

  /// Positions in [rules] and prompts of the semantic rules still to be checked.
  List<(int, String)> get pendingSemantic => [
    for (var i = 0; i < rules.length; i++)
      if (rules[i].isSemantic) (i, rules[i].semanticPrompt!),
  ];

  factory MatchEvent.of(Post post, List<MatchedRule> rules) {
    var priority = RulePriority.silent;
    var readAloud = false;
    for (final r in rules) {
      if (r.priority.index > priority.index) priority = r.priority;
      readAloud |= r.readAloud;
    }
    return MatchEvent(
      post: post,
      priority: priority,
      readAloud: readAloud,
      rules: rules,
    );
  }

  factory MatchEvent.fromMatch(RuleMatch m) =>
      MatchEvent.of(m.post, [for (final r in m.rules) MatchedRule.of(r)]);

  /// The event after the model's answer: keyword rules stay, semantic rules stay only when
  /// their position is in [confirmed]. Null when nothing is left. A failed check passes an
  /// empty set, so those rules are skipped and the others still fire.
  MatchEvent? withSemanticVerdicts(Set<int> confirmed) {
    final kept = [
      for (var i = 0; i < rules.length; i++)
        if (!rules[i].isSemantic || confirmed.contains(i))
          MatchedRule(
            name: rules[i].name,
            priority: rules[i].priority,
            readAloud: rules[i].readAloud,
            feedId: rules[i].feedId,
          ),
    ];
    return kept.isEmpty ? null : MatchEvent.of(post, kept);
  }

  Map<String, Object?> encode() => {
    'post': encodePost(post),
    'rules': [for (final r in rules) r.encode()],
  };

  static MatchEvent decode(Map<Object?, Object?> m) =>
      MatchEvent.of(decodePost(m['post'] as Map<Object?, Object?>), [
        for (final r in m['rules'] as List)
          MatchedRule.decode(r as Map<Object?, Object?>),
      ]);
}

/// One feed as its rules see it: its channels and what it shows.
final class RuleFeed {
  const RuleFeed(this.chats, [this.filter = FeedFilter.none]);
  final Set<int> chats;
  final FeedFilter filter;
}

/// Evaluates rules against new posts (ARCHITECTURE.md section 6.2).
///
/// - Every rule belongs to a feed and watches its channels, or one of them.
/// - Only [PostAdded] is evaluated; edits are ignored.
/// - [PostsDeleted] is forwarded on [cancellations] so a pending notification can be dropped.
final class RuleEngine {
  RuleEngine({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final _evaluator = RuleEvaluator();
  final _matches = StreamController<RuleMatch>.broadcast();
  final _cancels = StreamController<PostsDeleted>.broadcast();
  List<RuleSpec> _rules = const [];
  Map<int, RuleFeed> _feeds = const {};
  Set<int> _watched = const {};

  Stream<RuleMatch> get matches => _matches.stream;
  Stream<PostsDeleted> get cancellations => _cancels.stream;
  List<RuleSpec> get rules => _rules;

  /// Every channel of every feed.
  Set<int> get watched => _watched;

  /// Replaces the rule set and the feeds (called whenever the database changes).
  void update({List<RuleSpec>? rules, Map<int, RuleFeed>? feeds}) {
    if (rules != null) _rules = List.unmodifiable(rules);
    if (feeds != null) {
      _feeds = Map.unmodifiable(feeds);
      _watched = Set.unmodifiable({for (final f in feeds.values) ...f.chats});
    }
  }

  /// A rule stays quiet about a post its feed hides. An album part counts as shown when
  /// the feed shows whole posts ([FeedFilter.mayShow]): the caption of an album usually
  /// sits on its first picture, which a filter by media kind would drop while the timeline
  /// still shows the post. Whether its siblings really carry what the filter asks for
  /// cannot be seen from one post, so such a rule may notify about an album the timeline
  /// hides after all.
  bool _shows(RuleSpec r, Post post) =>
      _feeds[r.feedId]?.filter.mayShow(post) ?? false;

  /// A post without text (a picture with no caption) only matches a rule with no
  /// condition, which is "every post"; a keyword has nothing to match, and an AI rule
  /// nothing to send to the model.
  static bool _mayMatch(RuleSpec r, String text) =>
      text.isNotEmpty || (r.matchesEverything && !r.isSemantic);

  /// Rules that apply to [chatId] right now: those of the feeds that hold it, for the
  /// whole feed or for this channel.
  List<RuleSpec> candidates(int chatId, {DateTime? now}) {
    final t = now ?? _clock();
    return [
      for (final r in _rules)
        if (r.enabled &&
            (_feeds[r.feedId]?.chats.contains(chatId) ?? false) &&
            (r.scopeChatId == null || r.scopeChatId == chatId) &&
            (r.schedule == null || r.schedule!.isActive(t)))
          r,
    ];
  }

  /// Evaluates one post; returns the match or null. Pure apart from the clock.
  RuleMatch? evaluate(Post post, {DateTime? now}) {
    if (!_watched.contains(post.chatId)) return null;
    final text = post.text;
    final hits = [
      for (final r in candidates(post.chatId, now: now))
        if (_shows(r, post) &&
            _mayMatch(r, text) &&
            _evaluator.matches(r.condition, text))
          r,
    ];
    if (hits.isEmpty) return null;
    var priority = RulePriority.silent;
    var readAloud = false;
    for (final r in hits) {
      if (r.priority.index > priority.index) priority = r.priority;
      readAloud |= r.readAloud;
    }
    return RuleMatch(
      post: post,
      rules: hits,
      priority: priority,
      readAloud: readAloud,
    );
  }

  /// Feeds a gateway's post events into the engine.
  StreamSubscription<PostEvent> attach(Stream<PostEvent> events) =>
      events.listen((e) {
        switch (e) {
          case PostAdded(:final post):
            final m = evaluate(post);
            if (m != null) _matches.add(m);
          case PostEdited():
            break; // edits never notify (SPEC)
          case PostsDeleted():
            if (_watched.contains(e.chatId)) _cancels.add(e);
        }
      });

  Future<void> close() async {
    await _matches.close();
    await _cancels.close();
  }
}
