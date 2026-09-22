import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart';

/// The executor for the app database file. The UI, the background service and the core
/// each hold a connection to it, so a connection waits up to five seconds for another
/// one's write instead of failing with "database is locked".
QueryExecutor appDatabaseFile(File file, {bool inBackground = false}) {
  void setup(Database db) => db.execute('PRAGMA busy_timeout = 5000;');
  return inBackground
      ? NativeDatabase.createInBackground(file, setup: setup)
      : NativeDatabase(file, setup: setup);
}
