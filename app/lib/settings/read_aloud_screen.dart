import 'dart:async';
import 'dart:convert';

import 'package:app_db/app_db.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
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

/// The languages speech engines offer whose names the app has, by ISO 639 code
/// (`AppLocalizations.languageName`).
const _namedLanguages = <String>{
  'af',
  'am',
  'ar',
  'as',
  'az',
  'be',
  'bg',
  'bn',
  'brx',
  'bs',
  'ca',
  'cmn',
  'cs',
  'cy',
  'da',
  'de',
  'doi',
  'el',
  'en',
  'es',
  'et',
  'eu',
  'fa',
  'fi',
  'fil',
  'fr',
  'ga',
  'gl',
  'gu',
  'he',
  'hi',
  'hr',
  'hu',
  'hy',
  'id',
  'is',
  'it',
  'ja',
  'jv',
  'ka',
  'kk',
  'km',
  'kn',
  'ko',
  'kok',
  'ks',
  'ky',
  'lo',
  'lt',
  'lv',
  'mai',
  'mk',
  'ml',
  'mn',
  'mni',
  'mr',
  'ms',
  'my',
  'nb',
  'ne',
  'nl',
  'no',
  'or',
  'pa',
  'pl',
  'pt',
  'ro',
  'ru',
  'sa',
  'sat',
  'sd',
  'si',
  'sk',
  'sl',
  'sq',
  'sr',
  'su',
  'sv',
  'sw',
  'ta',
  'te',
  'th',
  'tr',
  'uk',
  'ur',
  'uz',
  'vi',
  'yue',
  'zh',
  'zu',
};

/// The language's name, or its code where the app has none.
String languageName(String code, AppLocalizations l10n) {
  final known = code.toLowerCase();
  return _namedLanguages.contains(known)
      ? l10n.languageName(known)
      : code.toUpperCase();
}

/// Language codes in the alphabetical order of their names.
List<String> _byLanguageName(Iterable<String> codes, AppLocalizations l10n) {
  final keys = {for (final c in codes) c: _sortKey(languageName(c, l10n))};
  return keys.keys.toList()..sort((a, b) => keys[a]!.compareTo(keys[b]!));
}

const _ukrainianUpper = 'АБВГҐДЕЄЖЗИІЇЙКЛМНОПРСТУФХЦЧШЩЬЮЯ';
const _ukrainianLower = 'абвгґдеєжзиіїйклмнопрстуфхцчшщьюя';

/// A name whose Ukrainian letters are moved into alphabet order: by code point Є, І and Ї
/// come before А and Ґ after Я. The apostrophe ʼ does not count, as in a dictionary.
/// Other characters keep their code points.
String _sortKey(String name) => String.fromCharCodes([
  for (final r in name.runes)
    if (r != 0x02BC) _sortRune(r),
]);

int _sortRune(int rune) {
  final c = String.fromCharCode(rune);
  final upper = _ukrainianUpper.indexOf(c);
  if (upper >= 0) return 0xE000 + upper;
  final lower = _ukrainianLower.indexOf(c);
  return lower >= 0 ? 0xE040 + lower : rune;
}

