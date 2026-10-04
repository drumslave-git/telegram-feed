import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../app_name.dart';
import '../l10n/l10n.dart';
import '../widgets/error_state.dart';
import 'login_screens.dart' show OtherAccountButton;

/// Writes the digits of a phone number the way its country does, as Telegram's
/// [PhoneInfo.formatted] shows it: every `-` of [template] takes a digit, what stands
/// between them is kept, and digits beyond the template follow at the end. Nothing is
/// written after the last digit.
String formatPhoneDigits(String digits, String template) {
  final out = StringBuffer();
  var used = 0;
  for (final unit in template.split('')) {
    if (used >= digits.length) break;
    out.write(_takesDigit(unit) ? digits[used++] : unit);
  }
  out.write(digits.substring(used));
  return out.toString().trimRight();
}

bool _takesDigit(String unit) =>
    unit == '-' || (unit.compareTo('0') >= 0 && unit.compareTo('9') <= 0);

String _digitsOf(String text) => text.replaceAll(RegExp(r'\D'), '');

/// Keeps the number field written as its country writes numbers while it is typed in.
/// The [template] is what Telegram last said of the number; it is asked for again after
/// every change, since the way a number is written can depend on how it begins.
class PhoneNumberFormatter extends TextInputFormatter {
  String template = '';

  TextEditingValue format(TextEditingValue value) {
    final digits = _digitsOf(value.text);
    final text = formatPhoneDigits(digits, template);
    // The cursor stays after the digit it stood after.
    final end = value.selection.baseOffset.clamp(0, value.text.length);
    final before = _digitsOf(value.text.substring(0, end)).length;
    var at = 0;
    for (var seen = 0; at < text.length && seen < before; at++) {
      if (RegExp(r'\d').hasMatch(text[at])) seen++;
    }
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: at),
    );
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) =>
      // A number pasted with its plus is taken apart by the screen, not written here.
      newValue.text.trimLeft().startsWith('+') ? newValue : format(newValue);
}

/// The first step of the login, as in the official app: the country, its calling code
/// and the number in fields of their own, the number written as the country writes it,
/// and a question whether the number is right before the code is sent.
class PhoneScreen extends StatefulWidget {
  const PhoneScreen({super.key, required this.gateway});
  final TelegramGateway gateway;

  @override
  State<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends State<PhoneScreen> {
  final _code = TextEditingController();
  final _number = TextEditingController();
  final _numberFocus = FocusNode();
  final _format = PhoneNumberFormatter();

  List<Country> _countries = const [];
  String? _language;

  /// The country of the calling code; null while the code is none's.
  Country? _country;

  /// How the country writes a number, digits as zeros: the number field's hint.
  String _hint = '';
  String? _error;
  bool _busy = false;

  /// Counts the questions asked of Telegram, so a late answer does not undo a newer one.
  int _asked = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final language = Localizations.localeOf(context).languageCode;
    if (language == _language) return;
    _language = language;
    unawaited(_loadCountries(language));
  }

  @override
  void dispose() {
    _code.dispose();
    _number.dispose();
    _numberFocus.dispose();
    super.dispose();
  }

  Future<void> _loadCountries(String language) async {
    try {
      final countries = await widget.gateway.countries(language: language);
      if (!mounted || language != _language) return;
      countries.sort((a, b) => a.name.compareTo(b.name));
      setState(() {
        _countries = countries;
        // Named again in the new language.
        final chosen = _country;
        if (chosen != null) {
          _country = countries.where((c) => c.code == chosen.code).firstOrNull;
        }
      });
      if (_code.text.isEmpty) _preselect();
    } on Object catch (e) {
      // No list: the code and the number can still be typed.
      debugPrint('login: countries not loaded: $e');
    }
  }

  /// The country of the phone's region, as the official app starts with the SIM's.
  void _preselect() {
    final region = WidgetsBinding.instance.platformDispatcher.locale.countryCode
        ?.toUpperCase();
    final home = _countries.where((c) => c.code == region).firstOrNull;
    if (home != null && home.callingCodes.isNotEmpty) _choose(home);
  }

