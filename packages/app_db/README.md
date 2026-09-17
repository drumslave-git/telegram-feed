# app_db

Drift/SQLite database for everything TDLib does not own (ARCHITECTURE.md section 5.1):
`feeds`, `feed_sources`, `feed_read_marks`, `watched_channels`, `settings`.

```bash
dart run build_runner build --delete-conflicting-outputs   # after editing lib/src/database.dart
```

`AppDatabase` exposes the operations screens need (create/rename/reorder/delete feeds, add/remove/
reorder sources, monotonic read marks, settings, `wipe` on logout) and keeps `watched_channels` equal
to the union of all sources. Schema changes bump `schemaVersion`, add an `onUpgrade` step, and get a
migration test against a schema dump (`dart run drift_dev schema dump lib/src/database.dart drift_schemas/`).
