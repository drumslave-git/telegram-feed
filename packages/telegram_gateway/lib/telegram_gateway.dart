/// `TelegramGateway`: the only layer that knows about TDLib. Platform-neutral part.
///
/// Native platforms add `package:telegram_gateway/tdlib_ffi.dart` for the FFI transport;
/// the web will add a tdweb transport in phase 3.
library;

export 'src/gateway.dart';
export 'src/models.dart';
export 'src/td_transport.dart';
export 'src/tdlib_gateway.dart';
export 'src/codec.dart';
