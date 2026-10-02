import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../ai/semantic_gate.dart';
import '../l10n/l10n.dart';

/// Endpoint for AI semantic rules: any OpenAI-compatible chat completions API. The key is
/// kept in the platform keystore, never in the database.
class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({
    super.key,
    required this.db,
    required this.secrets,
    this.client,
  });
  final AppDatabase db;
  final SecretStore secrets;

  /// Injected in tests.
  final SemanticClient? client;

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  final _baseUrl = TextEditingController();
  final _model = TextEditingController();
  final _apiKey = TextEditingController();
  bool _loaded = false;
  bool _testing = false;
  bool _showKey = false;
  String? _testResult;
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    loadAiConfig(widget.db, widget.secrets).then((c) {
      if (!mounted) return;
      setState(() {
        _baseUrl.text = c.baseUrl;
        _model.text = c.model;
        _apiKey.text = c.apiKey;
        _loaded = true;
      });
    });
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _model.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.db.setSetting(AiKeys.baseUrl, _baseUrl.text.trim());
    await widget.db.setSetting(AiKeys.model, _model.text.trim());
    await widget.secrets.write(AiKeys.apiKeySecret, _apiKey.text.trim());
  }

  Future<void> _saveAndClose() async {
    await _save();
    if (mounted) Navigator.of(context).pop();
  }

  /// Saves, then asks the model a question with a known answer.
  Future<void> _test() async {
    final l10n = context.l10n;
    setState(() {
      _testing = true;
      _testResult = null;
    });
    await _save();
    final client = widget.client ?? SemanticClient();
    try {
      final hits = await client.matching(
        config: await loadAiConfig(widget.db, widget.secrets),
        postText: 'The central bank cut its key interest rate by half a point.',
        criteria: const ['football results', 'interest rate decisions'],
      );
      _testOk = hits.length == 1 && hits.contains(1);
      _testResult = _testOk
          ? l10n.aiSettingsTestOk
          : l10n.aiSettingsTestUnexpected;
    } on SemanticException catch (e) {
      _testOk = false;
      _testResult = e.describe(l10n);
    } finally {
      if (widget.client == null) client.close();
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.aiSettingsTitle),
        actions: [
          TextButton(
            onPressed: _loaded ? _saveAndClose : null,
            child: Text(l10n.commonSave),
          ),
        ],
      ),
      // Fields appear once the stored values are in, so loading never overwrites typing.
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(l10n.aiSettingsIntro, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 16),
                TextField(
                  controller: _baseUrl,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: l10n.aiSettingsEndpoint,
                    hintText: 'https://api.openai.com/v1',
                    helperText: l10n.aiSettingsEndpointHelper,
                    helperMaxLines: 2,
                  ),
                ),
                if (_baseUrl.text.trim().toLowerCase().startsWith('http://'))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      l10n.aiSettingsHttpWarning,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: _model,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: l10n.aiSettingsModel,
                    hintText: 'gpt-4o-mini',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _apiKey,
                  obscureText: !_showKey,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: l10n.aiSettingsApiKey,
                    helperText: l10n.aiSettingsApiKeyHelper,
                    suffixIcon: IconButton(
                      tooltip: _showKey
                          ? l10n.aiSettingsHideKey
                          : l10n.aiSettingsShowKey,
                      icon: Icon(
                        _showKey ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () => setState(() => _showKey = !_showKey),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _loaded && !_testing ? _test : null,
                    icon: _testing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.network_check),
                    label: Text(l10n.aiSettingsSaveAndTest),
                  ),
                ),
                if (_testResult != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _testResult!,
                      style: TextStyle(
                        color: _testOk
                            ? theme.colorScheme.primary
                            : theme.colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
