// Migration tests against the schema dumps in drift_schemas/ (ARCHITECTURE.md section 11).
// Before every schema change: `dart run drift_dev schema dump lib/src/database.dart drift_schemas/`
// then bump schemaVersion, and after the change regenerate test/generated/ with
// `dart run drift_dev schema generate drift_schemas/ test/generated/`.
import 'package:app_db/app_db.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:test/test.dart';

import 'generated/schema.dart';

void main() {
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('v1 to v7 adds the rules table and keeps data', () async {
    final connection = await verifier.startAt(1);
    final db = AppDatabase(connection);
    await verifier.migrateAndValidate(db, 7);
    // The upgraded database is usable.
    final feed = await db.createFeed('kept');
    await db.insertRule(
      RulesCompanion.insert(
        name: 'r',
        feedId: feed.id,
        conditionJson: '{"term":"x"}',
        priority: 'normal',
        createdAt: DateTime(2026),
      ),
    );
    expect((await db.allRules()).single.name, 'r');
    expect((await db.allFeeds()).single.id, feed.id);
    await db.close();
  });

  test('v2 to v7 deletes the rules of before and remembers it', () async {
    final schema = await verifier.schemaAt(2);
    schema.rawDatabase.execute(
      "INSERT INTO rules (name, enabled, scope_kind, condition_json, priority, "
      "read_aloud, created_at) VALUES ('old', 1, 'global', '{\"term\":\"x\"}', "
      "'normal', 0, 0)",
    );
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 7);
    expect(await db.allRules(), isEmpty);
    expect((await db.allTombstones()).single.kind, 'rule');
    await db.close();
  });

  test('v3 to v7 gives existing feeds sync ids and edit times', () async {
    final schema = await verifier.schemaAt(3);
    schema.rawDatabase
      ..execute(
        "INSERT INTO feeds (name, position, created_at) VALUES ('Old feed', 0, 1000)",
      )
      ..execute(
        "INSERT INTO rules (name, enabled, scope_kind, condition_json, priority, "
        "read_aloud, created_at) VALUES ('old', 1, 'global', '{}', 'normal', 0, 2000)",
      )
      ..execute(
        "INSERT INTO settings (key, value) VALUES ('themeMode', 'dark')",
      );
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 7);
    final feed = (await db.allFeeds()).single;
    expect(feed.syncId, hasLength(32));
    expect(feed.updatedAt, feed.createdAt);
    expect(await db.setting('themeMode'), 'dark');
    // The rule of before is gone, remembered as deleted.
    expect(await db.allRules(), isEmpty);
    final grave = (await db.allTombstones()).single;
    expect(grave.kind, 'rule');
    expect(grave.syncId, hasLength(32));
    await db.close();
  });

  test('fresh v4 database matches the dump', () async {
    final connection = await verifier.startAt(4);
    final db = AppDatabase(connection);
    await verifier.migrateAndValidate(db, 7);
    await db.close();
  });
  test(
    'v4 to v7 adds feeds.filter_json; existing feeds show everything',
    () async {
      final schema = await verifier.schemaAt(4);
      schema.rawDatabase.execute(
        "INSERT INTO feeds (name, position, created_at, sync_id, updated_at) "
        "VALUES ('old', 0, 0, 'abc', 0)",
      );
      final db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 7);
      final feed = (await db.allFeeds()).single;
      expect(feed.name, 'old');
      expect(feed.filterJson, isNull);
      await db.setFeedFilter(feed.id, '{"media":"withMedia"}');
      expect((await db.allFeeds()).single.filterJson, '{"media":"withMedia"}');
      await db.close();
    },
  );

  test('v5 to v7 drops the read marks of feeds and the read sync setting', () async {
    final schema = await verifier.schemaAt(5);
    schema.rawDatabase
      ..execute(
        "INSERT INTO feeds (name, position, created_at, sync_id, updated_at) "
        "VALUES ('kept', 0, 0, 'abc', 0)",
      )
      ..execute(
        'INSERT INTO feed_read_marks (feed_id, chat_id, last_read_message_id) '
        'VALUES (1, -1, 40)',
      )
      ..execute(
        "INSERT INTO settings (key, value) VALUES ('syncReadToTelegram', 'false')",
      )
      ..execute(
        "INSERT INTO settings (key, value) VALUES ('themeMode', 'dark')",
      );
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 7);
    expect((await db.allFeeds()).single.name, 'kept');
    expect(await db.setting('syncReadToTelegram'), isNull);
    expect(await db.setting('themeMode'), 'dark');
    final tables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name = 'feed_read_marks'",
        )
        .get();
    expect(tables, isEmpty);
    await db.close();
  });

  test(
    'v6 to v7: rules belong to feeds; the old ones are deleted everywhere',
    () async {
      final schema = await verifier.schemaAt(6);
      schema.rawDatabase
        ..execute(
          "INSERT INTO feeds (name, position, created_at, sync_id, updated_at) "
          "VALUES ('kept', 0, 0, 'feed-1', 0)",
        )
        ..execute(
          "INSERT INTO rules (name, enabled, scope_kind, scope_chat_id, "
          "condition_json, priority, read_aloud, created_at, sync_id, updated_at) "
          "VALUES ('global', 1, 'global', NULL, '{}', 'normal', 0, 0, 'rule-1', 0), "
          "('channel', 1, 'channel', -5, '{}', 'urgent', 0, 0, 'rule-2', 0)",
        );
      final db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 7);
      expect((await db.allFeeds()).single.name, 'kept');
      expect(await db.allRules(), isEmpty);
      // Tombstones, so a sync deletes them on the other devices too.
      expect(
        (await db.allTombstones()).map((t) => (t.kind, t.syncId)).toSet(),
        {('rule', 'rule-1'), ('rule', 'rule-2')},
      );
      await db.close();
    },
  );
}
