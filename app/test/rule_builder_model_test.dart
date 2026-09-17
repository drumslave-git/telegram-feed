import 'package:flutter_test/flutter_test.dart';
import 'package:rules/rules.dart';
import 'package:telegram_feed/rules/rule_builder_model.dart';

void main() {
  test('round-trips OR-of-AND shapes with negation and modifiers', () {
    for (final src in [
      'btc',
      'NOT btc',
      'a AND ~b',
      'a OR b',
      '(a AND NOT =b) OR c OR (d AND e AND "f g")',
    ]) {
      final e = RuleParser.parse(src);
      final m = BuilderModel.fromExpr(e);
      expect(m, isNotNull, reason: src);
      expect(m!.toExpr(), e, reason: src);
      expect(m.isValid, isTrue);
    }
  });

  test('deeper nesting is not representable', () {
    expect(BuilderModel.fromExpr(RuleParser.parse('NOT (a AND b)')), isNull);
    expect(BuilderModel.fromExpr(RuleParser.parse('a AND (b OR c)')), isNull);
  });

  test('validity and single-term simplification', () {
    expect(BuilderModel.empty.isValid, isFalse);
    const m = BuilderModel([
      [BuilderTerm(text: ' btc ', negated: true)],
    ]);
    expect(m.toExpr(), const Not(Term('btc')));
    expect(RuleParser.format(m.toExpr()), 'NOT btc');
  });
}
