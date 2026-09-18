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
