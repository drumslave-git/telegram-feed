import 'dart:async';
import 'dart:convert';

import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:rules/rules.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../notifications/notification_policy.dart';
import '../ai/semantic_gate.dart';
import '../feeds/post_card.dart' show formatDay;
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

  /// "Also ask the AI" is on: the description below it decides with the keywords.
  bool _useAi = false;

  /// A dry run is in progress.
  bool _testing = false;

  /// What the form held when it opened, to ask before changes are thrown away.
  String? _initial;

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
  String? _nameError;
  String? _feedError;
  String? _scheduleError;
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
    _useAi = (r?.semanticPrompt ?? '').trim().isNotEmpty;
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
    _initial = _snapshot();
    widget.db.allFeeds().then((feeds) {
      if (!mounted) return;
      final untouched = _snapshot() == _initial;
      setState(() {
        _feeds = feeds;
        if (_feedId == null || !feeds.any((f) => f.id == _feedId)) {
          _feedId = feeds.firstOrNull?.id;
          _scopeChatId = null;
        }
      });
      // The feed picked for a new rule is where the form starts, not an edit.
      if (untouched) _initial = _snapshot();
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

  /// AI rule: the AI is asked and the description is filled in.
  bool get _isSemantic => _useAi && _prompt.text.trim().isNotEmpty;

  /// Everything the form would save, as one string: a change makes it differ.
  String _snapshot() => [
    _name.text.trim(),
    _feedId,
    _scopeChatId,
    _priority,
    _readAloud,
    _enabled,
    _useAi ? _prompt.text.trim() : '',
    _textMode ? _text.text.trim() : _formatModel(_model),
    _scheduled ? '${_weekdays.toList()..sort()} $_from-$_to' : '',
  ].join('|');

  bool get _dirty => _initial != null && _snapshot() != _initial;

  /// The builder's terms as the text form writes them, leaving out rows without words.
  static String _formatModel(BuilderModel m) {
    final filled = m.withoutBlankTerms();
    return filled == null ? '' : RuleParser.format(filled.toExpr());
  }

  /// A parser error in words, without the parser's prefix and position; the cursor shows
  /// the position instead.
  static String _syntaxMessage(FormatException e) {
    var m = e.message.replaceFirst('rule syntax: ', '');
    m = m.replaceFirst(RegExp(r' at \d+$'), '');
    if (m.isEmpty) return 'This condition cannot be read.';
    return '${m[0].toUpperCase()}${m.substring(1)} where the cursor is.';
  }

  void _showSyntaxError(FormatException e) {
    final at = e.offset;
    if (at != null && at >= 0 && at <= _text.text.length) {
      _text.selection = TextSelection.collapsed(offset: at);
    }
    setState(() => _textError = _syntaxMessage(e));
  }

  /// Leaving with changes: asks whether to throw them away.
  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('The changes to this rule are not saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          DestructiveButton(
            onPressed: () => Navigator.pop(context, true),
            label: 'Discard',
          ),
        ],
      ),
    );
    if ((leave ?? false) && mounted) Navigator.of(context).pop();
  }

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
        _showSyntaxError(e);
        return null;
      }
    }
    // Rows without a word are dropped, exactly as the switch to the text form drops
    // them: the editor used to refuse to save instead.
    final filled = _model.withoutBlankTerms();
    return filled == null ? const And([]) : filled.toExpr();
  }

  void _switchMode(bool toText) {
    if (toText == _textMode) return;
    if (toText) {
      // The words typed so far go along; rows still without a word are left behind.
      _text.text = _formatModel(_model);
      setState(() {
        _textMode = true;
        _textError = null;
      });
      return;
    }
    if (_text.text.trim().isEmpty) {
      setState(() {
        _model = BuilderModel.empty;
        _textMode = false;
        _textError = null;
      });
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
      _showSyntaxError(e);
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final feedId = _feedId;
    // On the fields themselves: a snackbar can stand behind the keyboard, and the field
    // it is about is at the top of a scrolled form.
    setState(() {
      _nameError = name.isEmpty ? 'Give the rule a name.' : null;
      _feedError = feedId == null
          ? 'A rule belongs to a feed: create one first.'
          : null;
      _scheduleError = _scheduled && _weekdays.isEmpty
          ? 'Pick at least one day, or the rule never notifies.'
          : null;
    });
    if (_nameError != null ||
        _feedError != null ||
        _scheduleError != null ||
        feedId == null) {
      return;
    }
    final cond = _condition();
    if (cond == null) return;
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

  /// Urgent rules may break through Do Not Disturb only where Android allows it; asked
  /// the moment "Urgent" is picked, so the answer is about the choice just made.
  Future<void> _askForDoNotDisturb() async {
    if (await widget.policyGranted() || !mounted) return;
    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Show urgent posts in Do Not Disturb?'),
        content: const Text(
          'Urgent rules can break through Do Not Disturb, but Android must allow this '
          'app to do so. Open the setting now? The rule works either way.',
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
    setState(() => _testing = true);
    try {
      await _runTest(cond);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  /// How many channels of the feed a dry run reads.
  static const _dryRunChannels = 10;

  Future<void> _runTest(Expr cond) async {
    final filter = _feedFilter;
    final all = _scopeChatId != null
        ? [_scopeChatId!]
        : _channels.map((c) => c.chatId).toList();
    final chats = all.take(_dryRunChannels).toList();
    var failed = 0;
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
        // The dry run is best effort; the sheet says how many channels it could not read.
        failed++;
      }
    }
    final read = chats.length - failed;
    final scope = [
      'from $read channel${read == 1 ? '' : 's'}',
      if (all.length > chats.length)
        'of ${all.length} (the first $_dryRunChannels are checked)',
      if (failed > 0) '($failed could not be read)',
    ].join(' ');
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
    // Done: the results take over from the spinner.
    setState(() => _testing = false);
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
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              'Checked the latest posts $scope.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          for (final p in hits.take(30))
            ListTile(
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      titles[p.chatId] ?? '${p.chatId}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    formatDay(
                      DateTime.fromMillisecondsSinceEpoch(p.date * 1000),
                    ),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
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

  /// The whole syntax of the text form, which does not fit under the field.
  void _showSyntaxHelp() => unawaited(
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(
              'Writing a condition',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final (example, meaning) in const [
              ('bitcoin', 'the word, wherever it stands'),
              ('"interest rate"', 'those words next to each other'),
              ('bitcoin AND etf', 'both have to be there'),
              ('bitcoin OR btc', 'either one is enough'),
              ('NOT airdrop', 'the post must not have it'),
              ('(a OR b) AND c', 'brackets group the parts'),
              ('~rate', 'also inside longer words, like "rates"'),
              ('=Fed', 'exactly that spelling, capitals included'),
            ])
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(example),
                subtitle: Text(meaning),
              ),
          ],
        ),
      ),
    ),
  );

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
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_confirmLeave());
      },
      child: Scaffold(
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
              decoration: InputDecoration(
                labelText: 'Name',
                errorText: _nameError,
              ),
              textInputAction: TextInputAction.next,
              // The back guard compares the form with how it opened.
              onChanged: (_) => setState(() => _nameError = null),
            ),
            // At the top, where the state of the rule belongs, not under everything.
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enabled'),
              subtitle: const Text('Off keeps the rule but stops it notifying'),
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
            const SizedBox(height: 4),
            DropdownButtonFormField<int>(
              key: ValueKey('feed-${_feeds.length}-$_feedId'),
              initialValue: _feedId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Feed',
                errorText: _feedError,
                helperText: _feeds.isEmpty
                    ? 'A rule belongs to a feed: create one first.'
                    : null,
              ),
              items: [
                for (final f in _feeds)
                  DropdownMenuItem<int>(value: f.id, child: Text(f.name)),
              ],
              onChanged: (v) {
                setState(() => _feedError = null);
                _setFeed(v);
              },
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
            Row(
              children: [
                Text('Condition', style: theme.textTheme.titleMedium),
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
            if (_keywordsBlank || _isSemantic)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  !_isSemantic
                      ? 'No condition: every new post from this rule\'s channels notifies. Add terms to notify only about some of them.'
                      : _keywordsBlank
                      ? 'No keywords: every new post from this rule\'s channels goes to the AI. Add terms to send only posts that contain them.'
                      : 'The AI checks only the posts that pass these keywords.',
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
                  helperText: 'Words or "phrases" joined by AND, OR, NOT, with brackets.',
                  helperMaxLines: 2,
                  errorText: _textError,
                  errorMaxLines: 3,
                  suffixIcon: IconButton(
                    tooltip: 'Syntax',
                    icon: const Icon(Icons.help_outline),
                    onPressed: _showSyntaxHelp,
                  ),
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
                onPressed: _testing ? null : _testOnRecent,
                icon: _testing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.science_outlined),
                label: Text(
                  _testing ? 'Testing\u2026' : 'Test on recent posts',
                ),
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
              onSelectionChanged: (s) {
                setState(() => _priority = s.first);
                // Asked here, where the choice is made, instead of at save time.
                if (s.first == 'urgent') unawaited(_askForDoNotDisturb());
              },
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: Text(switch (_priority) {
                'silent' => 'In the tray only, with no sound and no vibration.',
                'urgent' =>
                  'Breaks through Do Not Disturb where Android allows it.',
                _ => 'The sound and vibration set in Notifications and sounds.',
              }, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Read the post aloud'),
              value: _readAloud,
              onChanged: (v) => setState(() => _readAloud = v),
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
                      onSelected: (on) => setState(() {
                        on ? _weekdays.add(d) : _weekdays.remove(d);
                        _scheduleError = null;
                      }),
                    ),
                ],
              ),
              if (_scheduleError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _scheduleError!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
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
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Also ask the AI'),
              subtitle: const Text(
                'A model you set up in Settings decides whether a post is about what you describe.',
              ),
              value: _useAi,
              onChanged: (v) => setState(() => _useAi = v),
            ),
            if (_useAi) ...[
              TextField(
                controller: _prompt,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'What the post should be about',
                  hintText: 'Central bank interest rate decisions',
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (!_aiConfigured)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'The AI endpoint is not set up yet (Settings, AI rules). Until then this rule is skipped.',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
            ],
          ],
        ),
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
    // Nothing left is a rule without a condition, which is a state of its own.
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
    if (model.groups.isEmpty) {
      // No blank row with a delete button under a line that says there is no condition.
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _addGroup,
          icon: const Icon(Icons.add),
          label: const Text('Add a term'),
        ),
      );
    }
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
  void didUpdateWidget(_TermRow old) {
    super.didUpdateWidget(old);
    // A row above was removed and this state now shows another term: its own words.
    if (widget.term.text != _ctl.text) {
      _ctl.value = TextEditingValue(
        text: widget.term.text,
        selection: TextSelection.collapsed(offset: widget.term.text.length),
      );
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Widget _option(String label, bool on, BuilderTerm Function() toggled) =>
      FilterChip(
        label: Text(label),
        selected: on,
        onSelected: (_) => widget.onChanged(toggled()),
      );

  @override
  Widget build(BuildContext context) {
    final t = widget.term;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ctl,
                decoration: InputDecoration(
                  hintText: t.negated
                      ? 'word it must not have'
                      : 'word or phrase',
                  isDense: true,
                ),
                onChanged: (v) => widget.onChanged(t.copyWith(text: v)),
              ),
            ),
            IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.close),
              onPressed: widget.onRemove,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            _option(
              'Must not contain',
              t.negated,
              () => t.copyWith(negated: !t.negated),
            ),
            _option(
              'Whole word',
              t.wholeWord,
              () => t.copyWith(wholeWord: !t.wholeWord),
            ),
            _option(
              'Match case',
              t.caseSensitive,
              () => t.copyWith(caseSensitive: !t.caseSensitive),
            ),
          ],
        ),
      ],
    );
  }
}
