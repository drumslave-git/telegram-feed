import 'dart:convert';

import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:rules/rules.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../notifications/notification_policy.dart';
import 'rule_builder_model.dart';

/// Create or edit one rule: visual builder or text form, scope, priority, read-aloud,
/// schedule, and a dry run against recent posts (SPEC section 4).
class RuleEditorScreen extends StatefulWidget {
  const RuleEditorScreen({
    super.key,
    required this.db,
    required this.gateway,
    this.rule,
    this.policyGranted = NotificationPolicy.isGrantedFn,
    this.openPolicySettings = NotificationPolicy.openSettings,
  });
  final AppDatabase db;
  final TelegramGateway gateway;
  final Rule? rule;

  /// Injectable for tests: whether DND bypass is allowed (urgent rules).
  final Future<bool> Function() policyGranted;
  final Future<void> Function() openPolicySettings;

  @override
  State<RuleEditorScreen> createState() => _RuleEditorScreenState();
}

class _RuleEditorScreenState extends State<RuleEditorScreen> {
  late final _name = TextEditingController(text: widget.rule?.name ?? '');
  late final _text = TextEditingController();
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
  List<WatchedChannel> _channels = const [];

  @override
  void initState() {
    super.initState();
    final r = widget.rule;
    if (r != null) {
      _scopeChatId = r.scopeKind == 'channel' ? r.scopeChatId : null;
      _priority = r.priority;
      _readAloud = r.readAloud;
      _enabled = r.enabled;
      try {
        final spec = RuleSpec.fromRow(r);
        final m = BuilderModel.fromExpr(spec.condition);
        if (m != null) {
          _model = m;
        } else {
          _textMode = true;
        }
        _text.text = RuleParser.format(spec.condition);
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
    widget.db.allWatched().then((c) {
      if (mounted) setState(() => _channels = c);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _text.dispose();
    super.dispose();
  }

  /// The condition from whichever editor is active, or null with an error shown.
  Expr? _condition() {
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
      scopeKind: Value(_scopeChatId == null ? 'global' : 'channel'),
      scopeChatId: Value(_scopeChatId),
      conditionJson: Value(jsonEncode(cond.toJson())),
      priority: Value(_priority),
      readAloud: Value(_readAloud),
      scheduleJson: Value(schedule),
    );
    final r = widget.rule;
    if (r == null) {
      await widget.db.insertRule(
        RulesCompanion.insert(
          name: name,
          enabled: Value(_enabled),
          scopeKind: _scopeChatId == null ? 'global' : 'channel',
          scopeChatId: Value(_scopeChatId),
          conditionJson: jsonEncode(cond.toJson()),
          priority: _priority,
          readAloud: Value(_readAloud),
          scheduleJson: Value(schedule),
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
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      await widget.db.deleteRule(r.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  /// Dry run: evaluate the condition against the latest posts of the rule's channels.
  Future<void> _testOnRecent() async {
    final cond = _condition();
    if (cond == null) return;
    final chats = _scopeChatId != null
        ? [_scopeChatId!]
        : _channels.map((c) => c.chatId).take(10).toList();
    final titles = {for (final c in _channels) c.chatId: c.title};
    final evaluator = RuleEvaluator();
    final hits = <Post>[];
    var scanned = 0;
    for (final chat in chats) {
      try {
        final posts = await widget.gateway.history(chat, limit: 20);
        scanned += posts.length;
        hits.addAll(
          posts.where(
            (p) => p.text.isNotEmpty && evaluator.matches(cond, p.text),
          ),
        );
      } on TelegramException {
        // skip channels that fail; the dry run is best effort
      }
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            hits.isEmpty
                ? 'No match in the last $scanned posts.'
                : '${hits.length} of the last $scanned posts match:',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final p in hits.take(30))
            ListTile(
              title: Text(titles[p.chatId] ?? '${p.chatId}'),
              subtitle: Text(
                p.text,
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
          DropdownButtonFormField<int?>(
            initialValue: _scopeChatId,
            decoration: const InputDecoration(labelText: 'Channels'),
            items: [
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('All channels in my feeds'),
              ),
              for (final c in _channels)
                DropdownMenuItem<int?>(
                  value: c.chatId,
                  child: Text(c.title, overflow: TextOverflow.ellipsis),
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
              onChanged: (_) {
                if (_textError != null) setState(() => _textError = null);
              },
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
