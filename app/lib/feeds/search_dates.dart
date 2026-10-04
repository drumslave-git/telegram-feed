import 'package:intl/intl.dart';

/// A span of days a search can be narrowed to, under the words it is offered with.
final class DateSpan {
  const DateSpan(this.label, this.from, this.until);

  /// "Yesterday", "September 12, 2026", "September 2026", "2025".
  final String label;

  /// The first moment of the span, and the first moment after it.
  final DateTime from;
  final DateTime until;

  /// The span in unix seconds, both ends inside it.
  int get minDate => from.millisecondsSinceEpoch ~/ 1000;
  int get maxDate => until.millisecondsSinceEpoch ~/ 1000 - 1;

  @override
  bool operator ==(Object other) =>
      other is DateSpan && other.from == from && other.until == until;
  @override
  int get hashCode => Object.hash(from, until);
}

/// Telegram has no posts older than this.
const _firstYear = 2013;

/// How many years a day or a month without a year is offered for.
const _years = 3;

/// The spans of days the typed [query] may mean, as the official app's search offers
/// them: "today" and "yesterday", a weekday (the last one), a year, a month (of the last
/// years), a day and a month in words or digits ("12 sep", "sep 12", "12.09"), with a
/// year or without. Words are understood in the language of [locale] and in English,
/// from their third letter on. Nothing lies in the future.
List<DateSpan> dateSpans(
  String query, {
  required String today,
  required String yesterday,
  String locale = 'en_US',
  DateTime? now,
}) {
  final q = query.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  if (q.length < 3) return const [];
  final n = now ?? DateTime.now();
  final day0 = DateTime(n.year, n.month, n.day);
  final here = DateFormat.yMMMMd(locale).dateSymbols;
  final english = DateFormat.yMMMMd('en_US').dateSymbols;
  final out = <DateSpan>[];

  DateSpan day(DateTime d, {String? label}) => DateSpan(
    label ?? DateFormat.yMMMMd(locale).format(d),
    d,
    DateTime(d.year, d.month, d.day + 1),
  );
  DateSpan month(int year, int m) => DateSpan(
    DateFormat.yMMMM(locale).format(DateTime(year, m)),
    DateTime(year, m),
    DateTime(year, m + 1),
  );
  bool begins(String word, String typed) =>
      word.toLowerCase().replaceAll('.', '').startsWith(typed);

  /// The month [typed] names, 1 to 12, or 0.
  int monthOf(String typed) {
    if (typed.length < 3) return 0;
    for (final names in [here.MONTHS, here.STANDALONEMONTHS, english.MONTHS]) {
      for (var i = 0; i < 12; i++) {
        if (begins(names[i], typed)) return i + 1;
      }
    }
    return 0;
  }

  bool real(int year, int m, int d) =>
      m >= 1 && m <= 12 && d >= 1 && d <= DateTime(year, m + 1, 0).day;

  /// The day [d] of month [m] in the last years it has come.
  void days(int m, int d) {
    for (var year = n.year; year > n.year - _years - 1; year--) {
      if (out.length >= _years || year < _firstYear) break;
      if (!real(year, m, d)) continue;
      final date = DateTime(year, m, d);
      if (!date.isAfter(day0)) out.add(day(date));
    }
  }

  /// The month [m] in the last years it has begun.
  void months(int m) {
    for (var year = n.year; year >= _firstYear; year--) {
      if (out.length >= _years) break;
      if (!DateTime(year, m).isAfter(day0)) out.add(month(year, m));
    }
  }

  int fullYear(String digits) {
    final y = int.parse(digits);
    return digits.length <= 2 ? 2000 + y : y;
  }

  bool known(int year) => year >= _firstYear && year <= n.year;

  if (begins(today, q) || 'today'.startsWith(q)) {
    out.add(day(day0, label: today));
  }
  if (begins(yesterday, q) || 'yesterday'.startsWith(q)) {
    out.add(day(DateTime(n.year, n.month, n.day - 1), label: yesterday));
  }
  if (out.isNotEmpty) return out;

  // A weekday: the last one, today when it is today.
  for (final names in [
    here.WEEKDAYS,
    here.STANDALONEWEEKDAYS,
    english.WEEKDAYS,
  ]) {
    for (var i = 0; i < 7; i++) {
      if (!begins(names[i], q)) continue;
      // The names start at Sunday; DateTime counts Monday as 1 and Sunday as 7.
      final weekday = i == 0 ? 7 : i;
      final back = (n.weekday - weekday) % 7;
      final d = DateTime(n.year, n.month, n.day - back);
      return [day(d, label: DateFormat.MMMMEEEEd(locale).format(d))];
    }
  }

  RegExpMatch? m;
  // A year.
  if (RegExp(r'^\d{4}$').hasMatch(q)) {
    final year = int.parse(q);
    if (!known(year)) return const [];
    return [DateSpan(q, DateTime(year), DateTime(year + 1))];
  }
  // A month.
  if (RegExp(r'^[^\d\s]+$').hasMatch(q)) {
    final mo = monthOf(q);
    if (mo != 0) months(mo);
    return out;
  }
  // "September 2025", "2025 September".
  m =
      RegExp(r'^([^\d\s]+) (\d{4})$').firstMatch(q) ??
      RegExp(r'^(\d{4}) ([^\d\s]+)$').firstMatch(q);
  if (m != null) {
    final first = m.group(1)!;
    final wordFirst = !RegExp(r'^\d').hasMatch(first);
    final mo = monthOf(wordFirst ? first : m.group(2)!);
    final year = int.parse(wordFirst ? m.group(2)! : first);
    if (mo != 0 && known(year) && !DateTime(year, mo).isAfter(day0)) {
      out.add(month(year, mo));
    }
    return out;
  }
  // "12 September", "September 12", with a year or without.
  m =
      RegExp(r'^(\d{1,2}) ([^\d\s]+)(?: (\d{4}))?$').firstMatch(q) ??
      RegExp(r'^([^\d\s]+) (\d{1,2})(?:,? (\d{4}))?$').firstMatch(q);
  if (m != null) {
    final first = m.group(1)!;
    final wordFirst = !RegExp(r'^\d').hasMatch(first);
    final mo = monthOf(wordFirst ? first : m.group(2)!);
    final d = int.parse(wordFirst ? m.group(2)! : first);
    if (mo == 0) return out;
    final year = m.group(3);
    if (year == null) {
      days(mo, d);
    } else {
      final y = int.parse(year);
      if (known(y) && real(y, mo, d) && !DateTime(y, mo, d).isAfter(day0)) {
        out.add(day(DateTime(y, mo, d)));
      }
    }
    return out;
  }
  // "12.09.2025", "12/09/25".
  m = RegExp(r'^(\d{1,2})[./\- ](\d{1,2})[./\- ](\d{2}|\d{4})$').firstMatch(q);
  if (m != null) {
    final d = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    final y = fullYear(m.group(3)!);
    if (known(y) && real(y, mo, d) && !DateTime(y, mo, d).isAfter(day0)) {
      out.add(day(DateTime(y, mo, d)));
    }
    return out;
  }
  // "09.2025": a month.
  m = RegExp(r'^(\d{1,2})[./\- ](\d{4})$').firstMatch(q);
  if (m != null) {
    final mo = int.parse(m.group(1)!);
    final y = int.parse(m.group(2)!);
    if (mo >= 1 && mo <= 12 && known(y) && !DateTime(y, mo).isAfter(day0)) {
      out.add(month(y, mo));
    }
    return out;
  }
  // "12.09": a day and a month.
  m = RegExp(r'^(\d{1,2})[./\-](\d{1,2})$').firstMatch(q);
  if (m != null) days(int.parse(m.group(2)!), int.parse(m.group(1)!));
  return out;
}
