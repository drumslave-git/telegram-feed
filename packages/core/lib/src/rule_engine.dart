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
/// - An album is one post: its parts arrive as messages of their own, so they are held for
///   [albumWait] after the last one and evaluated together.
/// - [PostsDeleted] is forwarded on [cancellations] so a pending notification can be dropped.
/// - Every post is evaluated once. The engine keeps a mark per channel, the newest post it
///   has looked at; [catchUp] evaluates what came after it while nothing ran, and a post
///   that both a live update and a catch-up bring is looked at only the first time.
final class RuleEngine {
  RuleEngine({
    DateTime Function()? clock,
    this.albumWait = const Duration(seconds: 1),
  }) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  /// How long after the last part of an album the album is taken as complete.
  final Duration albumWait;

  /// The parts of the albums still arriving, by chat and album, with the timer that ends
  /// the wait.
  final _albums = <(int, int), ({List<Post> parts, Timer timer})>{};
  final _evaluator = RuleEvaluator();
  final _matches = StreamController<RuleMatch>.broadcast();
  final _cancels = StreamController<PostsDeleted>.broadcast();
  List<RuleSpec> _rules = const [];
  Map<int, RuleFeed> _feeds = const {};
  Set<int> _watched = const {};

  /// While true the engine looks at posts without matching them: the pause. What comes
  /// during the pause is looked at all the same, so no catch-up brings it up afterwards.
  bool quiet = false;

  /// Posts looked at in this run, by chat and message, oldest first.
  final _lookedAt = <(int, int)>{};
  static const _lookedAtKept = 4096;

  /// The newest post of each channel that the rules have looked at, every post before it
  /// included. The host keeps them between runs ([restoreMarks], [marksChanged]).
  final _marks = <int, int>{};

  /// Channels caught up in this run. A live post moves on only their marks: the mark of
  /// a channel not caught up yet still says where its catch-up starts.
  final _caughtUp = <int>{};
  final _marksChanged = StreamController<void>.broadcast();

  Map<int, int> get marks => Map.unmodifiable(_marks);

  /// Fires whenever a mark moves.
  Stream<void> get marksChanged => _marksChanged.stream;

  /// The marks of the run before; no channel is caught up yet.
  void restoreMarks(Map<int, int> marks) {
    _marks
      ..clear()
      ..addAll(marks);
    _caughtUp.clear();
    _lookedAt.clear();
  }

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
    // A service message (a pin, a new channel photo) is not a post.
    if (post.media is ServiceNote) return null;
    final text = post.text;
    return _matchOf(post, [
      for (final r in candidates(post.chatId, now: now))
        if (_shows(r, post) &&
            _mayMatch(r, text) &&
            _evaluator.matches(r.condition, text))
          r,
    ]);
  }

  /// Evaluates an album as the one post it is: its captions together are its words, and a
  /// rule's feed shows it when it shows any of its parts. The match names the part with
  /// the caption, or the first part of an album without one.
  RuleMatch? evaluateAlbum(List<Post> parts, {DateTime? now}) {
    if (parts.isEmpty || !_watched.contains(parts.first.chatId)) return null;
    final ordered = [...parts]
      ..sort((a, b) => a.messageId.compareTo(b.messageId));
    final text = [
      for (final p in ordered)
        if (p.text.isNotEmpty) p.text,
    ].join('\n');
    final post = ordered.firstWhere(
      (p) => p.text.isNotEmpty,
      orElse: () => ordered.first,
    );
    return _matchOf(post, [
      for (final r in candidates(post.chatId, now: now))
        if ((_feeds[r.feedId]?.filter.shownParts(ordered).isNotEmpty ??
                false) &&
            _mayMatch(r, text) &&
            _evaluator.matches(r.condition, text))
          r,
    ]);
  }

  RuleMatch? _matchOf(Post post, List<RuleSpec> hits) {
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
            if (!_watched.contains(post.chatId) || !_lookAtLive(post)) return;
            if (quiet) return;
            if (post.albumId != 0) {
              _holdAlbumPart(post);
            } else if (evaluate(post) case final m?) {
              _matches.add(m);
            }
          case PostEdited():
            break; // edits never notify (SPEC)
          case PostsDeleted():
            if (_watched.contains(e.chatId)) _cancels.add(e);
        }
      });

  /// False for a post looked at before: in this run, or at or below its channel's mark.
  bool _lookAtLive(Post post) {
    final mark = _marks[post.chatId];
    if (mark != null && post.messageId <= mark) return false;
    if (!_lookAt(post)) return false;
    if (mark == null || _caughtUp.contains(post.chatId)) {
      _marks[post.chatId] = post.messageId;
      _marksChanged.add(null);
    }
    return true;
  }

  bool _lookAt(Post post) {
    if (!_lookedAt.add((post.chatId, post.messageId))) return false;
    if (_lookedAt.length > _lookedAtKept) _lookedAt.remove(_lookedAt.first);
    return true;
  }

  /// Evaluates what came to [chatId] after its mark while nothing ran. [posts] are its
  /// newest posts, in any order; those at or below the mark, those read already (up to
  /// [lastReadMessageId], here or in the official app) and those this run has looked at
  /// are left out. The rest are evaluated oldest first, an album as one post, each
  /// against the rules as they stood when it came. A channel without a mark gets one at
  /// [lastMessageId] and nothing of it is evaluated: the rules start from there.
  void catchUp(
    int chatId,
    List<Post> posts, {
    required int lastReadMessageId,
    required int lastMessageId,
  }) {
    final mark = _marks[chatId];
    var newest = mark ?? lastMessageId;
    if (mark != null) {
      final fresh = [
        for (final p in posts)
          if (p.chatId == chatId &&
              p.messageId > mark &&
              p.messageId > lastReadMessageId &&
              _lookAt(p))
            p,
      ]..sort((a, b) => a.messageId.compareTo(b.messageId));
      if (!quiet) _evaluateInOrder(fresh);
      for (final p in fresh) {
        if (p.messageId > newest) newest = p.messageId;
      }
    }
    if (lastMessageId > newest) newest = lastMessageId;
    _caughtUp.add(chatId);
    if (_marks[chatId] != newest) {
      _marks[chatId] = newest;
      _marksChanged.add(null);
    }
  }

  /// Evaluates [posts], oldest first, the parts of an album together.
  void _evaluateInOrder(List<Post> posts) {
    for (var i = 0; i < posts.length;) {
      final first = posts[i];
      final when = DateTime.fromMillisecondsSinceEpoch(first.date * 1000);
      if (first.albumId == 0) {
        i++;
        if (evaluate(first, now: when) case final m?) _matches.add(m);
        continue;
      }
      final parts = [
        for (; i < posts.length && posts[i].albumId == first.albumId; i++)
          posts[i],
      ];
      if (evaluateAlbum(parts, now: when) case final m?) _matches.add(m);
    }
  }

  /// Keeps a part of an album until no further part has come for [albumWait], then
  /// evaluates the album once.
  void _holdAlbumPart(Post post) {
    final key = (post.chatId, post.albumId);
    final held = _albums[key];
    held?.timer.cancel();
    _albums[key] = (
      parts: [...?held?.parts, post],
      timer: Timer(albumWait, () {
        final album = _albums.remove(key);
        if (album == null || _matches.isClosed) return;
        final m = evaluateAlbum(album.parts);
        if (m != null) _matches.add(m);
      }),
    );
  }

  Future<void> close() async {
    for (final album in _albums.values) {
      album.timer.cancel();
    }
    _albums.clear();
    await _matches.close();
    await _cancels.close();
    await _marksChanged.close();
  }
}
