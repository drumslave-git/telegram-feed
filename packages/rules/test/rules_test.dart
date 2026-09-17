import 'dart:convert';

import 'package:rules/rules.dart';
import 'package:test/test.dart';

void main() {
  group('parser', () {
    test('precedence: AND binds tighter than OR, NOT tightest', () {
      expect(
        RuleParser.parse('a OR b AND NOT c'),
        const Or([
          Term('a'),
          And([Term('b'), Not(Term('c'))]),
        ]),
      );
    });

    test('parentheses, quotes, modifiers, keyword case', () {
      expect(
        RuleParser.parse('("bitcoin" or btc) and not ~=Air'),
        const And([
          Or([Term('bitcoin'), Term('btc')]),
          Not(Term('Air', wholeWord: false, caseSensitive: true)),
        ]),
      );
      expect(
        RuleParser.parse(r'"say \"hi\" \\ now"'),
        const Term(r'say "hi" \ now'),
      );
      expect(RuleParser.parse('"two words"'), const Term('two words'));
    });

    test('errors', () {
      expect(() => RuleParser.parse(''), throwsFormatException);
      expect(() => RuleParser.parse('(a OR b'), throwsFormatException);
      expect(() => RuleParser.parse('a b'), throwsFormatException);
      expect(() => RuleParser.parse('AND'), throwsFormatException);
      expect(() => RuleParser.parse('"unterminated'), throwsFormatException);
      expect(() => RuleParser.parse('""'), throwsFormatException);
    });

    test('format round-trips', () {
      for (final src in [
        'a OR b AND NOT c',
        '(a OR b) AND NOT c',
        '~coin AND =BTC AND ~="Mixed Case"',
        '"a phrase" OR word',
        'NOT (a AND b)',
        '"and"',
      ]) {
        final e = RuleParser.parse(src);
        expect(RuleParser.parse(RuleParser.format(e)), e, reason: src);
      }
      expect(
        RuleParser.format(RuleParser.parse('(a OR b) AND NOT c')),
        '(a OR b) AND NOT c',
      );
    });
  });

  group('json', () {
    test('round-trips through condition_json', () {
      final e = RuleParser.parse('(a OR ~b) AND NOT ="C d"');
      final json = jsonEncode(e.toJson());
      expect(Expr.fromJson(jsonDecode(json) as Map<Object?, Object?>), e);
      expect(() => Expr.fromJson({'nope': 1}), throwsFormatException);
    });
  });

  group('evaluator', () {
    final ev = RuleEvaluator();
    bool m(String rule, String text) =>
        ev.matches(RuleParser.parse(rule), text);

    test('whole words, substrings, case', () {
      expect(m('btc', 'Buy BTC now'), isTrue);
      expect(m('btc', 'altbtcoin'), isFalse);
      expect(m('~btc', 'altbtcoin'), isTrue);
      expect(m('=BTC', 'buy btc'), isFalse);
      expect(m('=BTC', 'buy BTC'), isTrue);
      expect(m('coin', 'coin.'), isTrue); // punctuation is a boundary
      expect(m('coin', 'coin_x'), isFalse); // underscore is a word character
    });

    test('phrases match across whitespace runs', () {
      expect(m('"rate cut"', 'A rate\n  cut is coming'), isTrue);
      expect(m('"rate cut"', 'rate-cut'), isFalse);
    });

    test('Unicode word boundaries and Cyrillic case folding', () {
      expect(m('курс', 'Новый курс рубля'), isTrue);
      expect(
        m('курс', 'Новый КУРС рубля'),
        isTrue,
      ); // case-insensitive Cyrillic
      expect(m('курс', 'экскурсия'), isFalse); // inside a Cyrillic word
      expect(m('~курс', 'экскурсия'), isTrue);
      expect(m('=Курс', 'курс'), isFalse);
      expect(m('ünal', 'Ünal geldi'), isTrue);
      expect(
        m('nal', 'Ünal geldi'),
        isFalse,
      ); // ü is a letter, so no boundary before "nal"
      expect(m('币', '比特币涨了'), isFalse); // CJK: no boundary inside the word
      expect(m('~币', '比特币涨了'), isTrue);
      expect(m('😀', 'hi 😀 there'), isTrue);
    });

    test('boolean structure', () {
      expect(m('(bitcoin OR btc) AND NOT airdrop', 'BTC pumps'), isTrue);
      expect(m('(bitcoin OR btc) AND NOT airdrop', 'btc airdrop!'), isFalse);
      expect(m('NOT (a AND b)', 'a only'), isTrue);
      expect(m('NOT (a AND b)', 'a and b'), isFalse);
    });
  });

  group('schedule', () {
    DateTime at(int weekday, String hhmm) {
      // 2026-09-14 is a Monday.
      final t = Schedule.parseTime(hhmm);
      return DateTime(2026, 9, 14 + weekday - 1, t ~/ 60, t % 60);
    }

    test('simple window and weekdays', () {
      final s = Schedule(
        weekdays: {1, 2, 3, 4, 5},
        from: Schedule.parseTime('09:00'),
        to: Schedule.parseTime('18:00'),
      );
      expect(s.isActive(at(1, '09:00')), isTrue);
      expect(s.isActive(at(1, '17:59')), isTrue);
      expect(s.isActive(at(1, '18:00')), isFalse);
      expect(s.isActive(at(6, '12:00')), isFalse);
    });

    test('wraps past midnight: weekday is the start day', () {
      final s = Schedule(
        weekdays: {5},
        from: Schedule.parseTime('22:00'),
        to: Schedule.parseTime('02:00'),
      );
      expect(s.isActive(at(5, '23:30')), isTrue);
      expect(
        s.isActive(at(6, '01:30')),
        isTrue,
      ); // Saturday 01:30 belongs to Friday's window
      expect(s.isActive(at(6, '02:00')), isFalse);
      expect(s.isActive(at(6, '23:30')), isFalse);
      expect(s.isActive(at(1, '00:30')), isFalse);
      final sun = Schedule(
        weekdays: {7},
        from: Schedule.parseTime('23:00'),
        to: Schedule.parseTime('01:00'),
      );
      expect(
        sun.isActive(at(1, '00:30')),
        isTrue,
      ); // Monday 00:30 from Sunday's window
    });

    test('whole day, json, time parsing', () {
      final s = Schedule(weekdays: {3}, from: 0, to: 0);
      expect(s.isActive(at(3, '00:00')), isTrue);
      expect(s.isActive(at(4, '00:00')), isFalse);
      expect(Schedule.fromJson(s.toJson()), s);
      expect(s.toJson(), {
        'weekdays': [3],
        'from': '00:00',
        'to': '00:00',
      });
      expect(() => Schedule.parseTime('25:00'), throwsFormatException);
      expect(() => Schedule.parseTime('9'), throwsFormatException);
    });
  });
}
