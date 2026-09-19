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

  test('v1 to v5 adds the rules table and keeps data', () async {
    final connection = await verifier.startAt(1);
    final db = AppDatabase(connection);
    await verifier.migrateAndValidate(db, 5);
    // The upgraded database is usable.
    final feed = await db.createFeed('kept');
    await db.insertRule(
      RulesCompanion.insert(
        name: 'r',
        scopeKind: 'global',
        conditionJson: '{"term":"x"}',
        priority: 'normal',
        createdAt: DateTime(2026),
      ),
    );
    expect((await db.allRules()).single.name, 'r');
    expect((await db.allFeeds()).single.id, feed.id);
    await db.close();
  });

  test('v2 to v5 adds semantic_prompt and keeps rules', () async {
    final schema = await verifier.schemaAt(2);
    schema.rawDatabase.execute(
      "INSERT INTO rules (name, enabled, scope_kind, condition_json, priority, "
      "read_aloud, created_at) VALUES ('old', 1, 'global', '{\"term\":\"x\"}', "
      "'normal', 0, 0)",
    );
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 5);
    final rule = (await db.allRules()).single;
    expect(rule.name, 'old');
    expect(rule.semanticPrompt, isNull);
    await db.updateRule(
      rule.copyWith(semanticPrompt: const Value('about rates')),
    );
    expect((await db.allRules()).single.semanticPrompt, 'about rates');
    await db.close();
  });

  test(
    'v3 to v5 gives existing feeds and rules sync ids and edit times',
    () async {
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
      await verifier.migrateAndValidate(db, 5);
      final feed = (await db.allFeeds()).single;
      final rule = (await db.allRules()).single;
      expect(feed.syncId, hasLength(32));
      expect(rule.syncId, hasLength(32));
      expect(feed.syncId, isNot(rule.syncId));
      expect(feed.updatedAt, feed.createdAt);
      expect(rule.updatedAt, rule.createdAt);
      expect(await db.setting('themeMode'), 'dark');
      expect(await db.allTombstones(), isEmpty);
      await db.close();
    },
  );

  test('fresh v4 database matches the dump', () async {
    final connection = await verifier.startAt(4);
    final db = AppDatabase(connection);
    await verifier.migrateAndValidate(db, 5);
    await db.close();
  });
  test(
    'v4 to v5 adds feeds.filter_json; existing feeds show everything',
    () async {
      final schema = await verifier.schemaAt(4);
      schema.rawDatabase.execute(
        "INSERT INTO feeds (name, position, created_at, sync_id, updated_at) "
        "VALUES ('old', 0, 0, 'abc', 0)",
      );
      final db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 5);
      final feed = (await db.allFeeds()).single;
      expect(feed.name, 'old');
      expect(feed.filterJson, isNull);
      await db.setFeedFilter(feed.id, '{"media":"withMedia"}');
      expect((await db.allFeeds()).single.filterJson, '{"media":"withMedia"}');
      await db.close();
    },
  );
}
