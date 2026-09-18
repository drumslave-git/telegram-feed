import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:rules/rules.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../ai/semantic_gate.dart';
import 'rule_editor_screen.dart';

/// All keyword rules with enable switches (SPEC: rules are global or per channel).
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

  void _edit(BuildContext context, Rule? rule) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RuleEditorScreen(
          db: db,
          gateway: gateway,
          rule: rule,
          semanticCheck:
              semanticCheck ??
              SemanticGate(db: db, secrets: const SecureSecretStore()).check,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rules')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(context, null),
        tooltip: 'New rule',
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          if (batteryExempt != null)
            FutureBuilder<bool>(
              future: batteryExempt!(),
              builder: (context, snap) => snap.data == false
                  ? MaterialBanner(
                      content: const Text(
                        'Android may stop the watcher in the background. Allow the app to ignore battery optimisation so rules keep working.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: onRequestBatteryExemption,
                          child: const Text('Allow'),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
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
            child: StreamBuilder<List<Rule>>(
              stream: db.watchRules(),
              builder: (context, snap) {
                final rules = snap.data ?? const <Rule>[];
                if (rules.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'No rules yet. A rule watches your feeds\' channels for words and notifies you, optionally reading the post aloud.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return FutureBuilder<List<WatchedChannel>>(
                  future: db.allWatched(),
                  builder: (context, w) {
                    final titles = {
                      for (final c in w.data ?? const <WatchedChannel>[])
                        c.chatId: c.title,
                    };
                    return ListView.builder(
                      itemCount: rules.length,
                      itemBuilder: (context, i) {
                        final r = rules[i];
                        final scope = r.scopeKind == 'channel'
                            ? (titles[r.scopeChatId] ??
                                  'Channel ${r.scopeChatId}')
                            : 'All channels';
                        return ListTile(
                          leading: Icon(switch (r.priority) {
                            'urgent' => Icons.priority_high,
                            'silent' => Icons.notifications_off_outlined,
                            _ => Icons.notifications_outlined,
                          }),
                          title: Text(r.name),
                          subtitle: Text(
                            '$scope · ${_preview(r)}${r.readAloud ? ' · read aloud' : ''}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Switch(
                            value: r.enabled,
                            onChanged: (v) => db.setRuleEnabled(r.id, v),
                          ),
                          onTap: () => _edit(context, r),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Keyword condition, and for AI rules the description they check.
  static String _preview(Rule r) {
    final prompt = r.semanticPrompt?.trim() ?? '';
    if (prompt.isEmpty) return _conditionPreview(r);
    final keywords = _conditionPreview(r);
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
