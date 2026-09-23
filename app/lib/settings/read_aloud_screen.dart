import 'dart:async';
import 'dart:convert';

import 'package:app_db/app_db.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../service/tts_service.dart' show TtsKeys;
import 'settings_tiles.dart';

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

/// One speaker for every preview, so a second tap replaces the first instead of talking
/// over it.
final FlutterTts _previewTts = FlutterTts();

Future<void> enginePreview({
  required String text,
  required String language,
  Map<String, String>? voice,
  double? rate,
  double? pitch,
}) async {
  final tts = _previewTts;
  await tts.stop();
  await tts.setLanguage(language);
  if (voice != null) await tts.setVoice(voice);
  if (rate != null) await tts.setSpeechRate(rate);
  if (pitch != null) await tts.setPitch(pitch);
  await tts.speak(text, focus: true);
}

Future<void> engineStopPreview() => _previewTts.stop();

/// English names of the languages speech engines offer, by ISO 639 code.
const _languageNames = <String, String>{
  'af': 'Afrikaans',
  'am': 'Amharic',
  'ar': 'Arabic',
  'as': 'Assamese',
  'az': 'Azerbaijani',
  'be': 'Belarusian',
  'bg': 'Bulgarian',
  'bn': 'Bengali',
  'brx': 'Bodo',
  'bs': 'Bosnian',
  'ca': 'Catalan',
  'cmn': 'Mandarin',
  'cs': 'Czech',
  'cy': 'Welsh',
  'da': 'Danish',
  'de': 'German',
  'doi': 'Dogri',
  'el': 'Greek',
  'en': 'English',
  'es': 'Spanish',
  'et': 'Estonian',
  'eu': 'Basque',
  'fa': 'Persian',
  'fi': 'Finnish',
  'fil': 'Filipino',
  'fr': 'French',
  'ga': 'Irish',
  'gl': 'Galician',
  'gu': 'Gujarati',
  'he': 'Hebrew',
  'hi': 'Hindi',
  'hr': 'Croatian',
  'hu': 'Hungarian',
  'hy': 'Armenian',
  'id': 'Indonesian',
  'is': 'Icelandic',
  'it': 'Italian',
  'ja': 'Japanese',
  'jv': 'Javanese',
  'ka': 'Georgian',
  'kk': 'Kazakh',
  'km': 'Khmer',
  'kn': 'Kannada',
  'ko': 'Korean',
  'kok': 'Konkani',
  'ks': 'Kashmiri',
  'ky': 'Kyrgyz',
  'lo': 'Lao',
  'lt': 'Lithuanian',
  'lv': 'Latvian',
  'mai': 'Maithili',
  'mk': 'Macedonian',
  'ml': 'Malayalam',
  'mn': 'Mongolian',
  'mni': 'Manipuri',
  'mr': 'Marathi',
  'ms': 'Malay',
  'my': 'Burmese',
  'nb': 'Norwegian',
  'ne': 'Nepali',
  'nl': 'Dutch',
  'no': 'Norwegian',
  'or': 'Odia',
  'pa': 'Punjabi',
  'pl': 'Polish',
  'pt': 'Portuguese',
  'ro': 'Romanian',
  'ru': 'Russian',
  'sa': 'Sanskrit',
  'sat': 'Santali',
  'sd': 'Sindhi',
  'si': 'Sinhala',
  'sk': 'Slovak',
  'sl': 'Slovenian',
  'sq': 'Albanian',
  'sr': 'Serbian',
  'su': 'Sundanese',
  'sv': 'Swedish',
  'sw': 'Swahili',
  'ta': 'Tamil',
  'te': 'Telugu',
  'th': 'Thai',
  'tr': 'Turkish',
  'uk': 'Ukrainian',
  'ur': 'Urdu',
  'uz': 'Uzbek',
  'vi': 'Vietnamese',
  'yue': 'Cantonese',
  'zh': 'Chinese',
  'zu': 'Zulu',
};

