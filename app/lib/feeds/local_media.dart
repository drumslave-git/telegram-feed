/// Displaying TDLib-managed files: a filesystem path on Android, a `blob:` URL from
/// tdweb on the web (`TdlibGateway.download` returns whichever applies).
library;

export 'local_media_stub.dart'
    if (dart.library.io) 'local_media_native.dart'
    if (dart.library.js_interop) 'local_media_web.dart';
