/// Rule condition AST (ARCHITECTURE.md section 6.1).
///
///     Expr = And(List<Expr>) | Or(List<Expr>) | Not(Expr) | Term
///     Term = { text, wholeWord, caseSensitive }   // multi-word text = phrase match
library;

sealed class Expr {
  const Expr();

  /// JSON form stored in `rules.condition_json`.
  Map<String, Object?> toJson();

  static Expr fromJson(Map<Object?, Object?> json) {
    if (json case {'and': final List items}) {
      return And([
        for (final i in items) Expr.fromJson(i as Map<Object?, Object?>),
      ]);
    }
    if (json case {'or': final List items}) {
      return Or([
        for (final i in items) Expr.fromJson(i as Map<Object?, Object?>),
      ]);
    }
    if (json case {'not': final Map<Object?, Object?> inner}) {
      return Not(Expr.fromJson(inner));
    }
    if (json case {'term': final String text}) {
      return Term(
        text,
        wholeWord: (json['whole'] as bool?) ?? true,
        caseSensitive: (json['case'] as bool?) ?? false,
      );
    }
    throw FormatException('not a rule expression: $json');
  }
}

final class And extends Expr {
  const And(this.items);
  final List<Expr> items;

  @override
  Map<String, Object?> toJson() => {
    'and': [for (final i in items) i.toJson()],
  };

  @override
  bool operator ==(Object other) => other is And && _listEq(items, other.items);
  @override
  int get hashCode => Object.hash('and', Object.hashAll(items));
}

final class Or extends Expr {
  const Or(this.items);
  final List<Expr> items;

  @override
  Map<String, Object?> toJson() => {
    'or': [for (final i in items) i.toJson()],
  };

  @override
  bool operator ==(Object other) => other is Or && _listEq(items, other.items);
  @override
  int get hashCode => Object.hash('or', Object.hashAll(items));
}

final class Not extends Expr {
  const Not(this.inner);
  final Expr inner;

  @override
  Map<String, Object?> toJson() => {'not': inner.toJson()};

  @override
  bool operator ==(Object other) => other is Not && inner == other.inner;
  @override
  int get hashCode => Object.hash('not', inner);
}

final class Term extends Expr {
  const Term(this.text, {this.wholeWord = true, this.caseSensitive = false});

  /// Word or phrase to look for; internal whitespace matches any whitespace run.
  final String text;
  final bool wholeWord;
  final bool caseSensitive;

  @override
  Map<String, Object?> toJson() => {
    'term': text,
    'whole': wholeWord,
    'case': caseSensitive,
  };

  @override
  bool operator ==(Object other) =>
      other is Term &&
      text == other.text &&
      wholeWord == other.wholeWord &&
      caseSensitive == other.caseSensitive;
  @override
  int get hashCode => Object.hash(text, wholeWord, caseSensitive);
}

bool _listEq(List<Expr> a, List<Expr> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
