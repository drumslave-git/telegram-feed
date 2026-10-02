import 'ast.dart';

/// What is wrong with a condition's text form, for a message in the reader's language.
enum RuleSyntaxProblem {
  /// A character that cannot stand here; [RuleSyntaxError.detail] is the character.
  unexpected,
  expectedTerm,
  expectedClosingParen,
  unterminatedQuote,
  danglingEscape,
  emptyTerm,

  /// A bare AND, OR or NOT where a word was meant; [RuleSyntaxError.detail] is the word.
  keyword,
}

/// A condition's text form does not parse. [message] says it in English, for logs.
final class RuleSyntaxError extends FormatException {
  RuleSyntaxError(
    this.problem,
    String message,
    String source,
    int offset, {
    this.detail = '',
  }) : super('rule syntax: $message at ${offset + 1}', source, offset);

  final RuleSyntaxProblem problem;

  /// The character or the word [problem] is about; empty for the others.
  final String detail;

  /// The 1-based position in the text.
  int get position => (offset ?? 0) + 1;
}

/// Text form of a condition, parsed to the same AST the visual builder produces.
///
///     ("bitcoin" OR btc) AND NOT airdrop
///
/// - Terms are bare words or "quoted phrases". Default: whole-word, case-insensitive.
/// - Prefix `~` makes a term a substring match (`~coin` matches "bitcoin").
/// - Prefix `=` makes it case-sensitive (`="BTC"`). Both: `~=`.
/// - `AND`, `OR`, `NOT` (any case) and parentheses; AND binds tighter than OR.
/// - Inside quotes, `\"` and `\\` are escapes.
final class RuleParser {
  RuleParser._(this._src);
  final String _src;
  int _pos = 0;

  static Expr parse(String source) {
    final p = RuleParser._(source);
    final e = p._or();
    p._skipWs();
    if (!p._atEnd) {
      final c = p._src[p._pos];
      p._fail(RuleSyntaxProblem.unexpected, 'unexpected "$c"', detail: c);
    }
    return e;
  }

  /// Renders an expression back to the text form (round-trips through [parse]).
  static String format(Expr e) => switch (e) {
    Or(:final items) => items.map(format).join(' OR '),
    And(:final items) =>
      items.map((i) => i is Or ? '(${format(i)})' : format(i)).join(' AND '),
    Not(:final inner) =>
      'NOT ${inner is Term ? format(inner) : '(${format(inner)})'}',
    Term(:final text, :final wholeWord, :final caseSensitive) =>
      '${wholeWord ? '' : '~'}${caseSensitive ? '=' : ''}${_quote(text)}',
  };

  static String _quote(String text) {
    final bare =
        RegExp(r'^[^\s()"~=\\]+$').hasMatch(text) &&
        !_keywords.contains(text.toUpperCase());
    if (bare) return text;
    return '"${text.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
  }

  static const _keywords = {'AND', 'OR', 'NOT'};

  bool get _atEnd => _pos >= _src.length;

  Never _fail(RuleSyntaxProblem problem, String msg, {String detail = ''}) =>
      throw RuleSyntaxError(problem, msg, _src, _pos, detail: detail);

  void _skipWs() {
    while (!_atEnd && _src[_pos].trim().isEmpty) {
      _pos++;
    }
  }

  bool _keyword(String kw) {
    _skipWs();
    final end = _pos + kw.length;
    if (end > _src.length) return false;
    if (_src.substring(_pos, end).toUpperCase() != kw) return false;
    if (end < _src.length && _isWordChar(_src[end])) return false;
    _pos = end;
    return true;
  }

  static bool _isWordChar(String c) => !RegExp(r'[\s()"~=\\]').hasMatch(c);

  Expr _or() {
    final items = [_and()];
    while (_keyword('OR')) {
      items.add(_and());
    }
    return items.length == 1 ? items.single : Or(items);
  }

  Expr _and() {
    final items = [_not()];
    while (_keyword('AND')) {
      items.add(_not());
    }
    return items.length == 1 ? items.single : And(items);
  }

  Expr _not() {
    if (_keyword('NOT')) return Not(_not());
    return _primary();
  }

  Expr _primary() {
    _skipWs();
    if (_atEnd) _fail(RuleSyntaxProblem.expectedTerm, 'expected a term');
    if (_src[_pos] == '(') {
      _pos++;
      final e = _or();
      _skipWs();
      if (_atEnd || _src[_pos] != ')') {
        _fail(RuleSyntaxProblem.expectedClosingParen, 'expected ")"');
      }
      _pos++;
      return e;
    }
    var wholeWord = true;
    var caseSensitive = false;
    while (!_atEnd && (_src[_pos] == '~' || _src[_pos] == '=')) {
      if (_src[_pos] == '~') wholeWord = false;
      if (_src[_pos] == '=') caseSensitive = true;
      _pos++;
    }
    final text = _src[_pos] == '"' ? _quoted() : _bare();
    return Term(text, wholeWord: wholeWord, caseSensitive: caseSensitive);
  }

  String _quoted() {
    _pos++; // opening quote
    final buf = StringBuffer();
    while (true) {
      if (_atEnd) {
        _fail(RuleSyntaxProblem.unterminatedQuote, 'unterminated quote');
      }
      final c = _src[_pos++];
      if (c == r'\') {
        if (_atEnd) {
          _fail(RuleSyntaxProblem.danglingEscape, 'dangling escape');
        }
        buf.write(_src[_pos++]);
      } else if (c == '"') {
        break;
      } else {
        buf.write(c);
      }
    }
    final text = buf.toString().trim();
    if (text.isEmpty) _fail(RuleSyntaxProblem.emptyTerm, 'empty term');
    return text;
  }

  String _bare() {
    final start = _pos;
    while (!_atEnd && _isWordChar(_src[_pos])) {
      _pos++;
    }
    final text = _src.substring(start, _pos);
    if (text.isEmpty) _fail(RuleSyntaxProblem.expectedTerm, 'expected a term');
    if (_keywords.contains(text.toUpperCase())) {
      _fail(
        RuleSyntaxProblem.keyword,
        '"$text" is a keyword; quote it to match the word',
        detail: text,
      );
    }
    return text;
  }
}
