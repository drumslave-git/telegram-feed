# telegram_gateway

`TelegramGateway` is the only layer that knows about TDLib (ARCHITECTURE.md section 4).

- `TelegramGateway`: auth flow, `myChannels`, `history`, `postEvents`, `markViewed`, `download`,
  `membershipEvents`. App-level types (`Channel`, `Post`, `Media`, `FileRef`, `AuthState`) in
  `models.dart`; nothing above this package imports `tdlib_bindings`.
- `TdlibGateway`: the implementation over a `TdTransport` (raw JSON pipe). Updates are handled
  strictly in order.
- `FfiTransport` (`package:telegram_gateway/tdlib_ffi.dart`): `dart:ffi` to `libtdjson`, one
  receive isolate for all clients. Native platforms only.
- Web gets a tdweb transport in phase 3 and reuses `TdlibGateway`.

Tests run against a scripted fake transport (`test/tdlib_gateway_test.dart`).
