import 'dart:async';
import 'dart:convert';

import 'package:app_db/app_db.dart' show Rule;
import 'package:rules/rules.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

/// Notification priority (ARCHITECTURE.md section 6.3). Order matters: max wins.
enum RulePriority { silent, normal, urgent }

/// A rule as the engine sees it (parsed from the `rules` table by the host).
final class RuleSpec {
  const RuleSpec({
    required this.id,
    required this.name,
    required this.condition,
    this.enabled = true,
    this.scopeChatId,
    this.priority = RulePriority.normal,
    this.readAloud = false,
    this.schedule,
  });
  final int id;
  final String name;
  final Expr condition;
  final bool enabled;

  /// Null = global (all watched channels), otherwise only this channel.
  final int? scopeChatId;
  final RulePriority priority;
  final bool readAloud;
  final Schedule? schedule;

  /// Parses a `rules` row. Throws [FormatException] on corrupt JSON.
  factory RuleSpec.fromRow(Rule row) => RuleSpec(
    id: row.id,
    name: row.name,
    enabled: row.enabled,
    scopeChatId: row.scopeKind == 'channel' ? row.scopeChatId : null,
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

/// A rule match as clients receive it.
final class MatchEvent {
  const MatchEvent({
    required this.post,
    required this.priority,
    required this.readAloud,
    required this.ruleNames,
  });
  final Post post;
  final RulePriority priority;
  final bool readAloud;
  final List<String> ruleNames;

  factory MatchEvent.fromMatch(RuleMatch m) => MatchEvent(
    post: m.post,
    priority: m.priority,
    readAloud: m.readAloud,
    ruleNames: [for (final r in m.rules) r.name],
  );

  static MatchEvent decode(Map<Object?, Object?> m) => MatchEvent(
    post: decodePost(m['post'] as Map<Object?, Object?>),
    priority: RulePriority.values.byName(m['priority'] as String),
    readAloud: m['readAloud'] as bool,
    ruleNames: (m['rules'] as List).cast<String>(),
  );
}

/// Evaluates rules against new posts (ARCHITECTURE.md section 6.2).
///
/// - Only [PostAdded] is evaluated; edits are ignored.
/// - [PostsDeleted] is forwarded on [cancellations] so a pending notification can be dropped.
/// - Only chats in [watched] (the union of all feed sources) are considered.
final class RuleEngine {
  RuleEngine({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final _evaluator = RuleEvaluator();
  final _matches = StreamController<RuleMatch>.broadcast();
  final _cancels = StreamController<PostsDeleted>.broadcast();
  List<RuleSpec> _rules = const [];
  Set<int> _watched = const {};

  Stream<RuleMatch> get matches => _matches.stream;
  Stream<PostsDeleted> get cancellations => _cancels.stream;
  List<RuleSpec> get rules => _rules;
  Set<int> get watched => _watched;

  /// Replaces the rule set and the watched channels (called whenever the database changes).
  void update({List<RuleSpec>? rules, Set<int>? watched}) {
    if (rules != null) _rules = List.unmodifiable(rules);
    if (watched != null) _watched = Set.unmodifiable(watched);
  }

  /// Rules that apply to [chatId] right now.
  List<RuleSpec> candidates(int chatId, {DateTime? now}) {
    final t = now ?? _clock();
    return [
      for (final r in _rules)
        if (r.enabled &&
            (r.scopeChatId == null || r.scopeChatId == chatId) &&
            (r.schedule == null || r.schedule!.isActive(t)))
          r,
    ];
  }

  /// Evaluates one post; returns the match or null. Pure apart from the clock.
  RuleMatch? evaluate(Post post, {DateTime? now}) {
    if (!_watched.contains(post.chatId)) return null;
    final text = post.text;
    if (text.isEmpty) return null;
    final hits = [
      for (final r in candidates(post.chatId, now: now))
        if (_evaluator.matches(r.condition, text)) r,
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
