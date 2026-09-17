import 'dart:async';

import 'package:tdlib_bindings/tdlib_bindings.dart' as td;

import 'models.dart';

/// Raw JSON pipe to one TDLib client: FFI on Android/desktop, tdweb on the web.
abstract interface class TdTransport {
  /// Sends a request; the response (or `error`) arrives on [events] with the same `@extra`.
  void send(Map<String, Object?> request);

  /// Every update and response TDLib emits for this client.
  Stream<Map<String, Object?>> get events;

  Future<void> close();
}

/// Typed request/response layer over a [TdTransport].
final class TdClient {
  TdClient(this._transport) {
    _sub = _transport.events.listen(_onEvent);
  }

  final TdTransport _transport;
  late final StreamSubscription<Map<String, Object?>> _sub;
  final _pending = <String, Completer<Map<String, Object?>>>{};
  final _updates = StreamController<td.Update>.broadcast();
  int _seq = 0;

  /// Decoded updates (responses are routed to their requests instead).
  Stream<td.Update> get updates => _updates.stream;

  /// Raw events for callers that want to inspect unknown types (tests, diagnostics).
  Stream<Map<String, Object?>> get rawEvents => _transport.events;

  void _onEvent(Map<String, Object?> e) {
    final extra = e['@extra'];
    if (extra is String) {
      final c = _pending.remove(extra);
      if (c != null) {
        c.complete(e);
        return;
      }
    }
    final decoded = _decode(e);
    if (decoded is td.Update) _updates.add(decoded);
  }

  td.TdObject? _decode(Map<String, Object?> e) {
    try {
      return td.tdObjectFromJson(e);
    } catch (_) {
      return null; // newer TDLib than the schema, or non-update object
    }
  }

  /// Sends [f] and decodes its result; throws [TelegramException] on `error`.
  Future<R> call<R extends td.TdObject>(td.TdFunction<R> f) async {
    final extra = 'r${_seq++}';
    final c = Completer<Map<String, Object?>>();
    _pending[extra] = c;
    _transport.send({...f.toJson(), '@extra': extra});
    final r = await c.future;
    if (r['@type'] == 'error') {
      throw TelegramException(
        (r['code'] as num?)?.toInt() ?? -1,
        r['message'] as String? ?? '',
      );
    }
    return f.decodeResult(r);
  }

  Future<void> close() async {
    await _sub.cancel();
    await _updates.close();
    for (final c in _pending.values) {
      c.completeError(const TelegramException(-1, 'client closed'));
    }
    _pending.clear();
    await _transport.close();
  }
}