  void _choose(Country country) {
    setState(() {
      _country = country;
      _error = null;
    });
    _code.text = country.callingCodes.first;
    unawaited(_follow());
    _numberFocus.requestFocus();
  }

  Future<void> _pickCountry() async {
    final picked = await Navigator.of(context).push<Country>(
      MaterialPageRoute(builder: (_) => CountryPicker(countries: _countries)),
    );
    if (picked != null && mounted) _choose(picked);
  }

  /// The code field changed. More digits than a calling code has are the number's:
  /// a whole number typed or pasted into this field is taken apart.
  void _onCode(String text) {
    final digits = _digitsOf(text);
    if (digits != text) {
      _code.value = TextEditingValue(
        text: digits,
        selection: TextSelection.collapsed(offset: digits.length),
      );
    }
    if (digits.length > 4) {
      unawaited(_takeApart(digits + _digitsOf(_number.text)));
      return;
    }
    setState(() => _error = null);
    unawaited(_follow());
  }

  void _onNumber(String text) {
    if (text.trimLeft().startsWith('+')) {
      // A whole number, pasted or typed with its plus. The plus alone says nothing yet.
      final digits = _digitsOf(text);
      if (digits.isNotEmpty) unawaited(_takeApart(digits, typed: true));
      return;
    }
    if (_error != null) setState(() => _error = null);
    unawaited(_follow());
  }

  /// Splits a whole number into the calling code and the rest, as Telegram reads it. A
  /// number [typed] with its plus stays as it is typed until its first digits are a
  /// country's calling code.
  Future<void> _takeApart(String digits, {bool typed = false}) async {
    final asked = ++_asked;
    PhoneInfo? info;
    try {
      info = await widget.gateway.phoneInfo(digits);
    } on Object catch (e) {
      debugPrint('login: number not read: $e');
    }
    if (!mounted || asked != _asked) return;
    final code = info?.callingCode ?? '';
    if (code.isEmpty || !digits.startsWith(code)) {
      if (typed) return;
      // Not a number Telegram knows the country of: the fields keep what fits.
      _code.text = digits.substring(0, digits.length.clamp(0, 4));
      _setNumber(digits.substring(_code.text.length));
    } else {
      _code.text = code;
      _setNumber(digits.substring(code.length));
    }
    _numberFocus.requestFocus();
    await _follow();
  }

