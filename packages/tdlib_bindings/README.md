# tdlib_bindings

Dart types for the TDLib JSON API, generated from `schema/td_api.tl` at the TDLib commit in
`schema/TDLIB_COMMIT` (the same commit `tool/tdlib` builds `libtdjson.so` from).

```bash
dart run tool/generate.dart     # rewrites lib/src/td_api.dart and formats it
```

Mapping: `int32`/`int53` → `int`, `int64` → `int` (JSON string), `double` → `double`,
`string`/`bytes` → `String`, `Bool` → `bool`, `vector<T>` → `List<T>`, object fields nullable.
A TL type with several constructors is a `sealed class` (switch over it exhaustively); a type with one
constructor named like the type is a single `final class`. Functions extend `TdFunction<R>` and know
how to decode their result. `tdObjectFromJson` decodes any update or response by `@type`.
`Error` is exposed as `TdError`. Import with a prefix: `import 'package:tdlib_bindings/tdlib_bindings.dart' as td;`.
