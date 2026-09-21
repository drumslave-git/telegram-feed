# app_db

Drift/SQLite database for everything TDLib does not own (ARCHITECTURE.md section 5.1):
`feeds`, `feed_sources`, `watched_channels`, `rules`, `settings`, `sync_tombstones`.
Schema version 6. Read state is Telegram's own and lives in TDLib.

`AppDatabase` exposes what the screens need (create, rename, reorder and delete feeds; add,
remove and reorder sources; rules; settings; sync export and apply;
`wipe` on logout) and keeps `watched_channels` equal to the union of all sources.

```bash
dart run build_runner build --delete-conflicting-outputs              # after editing lib/src/database.dart
dart run drift_dev schema dump lib/src/database.dart drift_schemas/    # after a schema change
```

A schema change bumps `schemaVersion`, adds an `onUpgrade` step and a schema dump.
`drift_schemas/` holds one dump per version, and `test/migration_test.dart` migrates from each
older version and validates the result.
