import 'dart:async';

import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:rules/rules.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../ai/semantic_gate.dart';
import '../widgets/empty_state.dart';
import 'rule_editor_screen.dart';

/// Opens the rule editor: for [rule], or for a new rule in [feedId] (the first feed when
/// null).
void openRuleEditor(
  BuildContext context, {
  required AppDatabase db,
  required TelegramGateway gateway,
  Rule? rule,
  int? feedId,
  SemanticCheck? semanticCheck,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => RuleEditorScreen(
      db: db,
      gateway: gateway,
      rule: rule,
      feedId: feedId,
      semanticCheck:
          semanticCheck ??
          SemanticGate(db: db, secrets: const SecureSecretStore()).check,
    ),
  ),
);

/// Every rule of every feed, grouped by feed: the overview behind the Rules button of the
/// home screen. A feed's own rules are also on the Rules tab of its info screen.
class RulesScreen extends StatelessWidget {
  const RulesScreen({
    super.key,
    required this.db,
    required this.gateway,
    this.batteryExempt,
    this.onRequestBatteryExemption,
    this.semanticCheck,
  });
  final AppDatabase db;
  final TelegramGateway gateway;

  /// Null when the platform has no battery optimisation (tests, desktop).
  final Future<bool> Function()? batteryExempt;
  final Future<void> Function()? onRequestBatteryExemption;

  /// Asks the AI endpoint (rule editor dry run); defaults to the configured endpoint.
  final SemanticCheck? semanticCheck;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rules')),
      // With no feeds the editor would open on an empty feed dropdown and refuse to
      // save, so the button says what is missing instead.
      floatingActionButton: StreamBuilder<List<Feed>>(
        stream: db.watchFeeds(),
        builder: (context, snap) {
          final feeds = snap.data ?? const <Feed>[];
          return FloatingActionButton(
            onPressed: () => feeds.isEmpty
                ? _needsFeed(context)
                : openRuleEditor(
                    context,
                    db: db,
                    gateway: gateway,
                    semanticCheck: semanticCheck,
                  ),
            tooltip: 'New rule',
            child: const Icon(Icons.add),
          );
        },
      ),
      body: RuleList(
        db: db,
        gateway: gateway,
        batteryExempt: batteryExempt,
        onRequestBatteryExemption: onRequestBatteryExemption,
        semanticCheck: semanticCheck,
      ),
    );
  }

  void _needsFeed(BuildContext context) => unawaited(
    showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('No feeds yet'),
        content: const Text(
          'Every rule belongs to a feed and watches its channels. Make a feed first, '
          'then give it rules.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialog);
              Navigator.of(context).maybePop();
            },
            child: const Text('Go to feeds'),
          ),
        ],
      ),
    ),
  );
}

