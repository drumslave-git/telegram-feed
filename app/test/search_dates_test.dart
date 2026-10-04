import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/search_dates.dart';

void main() {
  // A Sunday.
  final now = DateTime(2026, 10, 4, 15);

  List<DateSpan> spans(String query) =>
      dateSpans(query, today: 'Today', yesterday: 'Yesterday', now: now);
  List<String> labels(String query) => [for (final s in spans(query)) s.label];

  test('today and yesterday, from their third letter', () {
    expect(labels('to'), isEmpty);
    expect(labels('tod'), ['Today']);
    expect(labels('Yesterday'), ['Yesterday']);
    final y = spans('yest').single;
    expect(y.from, DateTime(2026, 10, 3));
    expect(y.until, DateTime(2026, 10, 4));
    // Both ends are inside the span.
    expect(y.maxDate - y.minDate, 24 * 3600 - 1);
  });

  test('a weekday is the last one, today when it is today', () {
    expect(spans('friday').single.from, DateTime(2026, 10, 2));
    expect(spans('sun').single.from, DateTime(2026, 10, 4));
    expect(spans('mon').single.from, DateTime(2026, 9, 28));
    expect(labels('friday'), ['Friday, October 2']);
  });

  test('a year is the whole year, when Telegram had it and it has begun', () {
    final y = spans('2025').single;
    expect(y.label, '2025');
    expect(y.from, DateTime(2025));
    expect(y.until, DateTime(2026));
    expect(spans('2012'), isEmpty);
    expect(spans('2027'), isEmpty);
  });

  test('a month is offered for the last years it has begun', () {
    expect(labels('sep'), [
      'September 2026',
      'September 2025',
      'September 2024',
    ]);
    // November has not begun this year.
    expect(labels('november'), [
      'November 2025',
      'November 2024',
      'November 2023',
    ]);
    final s = spans('sept 2024').single;
    expect(s.label, 'September 2024');
    expect(s.from, DateTime(2024, 9));
    expect(s.until, DateTime(2024, 10));
    expect(labels('2024 sept'), ['September 2024']);
    expect(labels('09.2024'), ['September 2024']);
  });

  test('a day and a month, in words or digits, with a year or without', () {
    expect(labels('12 sep'), [
      'September 12, 2026',
      'September 12, 2025',
      'September 12, 2024',
    ]);
    expect(labels('sep 12'), labels('12 sep'));
    expect(labels('12.09'), labels('12 sep'));
    // A day that has not come this year starts at the last one.
    expect(labels('24 dec').first, 'December 24, 2025');
    expect(labels('12 sep 2021'), ['September 12, 2021']);
    expect(labels('sep 12, 2021'), ['September 12, 2021']);
    expect(labels('12.09.2021'), ['September 12, 2021']);
    expect(labels('12/09/21'), ['September 12, 2021']);
    final d = spans('12.09.2021').single;
    expect(d.from, DateTime(2021, 9, 12));
    expect(d.until, DateTime(2021, 9, 13));
  });

  test('what is no date offers nothing', () {
    expect(spans('pier'), isEmpty);
    expect(spans('31 feb'), isEmpty);
    expect(spans('40.09'), isEmpty);
    expect(spans('12 sep 2031'), isEmpty);
    expect(spans('rain in september'), isEmpty);
    // The 29th of February: only the years that had one.
    expect(labels('29 feb'), ['February 29, 2024']);
  });
}
