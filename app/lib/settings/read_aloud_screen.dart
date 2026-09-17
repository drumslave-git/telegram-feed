import 'dart:convert';

import 'package:app_db/app_db.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../service/tts_service.dart' show TtsKeys;

/// Engine voices as `{name, locale}`; injectable so tests need no engine.
typedef VoiceLister = Future<List<Map<String, String>>> Function();

/// Speaks a preview with the given parameters; injectable for tests.
typedef Previewer = Future<void> Function({
  required String text,
  required String language,
  Map<String, String>? voice,
  double? rate,
  double? pitch,
});

Future<List<Map<String, String>>> engineVoices() async {
  final raw = await FlutterTts().getVoices;
  if (raw is! List) return const [];
  return [
    for (final v in raw)
      if (v is Map) {for (final e in v.entries) '${e.key}': '${e.value}'},
  ];
}

Future<void> enginePreview({
  required String text,
  required String language,
  Map<String, String>? voice,
  double? rate,
  double? pitch,
}) async {
  final tts = FlutterTts();
  await tts.setLanguage(language);
  if (voice != null) await tts.setVoice(voice);
  if (rate != null) await tts.setSpeechRate(rate);
  if (pitch != null) await tts.setPitch(pitch);
  await tts.speak(text, focus: true);
}

/// Read-aloud preferences (ARCHITECTURE.md section 7): the service's TtsService reads the
/// same keys, so changes apply to the next utterance.
class ReadAloudScreen extends StatefulWidget {
  const ReadAloudScreen({
    super.key,
    required this.db,
    this.voices = engineVoices,
    this.preview = enginePreview,
  });
  final AppDatabase db;
  final VoiceLister voices;
  final Previewer preview;

  @override
  State<ReadAloudScreen> createState() => _ReadAloudScreenState();
}

class _ReadAloudScreenState extends State<ReadAloudScreen> {
  double _rate = 0.5;
  double _pitch = 1.0;
  int _maxChars = 600;
  String _language = 'en';
  List<Map<String, String>> _voices = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = widget.db;
    _rate = double.tryParse(await db.setting(TtsKeys.rate) ?? '') ?? 0.5;
    _pitch = double.tryParse(await db.setting(TtsKeys.pitch) ?? '') ?? 1.0;
    _maxChars = int.tryParse(await db.setting(TtsKeys.maxChars) ?? '') ?? 600;
    _language = await db.setting(TtsKeys.defaultLanguage) ?? 'en';
    try {
      _voices = await widget.voices();
    } catch (_) {
      _voices = const [];
    }
    if (mounted) setState(() => _loaded = true);
  }

  /// Languages the engine has voices for, plus the current default.
  List<String> get _languages {
    final codes = <String>{_language};
    for (final v in _voices) {
      final locale = v['locale'] ?? '';
      if (locale.isNotEmpty) {
        codes.add(locale.split(RegExp('[-_]')).first.toLowerCase());
      }
    }
    return codes.toList()..sort();
  }

  List<Map<String, String>> _voicesFor(String language) => [
    for (final v in _voices)
      if ((v['locale'] ?? '').toLowerCase().startsWith(language.toLowerCase()))
        v,
  ];

  Future<void> _preview() async {
    final voiceJson = await widget.db.setting(TtsKeys.voiceFor(_language));
    Map<String, String>? voice;
    if (voiceJson != null) {
      voice = (jsonDecode(voiceJson) as Map).cast<String, String>();
    }
    await widget.preview(
      text: 'New post in Example channel. This is how posts will sound.',
      language: _language,
      voice: voice,
      rate: _rate,
      pitch: _pitch,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(title: const Text('Read aloud')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final db = widget.db;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Read aloud'),
        actions: [
          IconButton(
            tooltip: 'Preview',
            icon: const Icon(Icons.volume_up),
            onPressed: _preview,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          ListTile(
            title: const Text('Speed'),
            subtitle: Slider(
              value: _rate,
              min: 0.2,
              max: 1.0,
              divisions: 8,
              label: '${(_rate * 2).toStringAsFixed(1)}x',
              onChanged: (v) => setState(() => _rate = v),
              onChangeEnd: (v) => db.setSetting(TtsKeys.rate, v.toString()),
            ),
          ),
          ListTile(
            title: const Text('Pitch'),
            subtitle: Slider(
              value: _pitch,
              min: 0.5,
              max: 2.0,
              divisions: 6,
              label: _pitch.toStringAsFixed(2),
              onChanged: (v) => setState(() => _pitch = v),
              onChangeEnd: (v) => db.setSetting(TtsKeys.pitch, v.toString()),
            ),
          ),
          ListTile(
            title: const Text('Maximum length'),
            subtitle: Text(
              'Posts longer than $_maxChars characters end with "and more"',
            ),
            trailing: DropdownButton<int>(
              value: _maxChars,
              items: const [
                DropdownMenuItem(value: 300, child: Text('300')),
                DropdownMenuItem(value: 600, child: Text('600')),
                DropdownMenuItem(value: 1200, child: Text('1200')),
                DropdownMenuItem(value: 3000, child: Text('3000')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _maxChars = v);
                db.setSetting(TtsKeys.maxChars, v.toString());
              },
            ),
          ),
          ListTile(
            title: const Text('Language when unknown'),
            subtitle: const Text(
              'Used when a post\'s language cannot be detected',
            ),
            trailing: DropdownButton<String>(
              value: _language,
              items: [
                for (final l in _languages)
                  DropdownMenuItem(value: l, child: Text(l)),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _language = v);
                db.setSetting(TtsKeys.defaultLanguage, v);
              },
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Voice per language',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          if (_voices.isEmpty)
            const ListTile(
              title: Text('No voices reported by the speech engine'),
              subtitle: Text(
                'The system default voice is used for every language',
              ),
            )
          else
            for (final l in _languages)
              StreamBuilder<String?>(
                stream: db.watchSetting(TtsKeys.voiceFor(l)),
                builder: (context, snap) {
                  final current = snap.data == null
                      ? null
                      : (jsonDecode(snap.data!) as Map)['name'] as String?;
                  final voices = _voicesFor(l);
                  return ListTile(
                    title: Text(l),
                    subtitle: Text(current ?? 'System default'),
                    trailing: DropdownButton<String?>(
                      value: voices.any((v) => v['name'] == current)
                          ? current
                          : null,
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Default'),
                        ),
                        for (final v in voices)
                          DropdownMenuItem<String?>(
                            value: v['name'],
                            child: Text(v['name'] ?? ''),
                          ),
                      ],
                      onChanged: (name) {
                        final v = voices
                            .where((x) => x['name'] == name)
                            .firstOrNull;
                        if (v == null) {
                          db.setSetting(TtsKeys.voiceFor(l), '');
                        } else {
                          db.setSetting(
                            TtsKeys.voiceFor(l),
                            jsonEncode({
                              'name': v['name'],
                              'locale': v['locale'],
                            }),
                          );
                        }
                      },
                    ),
                  );
                },
              ),
        ],
      ),
    );
  }
}