/// Rules with their switches: those of one feed ([feedId]), or of all feeds under a
/// header per feed. Above them the battery banner, where there is one, and the note that
/// AI rules are being skipped.
class RuleList extends StatelessWidget {
  const RuleList({
    super.key,
    required this.db,
    required this.gateway,
    this.feedId,
    this.batteryExempt,
    this.onRequestBatteryExemption,
    this.semanticCheck,
  });
  final AppDatabase db;
  final TelegramGateway gateway;
  final int? feedId;
  final Future<bool> Function()? batteryExempt;
  final Future<void> Function()? onRequestBatteryExemption;
  final SemanticCheck? semanticCheck;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (batteryExempt != null)
          BatteryBanner(
            exempt: batteryExempt!,
            onRequest: onRequestBatteryExemption,
          ),
        StreamBuilder<String?>(
          stream: db.watchSetting(AiKeys.lastError),
          builder: (context, snap) {
            final failure = AiFailure.decode(snap.data);
            if (failure == null) return const SizedBox.shrink();
            final t = TimeOfDay.fromDateTime(failure.at).format(context);
            return ListTile(
              dense: true,
              leading: Icon(
                Icons.info_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: const Text('AI rules are being skipped'),
              subtitle: Text('${failure.message} (last tried $t)'),
            );
          },
        ),
        Expanded(
          child: StreamBuilder<List<Feed>>(
            stream: db.watchFeeds(),
            builder: (context, feedsSnap) => StreamBuilder<List<Rule>>(
              stream: db.watchRules(),
              builder: (context, snap) {
                final feeds = [
                  for (final f in feedsSnap.data ?? const <Feed>[])
                    if (feedId == null || f.id == feedId) f,
                ];
                final rules = [
                  for (final r in snap.data ?? const <Rule>[])
                    if (feedId == null || r.feedId == feedId) r,
                ];
                if (rules.isEmpty) return _empty(context, feeds);
                return FutureBuilder<List<WatchedChannel>>(
                  future: db.allWatched(),
                  builder: (context, w) {
                    final titles = {
                      for (final c in w.data ?? const <WatchedChannel>[])
                        c.chatId: c.title,
                    };
                    return ListView(
                      padding: const EdgeInsets.only(bottom: 88),
                      children: [
                        for (final f in feeds)
                          if (rules.any((r) => r.feedId == f.id)) ...[
                            if (feedId == null) _FeedHeader(f.name),
                            for (final r in rules)
                              if (r.feedId == f.id)
                                _RuleTile(
                                  rule: r,
                                  channelTitle: r.scopeChatId == null
                                      ? null
                                      // A chat id would say nothing; this says what
                                      // happened to the channel.
                                      : titles[r.scopeChatId] ??
                                            'A channel that left the feed',
                                  onChanged: (v) => db.setRuleEnabled(r.id, v),
                                  onTap: () => openRuleEditor(
                                    context,
                                    db: db,
                                    gateway: gateway,
                                    rule: r,
                                    semanticCheck: semanticCheck,
                                  ),
                                ),
                          ],
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _empty(BuildContext context, List<Feed> feeds) {
    if (feeds.isEmpty) {
      return EmptyState(
        icon: Icons.notifications_none,
        title: 'No rules yet',
        message:
            'Rules belong to feeds. Make a feed first, then give it rules.',
        actionLabel: 'Go to feeds',
        actionIcon: Icons.arrow_back,
        onAction: () => Navigator.of(context).maybePop(),
      );
    }
    return EmptyState(
      icon: Icons.notifications_none,
      title: 'No rules yet',
      message: feedId != null
          ? 'A rule watches this feed\'s channels, or one of them, and notifies you, '
                'optionally reading the post aloud: give it words to look for, or leave '
                'the condition empty to be notified about every post the feed shows.'
          : 'Every feed has its own rules: a rule watches the feed\'s channels, or one '
                'of them, and notifies you, optionally reading the post aloud.',
      actionLabel: 'New rule',
      onAction: () => openRuleEditor(
        context,
        db: db,
        gateway: gateway,
        feedId: feedId ?? feeds.first.id,
        semanticCheck: semanticCheck,
      ),
    );
  }
}

/// The name of a feed above its rules in the overview.
class _FeedHeader extends StatelessWidget {
  const _FeedHeader(this.name);
  final String name;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      name,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}

class _RuleTile extends StatelessWidget {
  const _RuleTile({
    required this.rule,
    required this.channelTitle,
    required this.onChanged,
    required this.onTap,
  });
  final Rule rule;

  /// The one channel the rule watches; null for every channel of its feed.
  final String? channelTitle;
  final ValueChanged<bool> onChanged;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = rule;
    final scope = channelTitle ?? 'Every channel';
    // In words as well as in the glyph: the icon alone says nothing to a screen reader
    // and little to a reader who has not learned it.
    final priority = switch (r.priority) {
      'urgent' => 'urgent',
      'silent' => 'silent',
      _ => null,
    };
    return ListTile(
      leading: Semantics(
        label: switch (r.priority) {
          'urgent' => 'Urgent rule',
          'silent' => 'Silent rule',
          _ => 'Normal rule',
        },
        child: Icon(switch (r.priority) {
          'urgent' => Icons.priority_high,
          'silent' => Icons.notifications_off_outlined,
          _ => Icons.notifications_outlined,
        }),
      ),
      title: Text(r.name),
      subtitle: Text(
        [
          scope,
          _preview(r),
          ?priority,
          if (r.readAloud) 'read aloud',
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Switch(value: r.enabled, onChanged: onChanged),
      onTap: onTap,
    );
  }

  /// Keyword condition, and for AI rules the description they check. A rule with no
  /// condition at all matches every post of its channels.
  static String _preview(Rule r) {
    final prompt = r.semanticPrompt?.trim() ?? '';
    final keywords = _conditionPreview(r);
    if (prompt.isEmpty) return keywords.isEmpty ? 'every post' : keywords;
    return keywords.isEmpty ? 'AI: $prompt' : 'AI: $prompt · only if $keywords';
  }

  static String _conditionPreview(Rule r) {
    try {
      return RuleParser.format(RuleSpec.fromRow(r).condition);
    } on FormatException {
      return '(invalid condition)';
    }
  }
}

/// Asks for the battery-optimisation exemption until it is granted. The answer is given in a
/// system dialog or in Android's settings, so it is checked again whenever the app resumes.
class BatteryBanner extends StatefulWidget {
  const BatteryBanner({super.key, required this.exempt, this.onRequest});
  final Future<bool> Function() exempt;
  final Future<void> Function()? onRequest;

  @override
  State<BatteryBanner> createState() => _BatteryBannerState();
}

class _BatteryBannerState extends State<BatteryBanner>
    with WidgetsBindingObserver {
  bool _exempt = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final exempt = await widget.exempt();
    if (mounted && exempt != _exempt) setState(() => _exempt = exempt);
  }

  Future<void> _request() async {
    await widget.onRequest?.call();
    await _check();
  }

  @override
  Widget build(BuildContext context) {
    if (_exempt) return const SizedBox.shrink();
    return MaterialBanner(
      content: const Text(
        'Android may stop the watcher in the background. Allow the app to ignore battery optimisation so rules keep working.',
      ),
      actions: [TextButton(onPressed: _request, child: const Text('Allow'))],
    );
  }
}