/// The language's English name, or its code where the table has none.
String languageName(String code) =>
    _languageNames[code.toLowerCase()] ?? code.toUpperCase();

/// A voice as a person reads it: "Female 1 · US", "Voice SFG · GB · online". Engines name
/// voices like `en-us-x-sfg#female_1-local`.
String voiceLabel(Map<String, String> voice) {
  final name = voice['name'] ?? '';
  final locale = voice['locale'] ?? '';
  final parts = locale.split(RegExp('[-_]'));
  final region = parts.length > 1 ? parts[1].toUpperCase() : '';
  final tail = name.contains('-x-') ? name.split('-x-').last : name;
  final hash = tail.split('#');
  String who;
  if (hash.length > 1) {
    final g = hash[1].split('-').first.split('_');
    who =
        '${g.first[0].toUpperCase()}${g.first.substring(1)}'
        '${g.length > 1 ? ' ${g[1]}' : ''}';
  } else {
    final id = tail.split('-').first;
    who = id.isEmpty ? name : 'Voice ${id.toUpperCase()}';
  }
  final online = name.endsWith('-network') ? 'online' : '';
  return [who, region, online].where((s) => s.isNotEmpty).join(' · ');
}

/// Read-aloud preferences (ARCHITECTURE.md section 7): the service's TtsService reads the
/// same keys, so changes apply to the next utterance.
class ReadAloudScreen extends StatefulWidget {
  const ReadAloudScreen({
    super.key,
    required this.db,
    this.voices = engineVoices,
    this.preview = enginePreview,
    this.stopPreview = engineStopPreview,
  });
  final AppDatabase db;
  final VoiceLister voices;
  final Previewer preview;

  /// Stops a preview still speaking; called when the screen closes.
  final Future<void> Function() stopPreview;

  @override
  State<ReadAloudScreen> createState() => _ReadAloudScreenState();
}

class _ReadAloudScreenState extends State<ReadAloudScreen> {
  double _rate = 0.5;
  double _pitch = 1.0;
  int _maxChars = 600;
  String _language = 'en';
  List<Map<String, String>> _voices = const [];

  /// Languages with a voice of their own, by code; every other one uses the default.
  final Map<String, Map<String, String>> _chosen = {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(widget.stopPreview().catchError((Object _) {}));
    super.dispose();
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
    for (final l in _languages) {
      final json = await db.setting(TtsKeys.voiceFor(l));
      if (json == null || json.isEmpty) continue;
      _chosen[l] = (jsonDecode(json) as Map).cast<String, String>();
    }
    if (mounted) setState(() => _loaded = true);
  }

  /// Languages the engine has voices for, plus the current default, by name.
  List<String> get _languages {
    final codes = <String>{_language};
    for (final v in _voices) {
      final locale = v['locale'] ?? '';
      if (locale.isNotEmpty) {
        codes.add(locale.split(RegExp('[-_]')).first.toLowerCase());
      }
    }
    return codes.toList()
      ..sort((a, b) => languageName(a).compareTo(languageName(b)));
  }

  List<Map<String, String>> _voicesFor(String language) => [
    for (final v in _voices)
      if ((v['locale'] ?? '').toLowerCase().startsWith(language.toLowerCase()))
        v,
  ];

  Future<void> _preview() async {
    await widget.preview(
      text: 'New post in Example channel. This is how posts will sound.',
      language: _language,
      voice: _chosen[_language],
      rate: _rate,
      pitch: _pitch,
    );
  }

  Future<void> _setVoice(String language, Map<String, String>? voice) async {
    await widget.db.setSetting(
      TtsKeys.voiceFor(language),
      voice == null
          ? ''
          : jsonEncode({'name': voice['name'], 'locale': voice['locale']}),
    );
    if (!mounted) return;
    setState(() {
      if (voice == null) {
        _chosen.remove(language);
      } else {
        _chosen[language] = voice;
      }
    });
  }

