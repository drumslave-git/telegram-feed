import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart';

/// How long a connection waits for another one's write before it gives up as locked.
const dbBusyTimeout = Duration(seconds: 5);

/// How long a connection waits for another one's migration, which is longer than a write
/// because it is the whole schema and it happens once, when every connection opens the
/// file together after an update.
const dbMigrationTimeout = Duration(minutes: 1);

/// The executor for the app database file. The UI, the background service and the core
/// each hold a connection to it, so a connection waits for another one's write instead of
/// failing with "database is locked".
QueryExecutor appDatabaseFile(File file, {bool inBackground = false}) {
  void setup(Database db) =>
      db.execute('PRAGMA busy_timeout = ${dbBusyTimeout.inMilliseconds};');
  return inBackground
      ? NativeDatabase.createInBackground(file, setup: setup)
      : NativeDatabase(file, setup: setup);
}
