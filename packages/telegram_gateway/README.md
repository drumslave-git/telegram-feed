# telegram_gateway

`TelegramGateway` is the only layer that knows about TDLib (ARCHITECTURE.md section 4).

- `TelegramGateway`: login, channels and folders, history, search, files, reactions, comments,
  account and storage. App-level types (`Channel`, `Post`, `Media`, `Comment`, `FileRef`,
  `AuthState`) are in `models.dart`; nothing above this package imports `tdlib_bindings`.
- `TdlibGateway`: the implementation over a `TdTransport` (raw JSON pipe). Updates are handled
  strictly in order.
- `FfiTransport` (`package:telegram_gateway/tdlib_ffi.dart`): `dart:ffi` to `libtdjson`, one
  receive isolate for all clients.

Tests run against a scripted fake transport (`test/tdlib_gateway_test.dart`).
