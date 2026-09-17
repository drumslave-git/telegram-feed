import 'ast.dart';

/// Matches conditions against plain post text (message text or caption; nothing else).
final class RuleEvaluator {
  RuleEvaluator();

  final _cache = <Term, RegExp>{};

  bool matches(Expr expr, String text) => switch (expr) {
    And(:final items) => items.every((i) => matches(i, text)),
    Or(:final items) => items.any((i) => matches(i, text)),
    Not(:final inner) => !matches(inner, text),
    final Term t => _regex(t).hasMatch(text),
  };

  /// Unicode-aware: a "word character" is any letter, digit or underscore in any script,
  /// so `\b` (ASCII-only in Dart regexes) is not used. Case folding via lower-casing both
  /// sides handles Cyrillic and other bicameral scripts.
  RegExp _regex(Term t) => _cache.putIfAbsent(t, () {
    final words = t.text.trim().split(RegExp(r'\s+')).map(RegExp.escape);
    final body = words.join(r'\s+');
    final pattern = t.wholeWord
        ? '(?<![\\p{L}\\p{N}_])$body(?![\\p{L}\\p{N}_])'
        : body;
    return RegExp(pattern, unicode: true, caseSensitive: t.caseSensitive);
  });
}
