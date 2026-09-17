/// Rule conditions: AST, text-form parser, evaluator and schedule matcher. Pure Dart, no I/O.
///
/// See ARCHITECTURE.md section 6.1. The text form is
/// `("bitcoin" OR btc) AND NOT airdrop`; see [RuleParser] for the modifiers.
library;

export 'src/ast.dart';
export 'src/evaluator.dart';
export 'src/parser.dart';
export 'src/schedule.dart';
