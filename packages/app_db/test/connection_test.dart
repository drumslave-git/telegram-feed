import 'dart:async';
import 'dart:io';

import 'package:app_db/app_db.dart';
import 'package:test/test.dart';

void main() {
  test(
    'a write waits for another connection\'s write instead of failing',
    () async {
      final dir = await Directory.systemTemp.createTemp('app_db_lock');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/app.sqlite');
      final a = AppDatabase(appDatabaseFile(file, inBackground: true));
      final b = AppDatabase(appDatabaseFile(file, inBackground: true));
      addTearDown(() async {
        await a.close();
        await b.close();
      });
      await a.setSetting('warm', '1');
      await b.setting('warm');

      // A holds a write transaction for a while; B writes meanwhile.
      final holding = a.transaction(() async {
        await a.setSetting('a', '1');
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await b.setSetting('b', '2');
      await holding;
      expect(await a.setting('b'), '2');
      expect(await b.setting('a'), '1');
    },
  );

  test('connections that open a new file at once all come up', () async {
    final dir = await Directory.systemTemp.createTemp('app_db_create');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/app.sqlite');
    final dbs = [
      for (var i = 0; i < 3; i++)
        AppDatabase(appDatabaseFile(file, inBackground: true)),
    ];
    addTearDown(() => Future.wait(dbs.map((d) => d.close())));

    // The app, the service and the core reach an empty file together.
    await Future.wait(dbs.map((d) => d.allFeeds()));
    expect(await dbs.first.allFeeds(), isEmpty);
  });

  test(
    'a connection does not migrate a file another one is migrating',
    () async {
      final dir = await Directory.systemTemp.createTemp('app_db_migrate');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/app.sqlite');
      final old = _OldDatabase(appDatabaseFile(file));
      await old.allFeeds();
      await old.close();

      // After an update the app, the service and the core all find the old schema. These two
      // are held at the worst moment for each other: one is between dropping the rules table
      // and creating it again, the other is about to read that same table.
      final dropped = Completer<void>();
      final read = Completer<void>();
      final dropping = _PausingDatabase(
        appDatabaseFile(file, inBackground: true),
        after: 'DROP TABLE',
        reached: dropped,
        before: 'CREATE TABLE IF NOT EXISTS "rules"',
        waitFor: read,
      );
      final reading = _PausingDatabase(
        appDatabaseFile(file, inBackground: true),
        before: 'FROM rules',
        waitFor: dropped,
        reached: read,
      );
      addTearDown(() async {
        await dropping.close();
        await reading.close();
      });

      await Future.wait([dropping.allRules(), reading.allRules()]);
      expect(await dropping.allRules(), isEmpty);
      expect(await reading.allRules(), isEmpty);
    },
  );
}

/// A database file left by an older version of the app.
class _OldDatabase extends AppDatabase {
  _OldDatabase(super.executor);

  @override
  int get schemaVersion => 6;
}

/// Holds a connection at one statement of its migration, so that the connections of the
/// test meet where they would tread on each other.
class _PausingDatabase extends AppDatabase {
  _PausingDatabase(
    super.executor, {
    this.before,
    this.after,
    this.waitFor,
    this.reached,
  });

  /// The statement to hold back until [waitFor] is reached, and the statement that
  /// completes [reached] once it has run. Both are matched as part of the statement.
  final String? before;
  final String? after;
  final Completer<void>? waitFor;
  final Completer<void>? reached;

  /// The other connection may never arrive: with the connections kept apart, only one of
  /// them migrates and the other has no such statement to run.
  static Future<void> _meetOrGoOn(Completer<void> c) =>
      Future.any([c.future, Future<void>.delayed(const Duration(seconds: 1))]);

  @override
  Future<void> customStatement(String statement, [List<Object?>? args]) async {
    final hold = before != null && statement.contains(before!);
    final report = after != null && statement.contains(after!);
    if (hold) await _meetOrGoOn(waitFor!);
    try {
      await super.customStatement(statement, args);
    } finally {
      if (report && !(reached?.isCompleted ?? true)) reached!.complete();
    }
  }
}
