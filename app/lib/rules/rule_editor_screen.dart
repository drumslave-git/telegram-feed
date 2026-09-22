import 'dart:convert';

import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:rules/rules.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../notifications/notification_policy.dart';
import '../ai/semantic_gate.dart';
import '../home/channel_list.dart' show ChannelAvatar;
import 'rule_builder_model.dart';
import '../widgets/destructive_button.dart';

/// Create or edit one rule: visual builder or text form, its feed and channels, priority,
/// read-aloud, schedule, and a dry run against recent posts (SPEC section 4).
class RuleEditorScreen extends StatefulWidget {
  const RuleEditorScreen({
    super.key,
    required this.db,
    required this.gateway,
    this.rule,
    this.feedId,
    this.policyGranted = NotificationPolicy.isGrantedFn,
    this.openPolicySettings = NotificationPolicy.openSettings,
    this.semanticCheck,
  });
  final AppDatabase db;
  final TelegramGateway gateway;
  final Rule? rule;

  /// The feed a new rule goes into; the first feed when null.
  final int? feedId;

  /// Injectable for tests: whether DND bypass is allowed (urgent rules).
  final Future<bool> Function() policyGranted;
  final Future<void> Function() openPolicySettings;

  /// Asks the AI endpoint which descriptions a post matches (dry run of AI rules).
  final SemanticCheck? semanticCheck;

  @override
  State<RuleEditorScreen> createState() => _RuleEditorScreenState();
}

class _RuleEditorScreenState extends State<RuleEditorScreen> {
  late final _name = TextEditingController(text: widget.rule?.name ?? '');
  late final _text = TextEditingController();
  late final _prompt = TextEditingController(
    text: widget.rule?.semanticPrompt ?? '',
  );
  bool _aiConfigured = true;

  /// The rule's feed; null only while there is no feed at all.
  int? _feedId;
  List<Feed> _feeds = const [];

  /// One channel of the feed, or null for all of them.
  int? _scopeChatId;
  String _priority = 'normal';
  bool _readAloud = false;
  bool _enabled = true;
  bool _textMode = false;
  BuilderModel _model = BuilderModel.empty;
  String? _textError;
  bool _scheduled = false;
  Set<int> _weekdays = {...Schedule.allWeek};
  int _from = 9 * 60;
  int _to = 18 * 60;
  bool _saving = false;

  /// The channels of the rule's feed.
  List<WatchedChannel> _channels = const [];

  /// Channel photos for the scope list; the database only keeps titles.
  Map<int, FileRef?> _photos = const {};

  @override
  void initState() {
    super.initState();
    final r = widget.rule;
    _feedId = r?.feedId ?? widget.feedId;
    if (r != null) {
      _scopeChatId = r.scopeChatId;
      _priority = r.priority;
      _readAloud = r.readAloud;
      _enabled = r.enabled;
      try {
        final spec = RuleSpec.fromRow(r);
        if (_isMatchAll(spec.condition)) {
          // Rule without keywords (every post, or every post sent to the AI): both
          // editors start empty.
        } else {
          final m = BuilderModel.fromExpr(spec.condition);
          if (m != null) {
            _model = m;
          } else {
            _textMode = true;
          }
          _text.text = RuleParser.format(spec.condition);
        }
        final s = spec.schedule;
        if (s != null) {
          _scheduled = true;
          _weekdays = {...s.weekdays};
          _from = s.from;
          _to = s.to;
        }
      } on FormatException {
        _textMode = true;
        _text.text = r.conditionJson;
        _textError = 'Stored condition could not be parsed; rewrite it.';
      }
    }
    widget.db.allFeeds().then((feeds) {
      if (!mounted) return;
      setState(() {
        _feeds = feeds;
        if (_feedId == null || !feeds.any((f) => f.id == _feedId)) {
          _feedId = feeds.firstOrNull?.id;
          _scopeChatId = null;
        }
      });
      _loadChannels();
    });
    widget.gateway.myChannels().then((channels) {
      if (!mounted) return;
      setState(() => _photos = {for (final c in channels) c.chatId: c.photo});
    }, onError: (Object _) {}); // initials stay
    widget.db.setting(AiKeys.baseUrl).then((url) {
      if (mounted) setState(() => _aiConfigured = (url ?? '').isNotEmpty);
    });
  }