  /// The voices of one language, the chosen one ticked; the answer is null when the
  /// sheet was dismissed, and an empty map for the default voice.
  Future<void> _pickVoice(String language) async {
    final current = _chosen[language]?['name'];
    final picked = await showModalBottomSheet<Map<String, String>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  languageName(language),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ListTile(
                leading: Icon(
                  current == null ? Icons.check : null,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: const Text('The phone\'s default voice'),
                onTap: () => Navigator.pop(context, const <String, String>{}),
              ),
              for (final v in _voicesFor(language))
                ListTile(
                  leading: Icon(
                    v['name'] == current ? Icons.check : null,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(voiceLabel(v)),
                  onTap: () => Navigator.pop(context, v),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    await _setVoice(language, picked.isEmpty ? null : picked);
  }

  /// A language without a voice of its own yet, from a searchable list, then its voice.
  Future<void> _addLanguage() async {
    final options = [
      for (final l in _languages)
        if (!_chosen.containsKey(l) && _voicesFor(l).isNotEmpty) l,
    ];
    final code = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _LanguagePicker(codes: options),
    );
    if (code == null || !mounted) return;
    await _pickVoice(code);
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
    final chosen = _chosen.keys.toList()
      ..sort((a, b) => languageName(a).compareTo(languageName(b)));
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
            // The value beside the name: a slider with no number says nothing until it
            // is dragged, and the bubble is gone the moment the finger lifts.
            title: Text('Speed  ·  ${(_rate * 2).toStringAsFixed(1)}×'),
            subtitle: Slider(
              value: _rate,
              min: 0.2,
              max: 1.0,
              divisions: 8,
              label: '${(_rate * 2).toStringAsFixed(1)}x',
              semanticFormatterCallback: (v) =>
                  'Speed ${(v * 2).toStringAsFixed(1)} times',
              onChanged: (v) => setState(() => _rate = v),
              onChangeEnd: (v) => db.setSetting(TtsKeys.rate, v.toString()),
            ),
          ),
          ListTile(
            title: Text('Pitch  ·  ${_pitch.toStringAsFixed(2)}'),
            subtitle: Slider(
              value: _pitch,
              min: 0.5,
              max: 2.0,
              divisions: 6,
              label: _pitch.toStringAsFixed(2),
              semanticFormatterCallback: (v) => 'Pitch ${v.toStringAsFixed(2)}',
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
                  DropdownMenuItem(value: l, child: Text(languageName(l))),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _language = v);
                db.setSetting(TtsKeys.defaultLanguage, v);
              },
            ),
          ),
          const Divider(),
          const SettingsHeader('Voices'),
          if (_voices.isEmpty)
            const ListTile(
              title: Text('No voices reported by the speech engine'),
              subtitle: Text(
                'The system default voice is used for every language',
              ),
            )
          else ...[
            for (final l in chosen)
              ListTile(
                title: Text(languageName(l)),
                subtitle: Text(voiceLabel(_chosen[l]!)),
                onTap: () => unawaited(_pickVoice(l)),
                trailing: IconButton(
                  tooltip: 'Use the default voice',
                  icon: const Icon(Icons.close),
                  onPressed: () => unawaited(_setVoice(l, null)),
                ),
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Add language'),
              onTap: () => unawaited(_addLanguage()),
            ),
            const SettingsFooter(
              'Every other language is read with the phone\'s default voice for it.',
            ),
          ],
        ],
      ),
    );
  }
}

/// Languages by name with a search box; answers with the code picked.
class _LanguagePicker extends StatefulWidget {
  const _LanguagePicker({required this.codes});
  final List<String> codes;

  @override
  State<_LanguagePicker> createState() => _LanguagePickerState();
}

class _LanguagePickerState extends State<_LanguagePicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final shown = [
      for (final c in widget.codes)
        if (q.isEmpty ||
            languageName(c).toLowerCase().contains(q) ||
            c.contains(q))
          c,
    ];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search languages',
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final c in shown)
                      ListTile(
                        title: Text(languageName(c)),
                        onTap: () => Navigator.pop(context, c),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
