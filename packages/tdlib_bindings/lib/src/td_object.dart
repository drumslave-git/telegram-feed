/// Base classes for the generated TDLib JSON API types.
library;

/// Any TDLib object (update, response, function argument).
abstract base class TdObject {
  const TdObject();

  /// The TL constructor name, sent as `@type`.
  String get tdType;

  /// JSON representation as TDLib expects it (`@type` included).
  Map<String, Object?> toJson();

  @override
  String toString() => '$tdType${toJson()}';
}

/// A TDLib request. `R` is the TL result type; TDLib may still answer with `error`.
abstract base class TdFunction<R extends TdObject> extends TdObject {
  const TdFunction();

  /// Decodes a successful response of this request.
  R decodeResult(Map<String, Object?> json);
}