/// A voice as a person reads it: "Female 1 · US", "Voice SFG · GB · online". Engines name
/// voices like `en-us-x-sfg#female_1-local`.
String voiceLabel(Map<String, String> voice, AppLocalizations l10n) {
  final name = voice['name'] ?? '';
  final locale = voice['locale'] ?? '';
  final parts = locale.split(RegExp('[-_]'));
  final region = parts.length > 1 ? parts[1].toUpperCase() : '';
  final tail = name.contains('-x-') ? name.split('-x-').last : name;
  final hash = tail.split('#');
  String who;
  if (hash.length > 1) {
    final g = hash[1].split('-').first.split('_');
    final kind = switch (g.first) {
      'female' => l10n.readAloudVoiceFemale,
      'male' => l10n.readAloudVoiceMale,
      final other => '${other[0].toUpperCase()}${other.substring(1)}',
    };
    who = '$kind${g.length > 1 ? ' ${g[1]}' : ''}';
  } else {
    final id = tail.split('-').first;
    who = id.isEmpty ? name : l10n.readAloudVoiceId(id.toUpperCase());
  }
  final online = name.endsWith('-network') ? l10n.readAloudVoiceOnline : '';
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
    for (final l in _languageCodes) {
      final json = await db.setting(TtsKeys.voiceFor(l));
      if (json == null || json.isEmpty) continue;
      _chosen[l] = (jsonDecode(json) as Map).cast<String, String>();
    }
    if (mounted) setState(() => _loaded = true);
  }

  /// Languages the engine has voices for, plus the current default.
  Set<String> get _languageCodes {
    final codes = <String>{_language};
    for (final v in _voices) {
      final locale = v['locale'] ?? '';
      if (locale.isNotEmpty) {
        codes.add(locale.split(RegExp('[-_]')).first.toLowerCase());
      }
    }
    return codes;
  }

  /// The same languages, by name.
  List<String> _languages(AppLocalizations l10n) =>
      _byLanguageName(_languageCodes, l10n);

  List<Map<String, String>> _voicesFor(String language) => [
    for (final v in _voices)
      if ((v['locale'] ?? '').toLowerCase().startsWith(language.toLowerCase()))
        v,
  ];

  Future<void> _preview() async {
    // The sample in the language it is spoken in where the app has that language.
    final strings = AppLanguage.stringsOfLanguage(_language) ?? context.l10n;
    await widget.preview(
      text: strings.readAloudPreviewText,
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
    final l10n = context.l10n;
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
                  languageName(language, l10n),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ListTile(
                leading: Icon(
                  current == null ? Icons.check : null,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: Text(l10n.readAloudPhoneDefaultVoice),
                onTap: () => Navigator.pop(context, const <String, String>{}),
              ),
              for (final v in _voicesFor(language))
                ListTile(
                  leading: Icon(
                    v['name'] == current ? Icons.check : null,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(voiceLabel(v, l10n)),
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
      for (final l in _languages(context.l10n))
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
    final l10n = context.l10n;
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.readAloudTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final db = widget.db;
    final chosen = _byLanguageName(_chosen.keys, l10n);
    final languages = _languages(l10n);
    final speed = NumberFormat('0.0', l10n.localeName);
    final pitch = NumberFormat('0.00', l10n.localeName);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.readAloudTitle),
        actions: [
          IconButton(
            tooltip: l10n.readAloudPreview,
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
            title: Text(l10n.readAloudSpeed(speed.format(_rate * 2))),
            subtitle: Slider(
              value: _rate,
              min: 0.2,
              max: 1.0,
              divisions: 8,
              label: '${speed.format(_rate * 2)}x',
              semanticFormatterCallback: (v) =>
                  l10n.readAloudSpeedSemantics(speed.format(v * 2)),
              onChanged: (v) => setState(() => _rate = v),
              onChangeEnd: (v) => db.setSetting(TtsKeys.rate, v.toString()),
            ),
          ),
          ListTile(
            title: Text(l10n.readAloudPitch(pitch.format(_pitch))),
            subtitle: Slider(
              value: _pitch,
              min: 0.5,
              max: 2.0,
              divisions: 6,
              label: pitch.format(_pitch),
              semanticFormatterCallback: (v) =>
                  l10n.readAloudPitchSemantics(pitch.format(v)),
              onChanged: (v) => setState(() => _pitch = v),
              onChangeEnd: (v) => db.setSetting(TtsKeys.pitch, v.toString()),
            ),
          ),
          ListTile(
            title: Text(l10n.readAloudMaxLength),
            subtitle: Text(l10n.readAloudMaxLengthSubtitle(_maxChars)),
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
            title: Text(l10n.readAloudDefaultLanguage),
            subtitle: Text(l10n.readAloudDefaultLanguageSubtitle),
            trailing: DropdownButton<String>(
              value: _language,
              items: [
                for (final l in languages)
                  DropdownMenuItem(
                    value: l,
                    child: Text(languageName(l, l10n)),
                  ),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _language = v);
                db.setSetting(TtsKeys.defaultLanguage, v);
              },
            ),
          ),
          const Divider(),
          SettingsHeader(l10n.readAloudVoices),
          if (_voices.isEmpty)
            ListTile(
              title: Text(l10n.readAloudNoVoices),
              subtitle: Text(l10n.readAloudNoVoicesSubtitle),
            )
          else ...[
            for (final l in chosen)
              ListTile(
                title: Text(languageName(l, l10n)),
                subtitle: Text(voiceLabel(_chosen[l]!, l10n)),
                onTap: () => unawaited(_pickVoice(l)),
                trailing: IconButton(
                  tooltip: l10n.readAloudUseDefaultVoice,
                  icon: const Icon(Icons.close),
                  onPressed: () => unawaited(_setVoice(l, null)),
                ),
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: Text(l10n.readAloudAddLanguage),
              onTap: () => unawaited(_addLanguage()),
            ),
            SettingsFooter(l10n.readAloudOtherLanguagesFooter),
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
    final l10n = context.l10n;
    final q = _query.trim().toLowerCase();
    final shown = [
      for (final c in widget.codes)
        if (q.isEmpty ||
            languageName(c, l10n).toLowerCase().contains(q) ||
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
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: l10n.readAloudSearchLanguages,
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
                        title: Text(languageName(c, l10n)),
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
