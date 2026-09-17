/// Drift/SQLite schema for feeds, feed sources, read marks, watched channels and settings.
///
/// Open with a platform executor (`NativeDatabase` on Android, desktop and in tests).
/// See ARCHITECTURE.md section 5.1.
library;

export 'package:drift/drift.dart' show Value;

export 'src/database.dart';
