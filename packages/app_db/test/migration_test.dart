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

  test('v1 to v2 adds the rules table and keeps data', () async {
    final connection = await verifier.startAt(1);
    final db = AppDatabase(connection);
    await verifier.migrateAndValidate(db, 2);
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

  test('fresh v2 database matches the dump', () async {
    final connection = await verifier.startAt(2);
    final db = AppDatabase(connection);
    await verifier.migrateAndValidate(db, 2);
    await db.close();
  });
}
