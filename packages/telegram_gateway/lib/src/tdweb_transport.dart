// tdweb transport: TDLib compiled to WebAssembly, running in a Web Worker (spike P0-4).
// Import via `package:telegram_gateway/tdweb.dart` only when compiling for the web.
//
// The page must load `tdweb.js` (a `<script>` in `web/index.html`); its worker chunks and
// the `.wasm` are served from the site root because webpack's public path is `/`.
// JSON strings cross the JS boundary in both directions, so tdweb and the FFI transport
// feed the same codec (int64 fields stay strings, as TDLib's JSON interface emits them).
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'models.dart';
import 'td_transport.dart';

/// tdweb's `TdClient` (the webpack bundle exports it as `tdweb.default`).
@JS('tdweb.default')
extension type _TdClient._(JSObject _) implements JSObject {
  external _TdClient(JSObject options);
  external JSPromise<JSAny?> send(JSAny query);
}

@JS('JSON.stringify')
external JSString _stringify(JSAny? value);

@JS('JSON.parse')
external JSAny _parse(JSString text);

@JS('URL.createObjectURL')
external JSString _createObjectUrl(JSAny blob);

/// One TDLib client in tdweb. Its database and files live in IndexedDB under [instanceName].
final class TdwebTransport implements TdTransport {
  TdwebTransport._();

  /// Creates the client. tdweb keeps one live instance per [instanceName] per browser and
  /// closes older tabs' instances itself.
  factory TdwebTransport.create({
    String instanceName = 'telegram_feed',
    int logVerbosity = 1,
    String jsLogVerbosity = 'warning',
  }) {
    final t = TdwebTransport._();
    final options = JSObject()
      ..['onUpdate'] = t._onEvent.toJS
      ..['instanceName'] = instanceName.toJS
      ..['logVerbosityLevel'] = logVerbosity.toJS
      ..['jsLogVerbosityLevel'] = jsLogVerbosity.toJS
      ..['useDatabase'] = true.toJS;
    t._client = _TdClient(options);
    return t;
  }

  late final _TdClient _client;
  final _events = StreamController<Map<String, Object?>>.broadcast();
  final _objectUrls = <int, String>{};

  @override
  Stream<Map<String, Object?>> get events => _events.stream;

  void _onEvent(JSAny? e) {
    if (e == null || _events.isClosed) return;
    _events.add(_toMap(e));
  }

  static Map<String, Object?> _toMap(JSAny value) =>
      jsonDecode(_stringify(value).toDart) as Map<String, Object?>;

  @override
  void send(Map<String, Object?> request) {
    final extra = request['@extra'];
    // tdweb resolves the promise with the response (our `@extra` restored) and rejects
    // with the `error` object; both go on [events] where TdClient matches them.
    _client
        .send(_parse(jsonEncode(request).toJS))
        .toDart
        .then(_onEvent)
        .catchError((Object e) {
          if (_events.isClosed) return;
          Map<String, Object?> m;
          try {
            // The rejection reason is tdweb's error object (never a Dart value).
            // ignore: invalid_runtime_check_with_js_interop_types
            m = e is JSAny ? _toMap(e) : const {};
          } catch (_) {
            m = const {};
          }
          if (m['@type'] != 'error') {
            m = {'@type': 'error', 'code': -1, 'message': '$e'};
          }
          _events.add({...m, '@extra': ?extra});
        });
  }

  /// A `blob:` URL for a downloaded file, from tdweb's `readFile` (the Blob never goes
  /// through JSON). Cached per file id for the life of the page.
  Future<String> objectUrl(int fileId) async {
    final cached = _objectUrls[fileId];
    if (cached != null) return cached;
    final query = JSObject()
      ..['@type'] = 'readFile'.toJS
      ..['file_id'] = fileId.toJS;
    final JSAny? r;
    try {
      r = await _client.send(query).toDart;
    } catch (e) {
      // ignore: invalid_runtime_check_with_js_interop_types
      final m = e is JSAny ? _toMap(e) : const <String, Object?>{};
      throw TelegramException(
        (m['code'] as num?)?.toInt() ?? -1,
        m['message'] as String? ?? 'readFile failed: $e',
      );
    }
    final data = (r as JSObject?)?['data'];
    if (data == null) {
      throw const TelegramException(-1, 'readFile returned no data');
    }
    return _objectUrls[fileId] = _createObjectUrl(data).toDart;
  }

  @override
  Future<void> close() async {
    _client.send(_parse('{"@type":"close"}'.toJS));
    await _events.close();
  }
}