  static bool _isMatchAll(Expr e) => e is And && e.items.isEmpty;

  /// The channels of the rule's feed, for the scope list and the dry run.
  Future<void> _loadChannels() async {
    final feed = _feedId;
    if (feed == null) return;
    final channels = await widget.db.watchSourceChannels(feed).first;
    if (mounted && feed == _feedId) setState(() => _channels = channels);
  }

  void _setFeed(int? feed) {
    if (feed == null || feed == _feedId) return;
    setState(() {
      _feedId = feed;
      _scopeChatId = null;
      _channels = const [];
    });
    _loadChannels();
  }

  /// What the rule's feed shows: the dry run tests only those posts, like the engine.
  FeedFilter get _feedFilter => FeedFilter.decode(
    _feeds.where((f) => f.id == _feedId).firstOrNull?.filterJson,
  );

  /// How many posts a dry run of an AI rule sends to the model.
  static const _aiDryRunPosts = 8;

  /// AI rule: the description is filled in.
  bool get _isSemantic => _prompt.text.trim().isNotEmpty;

  /// No keyword typed in the active editor.
  bool get _keywordsBlank => _textMode
      ? _text.text.trim().isEmpty
      : _model.groups.every((g) => g.every((t) => t.text.trim().isEmpty));

  @override
  void dispose() {
    _name.dispose();
    _text.dispose();
    _prompt.dispose();
    super.dispose();
  }

