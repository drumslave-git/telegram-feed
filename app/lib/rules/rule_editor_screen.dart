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
import '../l10n/l10n.dart';
import 'condition_editor.dart';
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
    this.notificationsGranted = NotificationPermissionAsk.grantedFn,
    this.requestNotifications = NotificationPermissionAsk.request,
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

  /// Whether Android lets the app notify at all, and the ask for it. A rule that cannot
  /// notify does nothing, so the ask happens once a rule is saved.
  final Future<bool> Function() notificationsGranted;
  final Future<bool> Function() requestNotifications;

  /// Asks the AI endpoint which descriptions a post matches (dry run of AI rules).
  final SemanticCheck? semanticCheck;

  @override
  State<RuleEditorScreen> createState() => _RuleEditorScreenState();
}

class _RuleEditorScreenState extends State<RuleEditorScreen> {
  late final _name = TextEditingController(text: widget.rule?.name ?? '');
  late final ConditionController _cond;
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

  /// Notifies at once, through the connection the app then keeps open.
  bool _instant = false;
  bool _enabled = true;
  String? _nameError;
  String? _feedError;
  String? _scheduleError;
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
    var cond = ConditionController();
    if (r != null) {
      _scopeChatId = r.scopeChatId;
      _priority = r.priority;
      _readAloud = r.readAloud;
      _instant = r.instant;
      _enabled = r.enabled;
      try {
        final spec = RuleSpec.fromRow(r);
        // A rule without keywords (every post, or every post sent to the AI) starts with
        // both editors empty.
        cond = ConditionController(spec.condition);
        final s = spec.schedule;
        if (s != null) {
          _scheduled = true;
          _weekdays = {...s.weekdays};
          _from = s.from;
          _to = s.to;
        }
      } on FormatException {
        cond = ConditionController.unreadable(r.conditionJson);
      }
    }
    // The note above the condition and the back guard follow what is typed.
    _cond = cond..addListener(() => setState(() {}));
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
    _instant,
    _enabled,
    _useAi ? _prompt.text.trim() : '',
    _cond.snapshot,
    _scheduled ? '${_weekdays.toList()..sort()} $_from-$_to' : '',
  ].join('|');

  bool get _dirty => _initial != null && _snapshot() != _initial;

  /// Leaving with changes: asks whether to throw them away.
  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.ruleDiscardTitle),
        content: Text(context.l10n.ruleDiscardMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.commonKeepEditing),
          ),
          DestructiveButton(
            onPressed: () => Navigator.pop(context, true),
            label: context.l10n.commonDiscard,
          ),
        ],
      ),
    );
    if ((leave ?? false) && mounted) Navigator.of(context).pop();
  }

  /// No keyword typed in the active editor.
  bool get _keywordsBlank => _cond.blank;

  @override
  void dispose() {
    _name.dispose();
    _cond.dispose();
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final feedId = _feedId;
    // On the fields themselves: a snackbar can stand behind the keyboard, and the field
    // it is about is at the top of a scrolled form.
    final l10n = context.l10n;
    setState(() {
      _nameError = name.isEmpty ? l10n.ruleErrorNoName : null;
      _feedError = feedId == null ? l10n.ruleErrorNoFeed : null;
      _scheduleError = _scheduled && _weekdays.isEmpty
          ? l10n.scheduleErrorNoDays
          : null;
    });
    if (_nameError != null ||
        _feedError != null ||
        _scheduleError != null ||
        feedId == null) {
      return;
    }
    final cond = _cond.condition();
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
      instant: Value(_instant),
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
          instant: Value(_instant),
          scheduleJson: Value(schedule),
          semanticPrompt: Value(_isSemantic ? _prompt.text.trim() : null),
          createdAt: DateTime.now(),
        ),
      );
    } else {
      await widget.db.updateRule(r.copyWithCompanion(companion));
    }
    if (!mounted) return;
    await _askToNotify();
    if (mounted) Navigator.of(context).pop();
  }

  /// A rule that cannot notify is a rule that does nothing. Android grants the ask once,
  /// so it happens here, where the reader has just said what they want to hear about,
  /// and not on the blank screen the app starts with.
  Future<void> _askToNotify() async {
    if (await widget.notificationsGranted() || !mounted) return;
    final ask = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.ruleNotifyAskTitle),
        content: Text(context.l10n.ruleNotifyAskMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.commonNotNow),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.commonAllow),
          ),
        ],
      ),
    );
    if (ask ?? false) await widget.requestNotifications();
  }

  /// Urgent rules may break through Do Not Disturb only where Android allows it; asked
  /// the moment "Urgent" is picked, so the answer is about the choice just made.
  Future<void> _askForDoNotDisturb() async {
    if (await widget.policyGranted() || !mounted) return;
    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.ruleDndAskTitle),
        content: Text(context.l10n.ruleDndAskMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.commonLater),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.commonOpenSettings),
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
        title: Text(context.l10n.ruleDeleteTitle(r.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.commonCancel),
          ),
          DestructiveButton(
            onPressed: () => Navigator.pop(context, true),
            label: context.l10n.commonDelete,
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
    final cond = _cond.condition();
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
    final matchesEverything =
        ConditionController.isMatchAll(cond) && !_isSemantic;
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
    if (!mounted) return;
    final l10n = context.l10n;
    final read = chats.length - failed;
    final scope = [
      l10n.ruleDryRunScopeChannels(read),
      if (all.length > chats.length)
        l10n.ruleDryRunScopeOfTotal(all.length, _dryRunChannels),
      if (failed > 0) l10n.ruleDryRunScopeFailed(failed),
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
            ? l10n.ruleDryRunAiNone(sample.length, hits.length, scanned)
            : l10n.ruleDryRunAiMatched(confirmed.length, sample.length);
      } on SemanticException catch (e) {
        headline = l10n.ruleDryRunAiFailed(e.describe(l10n));
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
                    ? context.l10n.ruleDryRunNoMatch(scanned)
                    : context.l10n.ruleDryRunMatches(hits.length, scanned)),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              context.l10n.ruleDryRunChecked(scope),
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
                      l10n: context.l10n,
                    ),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
              subtitle: Text(
                // A post without text is one a rule with no condition matches too.
                postLabel(p, context.l10n.mediaWords),
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
    final l10n = context.l10n;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_confirmLeave());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.rule == null ? l10n.ruleNew : l10n.ruleEditTitle),
          actions: [
            if (widget.rule != null)
              IconButton(
                tooltip: l10n.commonDelete,
                icon: const Icon(Icons.delete_outline),
                onPressed: _delete,
              ),
            TextButton(
              onPressed: _saving ? null : _save,
              child: Text(l10n.commonSave),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _name,
              decoration: InputDecoration(
                labelText: l10n.ruleNameLabel,
                errorText: _nameError,
              ),
              textInputAction: TextInputAction.next,
              // The back guard compares the form with how it opened.
              onChanged: (_) => setState(() => _nameError = null),
            ),
            // At the top, where the state of the rule belongs, not under everything.
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.ruleEnabledTitle),
              subtitle: Text(l10n.ruleEnabledSubtitle),
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
            const SizedBox(height: 4),
            DropdownButtonFormField<int>(
              key: ValueKey('feed-${_feeds.length}-$_feedId'),
              initialValue: _feedId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.ruleFeedLabel,
                errorText: _feedError,
                helperText: _feeds.isEmpty ? l10n.ruleErrorNoFeed : null,
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
              decoration: InputDecoration(labelText: l10n.ruleChannelsLabel),
              items: [
                DropdownMenuItem<int?>(
                  value: null,
                  child: Text(l10n.ruleEveryChannelOfFeed),
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
            ConditionEditor(
              controller: _cond,
              title: Text(
                l10n.ruleConditionTitle,
                style: theme.textTheme.titleMedium,
              ),
              note: !_keywordsBlank && !_isSemantic
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        !_isSemantic
                            ? l10n.ruleNoConditionNote
                            : _keywordsBlank
                            ? l10n.semanticNoKeywordsNote
                            : l10n.semanticAfterKeywordsNote,
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
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
                  _testing ? l10n.ruleDryRunTesting : l10n.ruleDryRunButton,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.ruleNotificationTitle,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            // One row per priority with what it does, as the official app lists such
            // choices; every language's words fit.
            RadioGroup<String>(
              groupValue: _priority,
              onChanged: (v) {
                if (v == null || v == _priority) return;
                setState(() => _priority = v);
                // Asked here, where the choice is made, instead of at save time.
                if (v == 'urgent') unawaited(_askForDoNotDisturb());
              },
              child: Column(
                children: [
                  for (final (value, title, info, icon) in [
                    (
                      'silent',
                      l10n.rulePrioritySilent,
                      l10n.rulePrioritySilentInfo,
                      Icons.notifications_off_outlined,
                    ),
                    (
                      'normal',
                      l10n.rulePriorityNormal,
                      l10n.rulePriorityNormalInfo,
                      Icons.notifications_outlined,
                    ),
                    (
                      'urgent',
                      l10n.rulePriorityUrgent,
                      l10n.rulePriorityUrgentInfo,
                      Icons.priority_high,
                    ),
                  ])
                    RadioListTile<String>(
                      value: value,
                      contentPadding: EdgeInsets.zero,
                      title: Text(title),
                      subtitle: Text(info),
                      secondary: Icon(icon),
                    ),
                ],
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.ruleReadAloud),
              value: _readAloud,
              onChanged: (v) => setState(() => _readAloud = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.ruleInstant),
              subtitle: Text(l10n.ruleInstantInfo),
              value: _instant,
              onChanged: (v) => setState(() => _instant = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.scheduleSwitch),
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
                        [
                          l10n.scheduleMon,
                          l10n.scheduleTue,
                          l10n.scheduleWed,
                          l10n.scheduleThu,
                          l10n.scheduleFri,
                          l10n.scheduleSat,
                          l10n.scheduleSun,
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
                    child: Text(l10n.scheduleFrom(Schedule.formatTime(_from))),
                  ),
                  TextButton(
                    onPressed: () => _pickTime(false),
                    child: Text(l10n.scheduleTo(Schedule.formatTime(_to))),
                  ),
                  if (_to < _from)
                    Text(
                      l10n.scheduleNextDay,
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.semanticAlsoAsk),
              subtitle: Text(l10n.semanticAlsoAskSubtitle),
              value: _useAi,
              onChanged: (v) => setState(() => _useAi = v),
            ),
            if (_useAi) ...[
              TextField(
                controller: _prompt,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: l10n.semanticPromptLabel,
                  hintText: l10n.semanticPromptHint,
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (!_aiConfigured)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    l10n.semanticNotConfigured,
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
