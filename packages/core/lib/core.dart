/// Core: the always-on logic of the app, served to the UI over ports.
///
/// Platform-neutral part. Native platforms also import
/// `package:core/native_isolate.dart` to spawn the core isolate with TDLib over FFI.
library;

export 'src/core_client.dart';
export 'src/core_server.dart';
export 'src/feed_timeline.dart';
export 'src/telegram_links.dart';
export 'src/tts_text.dart';
export 'src/protocol.dart';
export 'src/rule_engine.dart';
