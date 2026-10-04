import 'package:telegram_gateway/telegram_gateway.dart';

/// A handful of countries for the scripted gateways: what the login screen lists, and how
/// each writes a number after its calling code (`-` for a digit).
const _countries = [
  (
    code: 'FR',
    en: 'France',
    uk: 'Франція',
    calling: '33',
    pattern: '- -- -- -- --',
  ),
  (
    code: 'DE',
    en: 'Germany',
    uk: 'Німеччина',
    calling: '49',
    pattern: '---- -------',
  ),
  (
    code: 'IT',
    en: 'Italy',
    uk: 'Італія',
    calling: '39',
    pattern: '--- --- ----',
  ),
  (
    code: 'PL',
    en: 'Poland',
    uk: 'Польща',
    calling: '48',
    pattern: '--- --- ---',
  ),
  (
    code: 'ES',
    en: 'Spain',
    uk: 'Іспанія',
    calling: '34',
    pattern: '--- --- ---',
  ),
  (
    code: 'UA',
    en: 'Ukraine',
    uk: 'Україна',
    calling: '380',
    pattern: '-- --- ----',
  ),
  (
    code: 'GB',
    en: 'United Kingdom',
    uk: 'Велика Британія',
    calling: '44',
    pattern: '---- ------',
  ),
  (
    code: 'US',
    en: 'United States',
    uk: 'Сполучені Штати',
    calling: '1',
    pattern: '--- --- ----',
  ),
];

/// The flag of a country as an emoji: its two letters as regional indicators.
String _flag(String code) => String.fromCharCodes([
  for (final unit in code.codeUnits) 0x1F1E6 + unit - 0x41,
]);

/// The countries the scripted gateways know, named in [language].
List<Country> fakeCountries({String language = 'en'}) => [
  for (final c in _countries)
    Country(
      code: c.code,
      name: language == 'uk' ? c.uk : c.en,
      flag: _flag(c.code),
      callingCodes: [c.calling],
    ),
];

/// What a scripted gateway makes of [digits]: the country whose calling code they start
/// with, and the rest written in its pattern, with `-` for the digits still expected and
/// further digits added at the end.
PhoneInfo fakePhoneInfo(String digits) {
  for (final c in _countries) {
    if (!digits.startsWith(c.calling)) continue;
    final rest = digits.substring(c.calling.length);
    final out = StringBuffer();
    var used = 0;
    for (final unit in c.pattern.split('')) {
      out.write(unit == '-' && used < rest.length ? rest[used++] : unit);
    }
    if (used < rest.length) out.write(rest.substring(used));
    return PhoneInfo(
      countryCode: c.code,
      callingCode: c.calling,
      formatted: out.toString(),
    );
  }
  return PhoneInfo(callingCode: '', formatted: digits);
}
