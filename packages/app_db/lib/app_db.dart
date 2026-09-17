/// Drift/SQLite schema for feeds, feed sources, read marks, watched channels and settings.
///
/// Open with a platform executor: `NativeDatabase` (Android, desktop, tests) or the
/// `sqlite3` WASM executor on the web. See ARCHITECTURE.md section 5.1.
library;

export 'package:drift/drift.dart' show Value;

export 'src/database.dart';