  /// The condition from whichever editor is active, or null with an error shown.
  ///
  /// No keywords at all is a rule that matches every post in its scope: on an AI rule they
  /// all go to the model, on a plain one they all notify. `And([])` is that condition.
  Expr? _condition() {
    if (_keywordsBlank) return const And([]);
    if (_textMode) {
      try {
        final e = RuleParser.parse(_text.text);
        setState(() => _textError = null);
        return e;
      } on FormatException catch (e) {
        setState(() => _textError = e.message);
        return null;
      }
    }
    if (!_model.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Every term needs a word or phrase.')),
      );
      return null;
    }
    return _model.toExpr();
  }

  void _switchMode(bool toText) {
    if (toText) {
      if (_model.isValid) _text.text = RuleParser.format(_model.toExpr());
      setState(() => _textMode = true);
      return;
    }
    try {
      final e = RuleParser.parse(_text.text);
      final m = BuilderModel.fromExpr(e);
      if (m == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Too nested for the builder; keep editing as text.'),
          ),
        );
        return;
      }
      setState(() {
        _model = m;
        _textMode = false;
        _textError = null;
      });
    } on FormatException catch (e) {
      setState(() => _textError = e.message);
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Give the rule a name.')));
      return;
    }
    final feedId = _feedId;
    if (feedId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A rule belongs to a feed: create one first.'),
        ),
      );
      return;
    }
    final cond = _condition();
    if (cond == null) return;
    if (_priority == 'urgent' && !await widget.policyGranted()) {
      if (!mounted) return;
      final open = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Show urgent posts in Do Not Disturb?'),
          content: const Text(
            'Urgent rules can break through Do Not Disturb, but Android must allow this app to do so. Open the setting now? The rule is saved either way.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Open settings'),
            ),
          ],
        ),
      );
      if (open ?? false) await widget.openPolicySettings();
    }
    setState(() => _saving = true);
    final schedule = _scheduled
        ? jsonEncode(
            Schedule(weekdays: _weekdays, from: _from, to: _to).toJson(),
          )
        : null;
    final companion = RulesCompanion(
      name: Value(name),
      enabled: Value(_enabled),
      feedId: Value(feedId),
      scopeChatId: Value(_scopeChatId),
      conditionJson: Value(jsonEncode(cond.toJson())),
      priority: Value(_priority),
      readAloud: Value(_readAloud),
      scheduleJson: Value(schedule),
      semanticPrompt: Value(_isSemantic ? _prompt.text.trim() : null),
    );
    final r = widget.rule;
    if (r == null) {
      await widget.db.insertRule(
        RulesCompanion.insert(
          name: name,
          enabled: Value(_enabled),
          feedId: feedId,
          scopeChatId: Value(_scopeChatId),
          conditionJson: jsonEncode(cond.toJson()),
          priority: _priority,
          readAloud: Value(_readAloud),
          scheduleJson: Value(schedule),
          semanticPrompt: Value(_isSemantic ? _prompt.text.trim() : null),
          createdAt: DateTime.now(),
        ),
      );
    } else {
      await widget.db.updateRule(r.copyWithCompanion(companion));
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final r = widget.rule;
    if (r == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${r.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          DestructiveButton(
            onPressed: () => Navigator.pop(context, true),
            label: 'Delete',
          ),
        ],
      ),
    );
    if (ok ?? false) {
      await widget.db.deleteRule(r.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  /// Dry run: evaluate the condition against the latest posts of the rule's channels that
  /// its feed shows.
  Future<void> _testOnRecent() async {
    final cond = _condition();
    if (cond == null) return;
    final filter = _feedFilter;
    final chats = _scopeChatId != null
        ? [_scopeChatId!]
        : _channels.map((c) => c.chatId).take(10).toList();
    final titles = {for (final c in _channels) c.chatId: c.title};
    final evaluator = RuleEvaluator();
    final matchesEverything = _isMatchAll(cond) && !_isSemantic;
    final hits = <Post>[];
    var scanned = 0;
    for (final chat in chats) {
      try {
        final posts = [
          for (final p in await widget.gateway.history(chat, limit: 20))
            if (filter.mayShow(p)) p,
        ];
        scanned += posts.length;
        hits.addAll(
          posts.where(
            // Like the engine: a post without text passes only a rule with no condition.
            (p) => p.text.isEmpty
                ? matchesEverything
                : evaluator.matches(cond, p.text),
          ),
        );
      } on TelegramException {
        // skip channels that fail; the dry run is best effort
      }
    }
    // AI rule: the newest few posts that pass the keywords go to the model, like live.
    String? headline;
    final check = widget.semanticCheck;
    if (_isSemantic && check != null) {
      hits.sort((a, b) => b.date.compareTo(a.date));
      final sample = hits.take(_aiDryRunPosts).toList();
      final confirmed = <Post>[];
      try {
        for (final p in sample) {
          if ((await check(p.text, [_prompt.text.trim()])).isNotEmpty) {
            confirmed.add(p);
          }
        }
        headline = confirmed.isEmpty
            ? 'The AI matched none of the ${sample.length} newest posts it checked '
                  '(${hits.length} of the last $scanned passed the keywords).'
            : 'The AI matched ${confirmed.length} of the ${sample.length} newest posts it checked:';
      } on SemanticException catch (e) {
        headline = 'The AI check failed: ${e.message}';
        confirmed.clear();
      }
      hits
        ..clear()
        ..addAll(confirmed);
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            headline ??
                (hits.isEmpty
                    ? 'No match in the last $scanned posts.'
                    : '${hits.length} of the last $scanned posts match:'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final p in hits.take(30))
            ListTile(
              title: Text(titles[p.chatId] ?? '${p.chatId}'),
              subtitle: Text(
                // A post without text is one a rule with no condition matches too.
                postLabel(p),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickTime(bool from) async {
    final initial = from ? _from : _to;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial ~/ 60, minute: initial % 60),
    );
    if (t == null) return;
    setState(() {
      if (from) {
        _from = t.hour * 60 + t.minute;
      } else {
        _to = t.hour * 60 + t.minute;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.rule == null ? 'New rule' : 'Edit rule'),
        actions: [
          if (widget.rule != null)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            key: ValueKey('feed-${_feeds.length}-$_feedId'),
            initialValue: _feedId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Feed',
              helperText: _feeds.isEmpty
                  ? 'A rule belongs to a feed: create one first.'
                  : null,
            ),
            items: [
              for (final f in _feeds)
                DropdownMenuItem<int>(value: f.id, child: Text(f.name)),
            ],
            onChanged: _setFeed,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int?>(
            key: ValueKey('channels-$_feedId-${_channels.length}'),
            initialValue: _channels.any((c) => c.chatId == _scopeChatId)
                ? _scopeChatId
                : null,
            // The items are rows with an avatar; they need the width of the field.
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Channels'),
            items: [
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('Every channel of the feed'),
              ),
              for (final c in _channels)
                DropdownMenuItem<int?>(
                  value: c.chatId,
                  child: Row(
                    children: [
                      ChannelAvatar(
                        photo: _photos[c.chatId],
                        title: c.title,
                        gateway: widget.gateway,
                        radius: 12,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(c.title, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
            ],
            onChanged: (v) => setState(() => _scopeChatId = v),
          ),
          const SizedBox(height: 16),
          Text('Meaning (AI, optional)', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _prompt,
            minLines: 1,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Central bank interest rate decisions',
              helperText: 'Describe what the post should be about. A model you configure in Settings decides; leave empty for a plain keyword rule.',
              helperMaxLines: 3,
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (_isSemantic && !_aiConfigured)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'The AI endpoint is not set up yet (Settings, AI rules). Until then this rule is skipped.',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          if (_isSemantic && _keywordsBlank)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'No keywords below: every new post from this rule\'s channels is sent to your AI endpoint. Add keywords to send only posts that contain them.',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                _isSemantic ? 'Keywords (pre-filter)' : 'Condition',
                style: theme.textTheme.titleMedium,
              ),
              const Spacer(),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Builder')),
                  ButtonSegment(value: true, label: Text('Text')),
                ],
                selected: {_textMode},
                onSelectionChanged: (s) => _switchMode(s.first),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!_isSemantic && _keywordsBlank)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'No condition: every new post from this rule\'s channels notifies. Add terms to notify only about some of them.',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          if (_textMode)
            TextField(
              controller: _text,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: '("bitcoin" OR btc) AND NOT airdrop',
                helperText: 'Words or "phrases"; AND, OR, NOT; ~word = part of a word; =Word = exact case',
                helperMaxLines: 3,
                errorText: _textError,
              ),
              onChanged: (_) => setState(() => _textError = null),
            )
          else
            _Builder(
              model: _model,
              onChanged: (m) => setState(() => _model = m),
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _testOnRecent,
              icon: const Icon(Icons.science_outlined),
              label: const Text('Test on recent posts'),
            ),
          ),
          const SizedBox(height: 16),
          Text('Notification', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'silent',
                label: Text('Silent'),
                icon: Icon(Icons.notifications_off_outlined),
              ),
              ButtonSegment(
                value: 'normal',
                label: Text('Normal'),
                icon: Icon(Icons.notifications_outlined),
              ),
              ButtonSegment(
                value: 'urgent',
                label: Text('Urgent'),
                icon: Icon(Icons.priority_high),
              ),
            ],
            selected: {_priority},
            onSelectionChanged: (s) => setState(() => _priority = s.first),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Read the post aloud'),
            value: _readAloud,
            onChanged: (v) => setState(() => _readAloud = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enabled'),
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Only at certain times'),
            value: _scheduled,
            onChanged: (v) => setState(() => _scheduled = v),
          ),
          if (_scheduled) ...[
            Wrap(
              spacing: 6,
              children: [
                for (var d = 1; d <= 7; d++)
                  FilterChip(
                    label: Text(
                      const [
                        'Mon',
                        'Tue',
                        'Wed',
                        'Thu',
                        'Fri',
                        'Sat',
                        'Sun',
                      ][d - 1],
                    ),
                    selected: _weekdays.contains(d),
                    onSelected: (on) => setState(
                      () => on ? _weekdays.add(d) : _weekdays.remove(d),
                    ),
                  ),
              ],
            ),
            Row(
              children: [
                TextButton(
                  onPressed: () => _pickTime(true),
                  child: Text('From ${Schedule.formatTime(_from)}'),
                ),
                TextButton(
                  onPressed: () => _pickTime(false),
                  child: Text('To ${Schedule.formatTime(_to)}'),
                ),
                if (_to < _from)
                  Text('(next day)', style: theme.textTheme.bodySmall),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Groups joined by OR; terms inside a group joined by AND.
class _Builder extends StatelessWidget {
  const _Builder({required this.model, required this.onChanged});
  final BuilderModel model;
  final ValueChanged<BuilderModel> onChanged;

  void _update(int g, int t, BuilderTerm term) {
    final groups = [
      for (final x in model.groups) [...x],
    ];
    groups[g][t] = term;
    onChanged(BuilderModel(groups));
  }

  void _remove(int g, int t) {
    final groups = [
      for (final x in model.groups) [...x],
    ];
    groups[g].removeAt(t);
    if (groups[g].isEmpty) groups.removeAt(g);
    if (groups.isEmpty) groups.add([const BuilderTerm(text: '')]);
    onChanged(BuilderModel(groups));
  }

  void _addTerm(int g) {
    final groups = [
      for (final x in model.groups) [...x],
    ];
    groups[g].add(const BuilderTerm(text: ''));
    onChanged(BuilderModel(groups));
  }

  void _addGroup() => onChanged(
    BuilderModel([
      ...model.groups,
      [const BuilderTerm(text: '')],
    ]),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var g = 0; g < model.groups.length; g++) ...[
          if (g > 0)
            const Center(
              child: Padding(padding: EdgeInsets.all(4), child: Text('OR')),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  for (var t = 0; t < model.groups[g].length; t++) ...[
                    if (t > 0) const Text('AND'),
                    _TermRow(
                      term: model.groups[g][t],
                      onChanged: (term) => _update(g, t, term),
                      onRemove: () => _remove(g, t),
                    ),
                  ],
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _addTerm(g),
                      icon: const Icon(Icons.add),
                      label: const Text('AND another word'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        TextButton.icon(
          onPressed: _addGroup,
          icon: const Icon(Icons.add),
          label: const Text('OR alternative'),
        ),
      ],
    );
  }
}

class _TermRow extends StatefulWidget {
  const _TermRow({
    required this.term,
    required this.onChanged,
    required this.onRemove,
  });
  final BuilderTerm term;
  final ValueChanged<BuilderTerm> onChanged;
  final VoidCallback onRemove;

  @override
  State<_TermRow> createState() => _TermRowState();
}

class _TermRowState extends State<_TermRow> {
  late final _ctl = TextEditingController(text: widget.term.text);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.term;
    return Row(
      children: [
        IconButton(
          tooltip: t.negated ? 'Must NOT contain' : 'Must contain',
          isSelected: t.negated,
          icon: const Icon(Icons.block),
          onPressed: () => widget.onChanged(t.copyWith(negated: !t.negated)),
        ),
        Expanded(
          child: TextField(
            controller: _ctl,
            decoration: const InputDecoration(
              hintText: 'word or phrase',
              isDense: true,
            ),
            onChanged: (v) => widget.onChanged(t.copyWith(text: v)),
          ),
        ),
        IconButton(
          tooltip: t.wholeWord ? 'Whole word' : 'Part of a word',
          isSelected: !t.wholeWord,
          icon: const Icon(Icons.text_fields),
          onPressed: () =>
              widget.onChanged(t.copyWith(wholeWord: !t.wholeWord)),
        ),
        IconButton(
          tooltip: t.caseSensitive ? 'Exact case' : 'Any case',
          isSelected: t.caseSensitive,
          icon: const Icon(Icons.abc),
          onPressed: () =>
              widget.onChanged(t.copyWith(caseSensitive: !t.caseSensitive)),
        ),
        IconButton(
          tooltip: 'Remove',
          icon: const Icon(Icons.close),
          onPressed: widget.onRemove,
        ),
      ],
    );
  }
}
