// dart:ffi transport to libtdjson (Android, desktop). Not for the web; import via
// `package:telegram_gateway/tdlib_ffi.dart` only on platforms with a native TDLib.
//
// td_receive is global for all clients, so it is polled from exactly one background isolate
// and results are demultiplexed by `@client_id` (verified in spike P0-1).
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'td_transport.dart';

typedef _CreateClientIdC = Int32 Function();
typedef _CreateClientIdDart = int Function();
typedef _SendC = Void Function(Int32, Pointer<Utf8>);
typedef _SendDart = void Function(int, Pointer<Utf8>);
typedef _ReceiveC = Pointer<Utf8> Function(Double);
typedef _ReceiveDart = Pointer<Utf8> Function(double);
typedef _ExecuteC = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _ExecuteDart = Pointer<Utf8> Function(Pointer<Utf8>);

/// The loaded native library. One per process.
final class TdJson {
  TdJson._(DynamicLibrary lib)
    : _createClientId = lib
          .lookupFunction<_CreateClientIdC, _CreateClientIdDart>(
            'td_create_client_id',
          ),
      _send = lib.lookupFunction<_SendC, _SendDart>('td_send'),
      _execute = lib.lookupFunction<_ExecuteC, _ExecuteDart>('td_execute');

  /// [libraryPath] defaults to `libtdjson.so`, which the Android loader finds in `jniLibs`.
  factory TdJson.open([String libraryPath = 'libtdjson.so']) {
    _libraryPath = libraryPath;
    return _instance ??= TdJson._(DynamicLibrary.open(libraryPath));
  }

  static TdJson? _instance;
  static String _libraryPath = 'libtdjson.so';
  final _CreateClientIdDart _createClientId;
  final _SendDart _send;
  final _ExecuteDart _execute;

  int createClientId() => _createClientId();

  void send(int clientId, Map<String, Object?> request) {
    final p = jsonEncode(request).toNativeUtf8();
    try {
      _send(clientId, p);
    } finally {
      malloc.free(p);
    }
  }

  /// Synchronous requests that need no client (`setLogVerbosityLevel`, `getOption version`).
  Map<String, Object?> execute(Map<String, Object?> request) {
    final p = jsonEncode(request).toNativeUtf8();
    try {
      final r = _execute(p);
      if (r == nullptr) return const {};
      return jsonDecode(r.toDartString()) as Map<String, Object?>;
    } finally {
      malloc.free(p);
    }
  }
}

void _receiveLoop(List<Object> args) {
  final out = args[0] as SendPort;
  final path = args[1] as String;
  final lib = DynamicLibrary.open(path);
  final receive = lib.lookupFunction<_ReceiveC, _ReceiveDart>('td_receive');
  while (true) {
    final r = receive(1.0);
    if (r == nullptr) continue;
    out.send(r.toDartString());
  }
}

/// Global receive pump shared by all [FfiTransport]s in this isolate.
final class _Receiver {
  static final _events = StreamController<Map<String, Object?>>.broadcast();
  static Future<void>? _started;

  static Stream<Map<String, Object?>> get events => _events.stream;

  static Future<void> start() => _started ??= () async {
    final port = ReceivePort();
    port.listen(
      (msg) => _events.add(jsonDecode(msg as String) as Map<String, Object?>),
    );
    await Isolate.spawn(_receiveLoop, [
      port.sendPort,
      TdJson._libraryPath,
    ], debugName: 'td_receive');
  }();
}

/// One TDLib client over the FFI.
final class FfiTransport implements TdTransport {
  FfiTransport._(this._td, this.clientId);

  /// Loads the library (once), starts the receive isolate (once) and creates a client.
  static Future<FfiTransport> create({
    String libraryPath = 'libtdjson.so',
    int logVerbosity = 1,
  }) async {
    final td = TdJson.open(libraryPath);
    td.execute({
      '@type': 'setLogVerbosityLevel',
      'new_verbosity_level': logVerbosity,
    });
    await _Receiver.start();
    return FfiTransport._(td, td.createClientId());
  }

  final TdJson _td;
  final int clientId;

  @override
  Stream<Map<String, Object?>> get events =>
      _Receiver.events.where((e) => e['@client_id'] == clientId);

  @override
  void send(Map<String, Object?> request) => _td.send(clientId, request);

  @override
  Future<void> close() async {
    // TDLib closes the client on `close`; the receive isolate keeps serving other clients.
    _td.send(clientId, const {'@type': 'close'});
  }
}
