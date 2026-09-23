import 'package:rules/rules.dart';

/// The visual builder's shape: groups joined by OR, each group an AND of terms, each term
/// optionally negated. Any AST the text form produces in that shape converts losslessly;
/// deeper nesting is only editable as text ([BuilderModel.fromExpr] returns null).
final class BuilderTerm {
  const BuilderTerm({
    required this.text,
    this.wholeWord = true,
    this.caseSensitive = false,
    this.negated = false,
  });
  final String text;
  final bool wholeWord;
  final bool caseSensitive;
  final bool negated;

  BuilderTerm copyWith({
    String? text,
    bool? wholeWord,
    bool? caseSensitive,
    bool? negated,
  }) => BuilderTerm(
    text: text ?? this.text,
    wholeWord: wholeWord ?? this.wholeWord,
    caseSensitive: caseSensitive ?? this.caseSensitive,
    negated: negated ?? this.negated,
  );

  Expr toExpr() {
    final t = Term(
      text.trim(),
      wholeWord: wholeWord,
      caseSensitive: caseSensitive,
    );
    return negated ? Not(t) : t;
  }

  static BuilderTerm? fromExpr(Expr e) => switch (e) {
    Term(:final text, :final wholeWord, :final caseSensitive) => BuilderTerm(
      text: text,
      wholeWord: wholeWord,
      caseSensitive: caseSensitive,
    ),
    Not(inner: Term(:final text, :final wholeWord, :final caseSensitive)) =>
      BuilderTerm(
        text: text,
        wholeWord: wholeWord,
        caseSensitive: caseSensitive,
        negated: true,
      ),
    _ => null,
  };
}

final class BuilderModel {
  const BuilderModel(this.groups);

  /// OR of groups; each group is an AND of terms.
  final List<List<BuilderTerm>> groups;

  /// No terms at all: the rule notifies about every post of its channels. The editor
  /// draws it as a single "Add a term" button, not as a blank row that contradicts the
  /// line above it.
  static const empty = BuilderModel([]);

  bool get isValid =>
      groups.isNotEmpty &&
      groups.every(
        (g) => g.isNotEmpty && g.every((t) => t.text.trim().isNotEmpty),
      );

  /// The same groups without the terms that have no word yet, and without groups left
  /// empty by that; null when no term has a word.
  BuilderModel? withoutBlankTerms() {
    final kept = [
      for (final g in groups)
        if ([
              for (final t in g)
                if (t.text.trim().isNotEmpty) t,
            ]
            case final filled when filled.isNotEmpty)
          filled,
    ];
    return kept.isEmpty ? null : BuilderModel(kept);
  }

  Expr toExpr() {
    final ands = [
      for (final g in groups)
        g.length == 1
            ? g.single.toExpr()
            : And([for (final t in g) t.toExpr()]),
    ];
    return ands.length == 1 ? ands.single : Or(ands);
  }

  /// Null when the expression does not fit the builder's shape.
  static BuilderModel? fromExpr(Expr e) {
    List<BuilderTerm>? group(Expr g) {
      final items = g is And ? g.items : [g];
      final terms = <BuilderTerm>[];
      for (final i in items) {
        final t = BuilderTerm.fromExpr(i);
        if (t == null) return null;
        terms.add(t);
      }
      return terms;
    }

    final alternatives = e is Or ? e.items : [e];
    final groups = <List<BuilderTerm>>[];
    for (final a in alternatives) {
      final g = group(a);
      if (g == null) return null;
      groups.add(g);
    }
    return BuilderModel(groups);
  }
}