  void _setNumber(String digits) {
    final text = formatPhoneDigits(digits, _format.template);
    _number.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  /// Asks Telegram about the number as it stands: whose calling code it has and how the
  /// rest is written. The country row, the hint and the number's writing follow.
  Future<void> _follow() async {
    final asked = ++_asked;
    final code = _code.text;
    final digits = _digitsOf(_number.text);
    if (code.isEmpty) {
      setState(() {
        _country = null;
        _hint = '';
      });
      return;
    }
    PhoneInfo info;
    try {
      info = await widget.gateway.phoneInfo('$code$digits');
    } on Object catch (e) {
      debugPrint('login: number not read: $e');
      return;
    }
    if (!mounted || asked != _asked) return;
    final known = info.callingCode == code;
    _format.template = known ? info.formatted : '';
    final formatted = _format.format(_number.value);
    if (formatted.text != _number.text) _number.value = formatted;
    setState(() {
      // A code shared by several countries keeps the one that was picked.
      final picked = _country;
      _country = !known
          ? null
          : picked != null && picked.callingCodes.contains(code)
          ? picked
          : _countries.where((c) => c.code == info.countryCode).firstOrNull ??
                _countries
                    .where((c) => c.callingCodes.contains(code))
                    .firstOrNull;
      _hint = !known
          ? ''
          : digits.isEmpty
          ? info.formatted.replaceAll('-', '0')
          : _hint;
    });
  }

  String get _fullNumber => '+${_code.text}${_digitsOf(_number.text)}';

  Future<void> _submit() async {
    final l10n = context.l10n;
    if (_code.text.isEmpty) {
      setState(() => _error = l10n.loginChooseCountry);
      return;
    }
    if (_number.text.trimLeft().startsWith('+')) {
      // Typed with a plus, and its first digits are no country's code.
      setState(() => _error = l10n.loginInvalidCountryCode);
      return;
    }
    if (_digitsOf(_number.text).isEmpty) return;
    // As the official app asks before it sends a code to a number.
    final right = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('+${_code.text} ${_number.text}'),
        content: Text(l10n.loginCorrectNumber),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.loginEditNumber),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.loginYes),
          ),
        ],
      ),
    );
    if (!(right ?? false) || !mounted) {
      if (mounted) _numberFocus.requestFocus();
      return;
    }
    await _guard(() => widget.gateway.setPhoneNumber(_fullNumber));
  }

  Future<void> _guard(Future<void> Function() action) async {
    final l10n = context.l10n;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on TelegramException catch (e) {
      if (!mounted) return;
      setState(
        () => _error = telegramErrorLine(
          e,
          what: l10n.loginTelegramRefused,
          l10n: l10n,
        ),
      );
    } on Object catch (e) {
      debugPrint('login: $e');
      if (mounted) setState(() => _error = l10n.loginSomethingWentWrong);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final country = _country;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.loginPhoneTitle)),
      // Scrolls, so the keyboard never pushes the buttons off a small screen.
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(l10n.loginPhoneExplanation(appName)),
          const SizedBox(height: 16),
          InkWell(
            onTap: _busy ? null : _pickCountry,
            borderRadius: BorderRadius.circular(4),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: l10n.loginCountry,
                border: const OutlineInputBorder(),
                suffixIcon: const Icon(Icons.arrow_drop_down),
              ),
              child: Text(
                country != null
                    ? '${country.flag} ${country.name}'.trim()
                    : _code.text.isEmpty
                    ? l10n.loginChooseCountry
                    : l10n.loginInvalidCountryCode,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 96,
                child: TextField(
                  controller: _code,
                  enabled: !_busy,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: l10n.loginCountryCode,
                    prefixText: '+',
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: _onCode,
                  onSubmitted: (_) => _numberFocus.requestFocus(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _number,
                  focusNode: _numberFocus,
                  autofocus: true,
                  enabled: !_busy,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [_format],
                  decoration: InputDecoration(
                    labelText: l10n.loginPhoneNumber,
                    hintText: _hint.isEmpty ? null : _hint,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: _onNumber,
                  onSubmitted: (_) => _submit(),
                ),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _submit,
            // Telegram can take a few seconds; the button shows it is working.
            child: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.loginSendCode),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => _guard(widget.gateway.requestQrCode),
            icon: const Icon(Icons.qr_code),
            label: Text(l10n.loginWithQrInstead),
          ),
          const OtherAccountButton(),
        ],
      ),
    );
  }
}

/// The list of countries with a search, as the official app's: a tap gives the country
/// back. Found by name, and by calling code with or without its plus.
class CountryPicker extends StatefulWidget {
  const CountryPicker({super.key, required this.countries});
  final List<Country> countries;

  @override
  State<CountryPicker> createState() => _CountryPickerState();
}

class _CountryPickerState extends State<CountryPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final words = _query.trim().toLowerCase();
    final digits = _digitsOf(words);
    final found = [
      for (final c in widget.countries)
        if (words.isEmpty ||
            c.name.toLowerCase().contains(words) ||
            (digits.isNotEmpty &&
                c.callingCodes.any((code) => code.startsWith(digits))))
          c,
    ];
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          decoration: InputDecoration(
            hintText: l10n.loginChooseCountry,
            border: InputBorder.none,
          ),
          onChanged: (q) => setState(() => _query = q),
        ),
      ),
      body: found.isEmpty
          ? Center(child: Text(l10n.loginNoCountryFound))
          : ListView.builder(
              itemCount: found.length,
              itemBuilder: (context, i) {
                final c = found[i];
                return ListTile(
                  leading: Text(c.flag, style: const TextStyle(fontSize: 24)),
                  title: Text(c.name),
                  trailing: Text(
                    '+${c.callingCodes.join(', +')}',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  onTap: () => Navigator.pop(context, c),
                );
              },
            ),
    );
  }
}
