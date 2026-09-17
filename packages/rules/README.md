# rules

Rule conditions (ARCHITECTURE.md section 6.1). Pure Dart, no I/O.

- `Expr` AST: `And`, `Or`, `Not`, `Term(text, wholeWord, caseSensitive)`; `toJson`/`fromJson` for `condition_json`.
- `RuleParser.parse` / `format`: text form `("bitcoin" OR btc) AND NOT airdrop`; `~` = substring, `=` = case-sensitive.
- `RuleEvaluator.matches(expr, text)`: Unicode-aware word boundaries, case folding incl. Cyrillic, phrases across whitespace.
- `Schedule(weekdays, from, to)`: local-time window that may wrap midnight; the weekday is the day the window starts.
