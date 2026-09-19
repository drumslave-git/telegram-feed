import 'dart:math';

import 'package:drift/drift.dart';

part 'database.g.dart';

// Schema per ARCHITECTURE.md section 5.1. TDLib owns messages and files; this database only
// holds what the app adds on top: feeds, their sources, read marks and settings.

/// Random id that names a feed or rule on every device (local row ids differ per device).
String newSyncId() {
  final r = Random.secure();
  return [
    for (var i = 0; i < 16; i++)
      r.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}

class Feeds extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  IntColumn get position => integer()();
  DateTimeColumn get createdAt => dateTime()();

  /// Sync (ARCHITECTURE.md section 5.5): cross-device id and time of the last edit, which
  /// covers the feed's name, position and list of sources.
  TextColumn get syncId => text().nullable().clientDefault(newSyncId)();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  /// What the feed shows of its channels' posts: JSON of `core.FeedFilter`, null for
  /// everything. `app_db` does not parse it. Part of the feed for sync.
  TextColumn get filterJson => text().nullable()();
}

class FeedSources extends Table {
  IntColumn get feedId =>
      integer().references(Feeds, #id, onDelete: KeyAction.cascade)();
  IntColumn get chatId => integer()();
  IntColumn get position => integer()();
  DateTimeColumn get addedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {feedId, chatId};
}

/// Newest message id the user has scrolled past, per feed and per channel.
class FeedReadMarks extends Table {
  IntColumn get feedId =>
      integer().references(Feeds, #id, onDelete: KeyAction.cascade)();
  IntColumn get chatId => integer()();
  IntColumn get lastReadMessageId => integer()();

  @override
  Set<Column> get primaryKey => {feedId, chatId};
}

/// Union of all feed sources; what rules see as "global". Kept in sync by [AppDatabase].
class WatchedChannels extends Table {
  IntColumn get chatId => integer()();
  TextColumn get title => text()();
  TextColumn get username => text().nullable()();

  @override
  Set<Column> get primaryKey => {chatId};
}

/// Keyword rules (ARCHITECTURE.md section 6.1). `condition_json` and `schedule_json` are the
/// JSON forms of `rules.Expr` and `rules.Schedule`; `app_db` does not parse them.
class Rules extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  /// 'global' or 'channel'.
  TextColumn get scopeKind => text()();
  IntColumn get scopeChatId => integer().nullable()();
  TextColumn get conditionJson => text()();

  /// 'silent', 'normal' or 'urgent'.
  TextColumn get priority => text()();
  BoolColumn get readAloud => boolean().withDefault(const Constant(false))();
  TextColumn get scheduleJson => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  /// AI semantic rule (section 6.4): what the post should be about, in the user's words.
  /// Null for plain keyword rules. `condition_json` is then the optional keyword pre-filter.
  TextColumn get semanticPrompt => text().nullable()();

  /// Sync: cross-device id and time of the last edit.
  TextColumn get syncId => text().nullable().clientDefault(newSyncId)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
}

class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  /// Sync: time of the last change.
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Feeds and rules deleted on this or another device, so a sync does not resurrect them.
class SyncTombstones extends Table {
  /// 'feed' or 'rule'.
  TextColumn get kind => text()();
  TextColumn get syncId => text()();
  DateTimeColumn get deletedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {kind, syncId};
}

/// A feed with its ordered sources, as screens need it.
final class FeedWithSources {
  const FeedWithSources(this.feed, this.sources);
  final Feed feed;
  final List<FeedSource> sources;
}

/// Setting keys used by the app (values are strings; parse at the call site).
abstract final class SettingKeys {
  static const themeMode = 'themeMode'; // 'system' | 'light' | 'dark'
  static const syncReadToTelegram =
      'syncReadToTelegram'; // 'true' | 'false', default true

  /// Short videos start muted when they scroll into view; 'true' | 'false', default true.
  static const autoplay = 'media.autoplay';

  /// Longest video that autoplays, in seconds (default 60).
  static const autoplayMaxSeconds = 'media.autoplayMaxSeconds';

  /// Largest video that autoplays, in megabytes (default 20).
  static const autoplayMaxMegabytes = 'media.autoplayMaxMegabytes';

  /// Rules keep being evaluated while the app is closed, in the foreground service;
  /// 'true' | 'false', default true. Off means no permanent notification and no rule
  /// notifications unless the app is open.
  static const backgroundWatching = 'service.background';
}

@DriftDatabase(
  tables: [
    Feeds,
    FeedSources,
    FeedReadMarks,
    WatchedChannels,
    Settings,
    Rules,
    SyncTombstones,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// Stamps `updated_at`; injectable so sync tests control time.
  final DateTime Function() _clock;

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(rules); // already has every later column
      } else {
        if (from < 3) await m.addColumn(rules, rules.semanticPrompt);
        if (from < 4) {
          await m.addColumn(rules, rules.syncId);
          await m.addColumn(rules, rules.updatedAt);
        }
      }
      if (from < 4) {
        await m.addColumn(feeds, feeds.syncId);
        await m.addColumn(feeds, feeds.updatedAt);
        await m.addColumn(settings, settings.updatedAt);
        await m.createTable(syncTombstones);
        // Existing rows get an id now; their edit time is their creation time.
        await customStatement(
          'UPDATE feeds SET sync_id = lower(hex(randomblob(16))), updated_at = created_at '
          'WHERE sync_id IS NULL',
        );
        await customStatement(
          'UPDATE rules SET sync_id = lower(hex(randomblob(16))), updated_at = created_at '
          'WHERE sync_id IS NULL',
        );
      }
      if (from < 5) await m.addColumn(feeds, feeds.filterJson);
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  // ---- rules ----

  Future<List<Rule>> allRules() =>
      (select(rules)..orderBy([(r) => OrderingTerm.asc(r.createdAt)])).get();

  Stream<List<Rule>> watchRules() =>
      (select(rules)..orderBy([(r) => OrderingTerm.asc(r.createdAt)])).watch();

  Future<Rule> insertRule(RulesCompanion rule) => into(rules).insertReturning(
    rule.updatedAt.present ? rule : rule.copyWith(updatedAt: Value(_clock())),
  );

  Future<void> updateRule(Rule rule) =>
      update(rules).replace(rule.copyWith(updatedAt: Value(_clock())));

  Future<void> setRuleEnabled(int id, bool enabled) =>
      (update(rules)..where((r) => r.id.equals(id))).write(
        RulesCompanion(enabled: Value(enabled), updatedAt: Value(_clock())),
      );

  Future<void> deleteRule(int id) => transaction(() async {
    final row = await (select(
      rules,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    await (delete(rules)..where((r) => r.id.equals(id))).go();
    await _bury('rule', row.syncId);
  });

  // ---- feeds ----

  /// Feeds ordered by position.
  Future<List<Feed>> allFeeds() =>
      (select(feeds)..orderBy([(f) => OrderingTerm.asc(f.position)])).get();

  Stream<List<Feed>> watchFeeds() =>
      (select(feeds)..orderBy([(f) => OrderingTerm.asc(f.position)])).watch();

  /// Creates a feed at the end of the list.
  Future<Feed> createFeed(String name, {DateTime? now}) =>
      transaction(() async {
        final max = await _maxPosition(feeds, feeds.position);
        return into(feeds).insertReturning(
          FeedsCompanion.insert(
            name: name,
            position: max + 1,
            createdAt: now ?? _clock(),
            updatedAt: Value(now ?? _clock()),
          ),
        );
      });

  Future<void> renameFeed(int feedId, String name) =>
      (update(feeds)..where((f) => f.id.equals(feedId))).write(
        FeedsCompanion(name: Value(name), updatedAt: Value(_clock())),
      );

  /// Sets what the feed shows ([json] of `core.FeedFilter`, null for everything).
  Future<void> setFeedFilter(int feedId, String? json) =>
      (update(feeds)..where((f) => f.id.equals(feedId))).write(
        FeedsCompanion(filterJson: Value(json), updatedAt: Value(_clock())),
      );

  Stream<Feed?> watchFeed(int feedId) =>
      (select(feeds)..where((f) => f.id.equals(feedId))).watchSingleOrNull();

  /// Per watched channel, the filters of the feeds that contain it (null = shows everything).
  /// Rules stay quiet about a post only when every one of them hides it.
  Future<Map<int, List<String?>>> filtersByChat() async {
    final rows = await (select(
      feedSources,
    ).join([innerJoin(feeds, feeds.id.equalsExp(feedSources.feedId))])).get();
    final out = <int, List<String?>>{};
    for (final r in rows) {
      (out[r.readTable(feedSources).chatId] ??= []).add(
        r.readTable(feeds).filterJson,
      );
    }
    return out;
  }

  /// Rewrites positions so [orderedFeedIds] becomes the feed order.
  Future<void> reorderFeeds(List<int> orderedFeedIds) => transaction(() async {
    final now = _clock();
    for (var i = 0; i < orderedFeedIds.length; i++) {
      // Only feeds that really moved count as edited.
      await (update(feeds)..where(
            (f) => f.id.equals(orderedFeedIds[i]) & f.position.equals(i).not(),
          ))
          .write(FeedsCompanion(position: Value(i), updatedAt: Value(now)));
    }
  });

  /// Deletes the feed, its sources and read marks (cascade), then prunes watched channels.
  Future<void> deleteFeed(int feedId) => transaction(() async {
    final row = await (select(
      feeds,
    )..where((f) => f.id.equals(feedId))).getSingleOrNull();
    await (delete(feeds)..where((f) => f.id.equals(feedId))).go();
    await _pruneWatched();
    await _bury('feed', row?.syncId);
  });

  /// A feed's sources are part of the feed for sync: changing them edits the feed.
  Future<void> _touchFeed(int feedId) =>
      (update(feeds)..where((f) => f.id.equals(feedId))).write(
        FeedsCompanion(updatedAt: Value(_clock())),
      );

  Future<void> _bury(String kind, String? syncId) async {
    if (syncId == null) return;
    await into(syncTombstones).insertOnConflictUpdate(
      SyncTombstonesCompanion.insert(
        kind: kind,
        syncId: syncId,
        deletedAt: _clock(),
      ),
    );
  }

  /// Feeds that contain [chatId] as a source, in feed order (notification tap target).
  Future<List<Feed>> feedsContaining(int chatId) async {
    final q =
        select(feeds).join([
            innerJoin(feedSources, feedSources.feedId.equalsExp(feeds.id)),
          ])
          ..where(feedSources.chatId.equals(chatId))
          ..orderBy([OrderingTerm.asc(feeds.position)]);
    return (await q.get()).map((r) => r.readTable(feeds)).toList();
  }

  Future<FeedWithSources?> feedWithSources(int feedId) async {
    final feed = await (select(
      feeds,
    )..where((f) => f.id.equals(feedId))).getSingleOrNull();
    if (feed == null) return null;
    return FeedWithSources(feed, await sourcesOf(feedId));
  }

  // ---- sources ----

  Future<List<FeedSource>> sourcesOf(int feedId) =>
      (select(feedSources)
            ..where((s) => s.feedId.equals(feedId))
            ..orderBy([(s) => OrderingTerm.asc(s.position)]))
          .get();

  Stream<List<FeedSource>> watchSourcesOf(int feedId) =>
      (select(feedSources)
            ..where((s) => s.feedId.equals(feedId))
            ..orderBy([(s) => OrderingTerm.asc(s.position)]))
          .watch();

  /// Emits whenever any feed's sources change (the core re-reads watched channels).
  Stream<List<FeedSource>> watchSourceChanges() => select(feedSources).watch();

  /// Sources of a feed with their channel titles, ordered by position.
  Stream<List<WatchedChannel>> watchSourceChannels(int feedId) {
    final q =
        select(feedSources).join([
            innerJoin(
              watchedChannels,
              watchedChannels.chatId.equalsExp(feedSources.chatId),
            ),
          ])
          ..where(feedSources.feedId.equals(feedId))
          ..orderBy([OrderingTerm.asc(feedSources.position)]);
    return q.watch().map(
      (rows) => rows.map((r) => r.readTable(watchedChannels)).toList(),
    );
  }

  /// Adds a joined channel to a feed (no-op if already present) and records it as watched.
  Future<void> addSource(
    int feedId,
    int chatId, {
    required String title,
    String? username,
    DateTime? now,
  }) => transaction(() async {
    final existing =
        await (select(feedSources)
              ..where((s) => s.feedId.equals(feedId) & s.chatId.equals(chatId)))
            .getSingleOrNull();
    if (existing == null) {
      final max = await _maxPosition(
        feedSources,
        feedSources.position,
        where: feedSources.feedId.equals(feedId),
      );
      await into(feedSources).insert(
        FeedSourcesCompanion.insert(
          feedId: feedId,
          chatId: chatId,
          position: max + 1,
          addedAt: now ?? _clock(),
        ),
      );
      await _touchFeed(feedId);
    }
    await into(watchedChannels).insertOnConflictUpdate(
      WatchedChannelsCompanion.insert(
        chatId: Value(chatId),
        title: title,
        username: Value.absentIfNull(username), // never erase a known username
      ),
    );
  });

  Future<void> removeSource(int feedId, int chatId) => transaction(() async {
    await (delete(
      feedSources,
    )..where((s) => s.feedId.equals(feedId) & s.chatId.equals(chatId))).go();
    await (delete(
      feedReadMarks,
    )..where((r) => r.feedId.equals(feedId) & r.chatId.equals(chatId))).go();
    await _pruneWatched();
    await _touchFeed(feedId);
  });

  Future<void> reorderSources(int feedId, List<int> orderedChatIds) =>
      transaction(() async {
        for (var i = 0; i < orderedChatIds.length; i++) {
          await (update(feedSources)..where(
                (s) =>
                    s.feedId.equals(feedId) &
                    s.chatId.equals(orderedChatIds[i]),
              ))
              .write(FeedSourcesCompanion(position: Value(i)));
        }
        await _touchFeed(feedId);
      });

  // ---- read marks ----

  /// Moves the mark forward only; older ids never overwrite newer ones.
  Future<void> markRead(int feedId, int chatId, int messageId) =>
      transaction(() async {
        final current =
            await (select(feedReadMarks)..where(
                  (r) => r.feedId.equals(feedId) & r.chatId.equals(chatId),
                ))
                .getSingleOrNull();
        if (current != null && current.lastReadMessageId >= messageId) return;
        await into(feedReadMarks).insertOnConflictUpdate(
          FeedReadMarksCompanion.insert(
            feedId: feedId,
            chatId: chatId,
            lastReadMessageId: messageId,
          ),
        );
      });

  /// Emits whenever any read mark changes (badge recomputation).
  Stream<List<FeedReadMark>> watchAllReadMarks() =>
      select(feedReadMarks).watch();

  /// chat id → last read message id for one feed (0 for sources never read).
  Future<Map<int, int>> readMarks(int feedId) async {
    final sources = await sourcesOf(feedId);
    final marks = await (select(
      feedReadMarks,
    )..where((r) => r.feedId.equals(feedId))).get();
    final byChat = {for (final m in marks) m.chatId: m.lastReadMessageId};
    return {for (final s in sources) s.chatId: byChat[s.chatId] ?? 0};
  }

  // ---- watched channels ----

  Future<List<WatchedChannel>> allWatched() => (select(
    watchedChannels,
  )..orderBy([(w) => OrderingTerm.asc(w.title)])).get();

  Future<void> updateWatchedTitle(int chatId, String title, String? username) =>
      (update(watchedChannels)..where((w) => w.chatId.equals(chatId))).write(
        WatchedChannelsCompanion(
          title: Value(title),
          username: Value(username),
        ),
      );

  /// Removes watched channels that no feed references any more.
  Future<void> _pruneWatched() async {
    final referenced = selectOnly(feedSources, distinct: true)
      ..addColumns([feedSources.chatId]);
    await (delete(
      watchedChannels,
    )..where((w) => w.chatId.isNotInQuery(referenced))).go();
  }

  // ---- settings ----

  Future<String?> setting(String key) async => (await (select(
    settings,
  )..where((s) => s.key.equals(key))).getSingleOrNull())?.value;

  Stream<String?> watchSetting(String key) => (select(
    settings,
  )..where((s) => s.key.equals(key))).watchSingleOrNull().map((r) => r?.value);

  Future<void> deleteSetting(String key) =>
      (delete(settings)..where((s) => s.key.equals(key))).go();

  Future<void> setSetting(String key, String value) => into(settings)
      .insertOnConflictUpdate(
        SettingsCompanion.insert(
          key: key,
          value: value,
          updatedAt: Value(_clock()),
        ),
      );

  // ---- sync (ARCHITECTURE.md section 5.5); the merge itself lives in package core ----

  Future<List<Setting>> allSettings() => select(settings).get();

  Future<List<SyncTombstone>> allTombstones() => select(syncTombstones).get();

  Stream<void> watchSyncedData() => customSelect(
    'SELECT 1',
    readsFrom: {feeds, feedSources, rules, settings},
  ).watch().map((_) {});

  /// Writes a feed as another device saved it. Its source list is replaced; read marks of
  /// sources that stay are kept.
  Future<void> applySyncedFeed({
    required String syncId,
    required String name,
    required int position,
    required DateTime updatedAt,
    required List<({int chatId, String title, String? username})> sources,
    String? filterJson,
  }) => transaction(() async {
    final existing = await (select(
      feeds,
    )..where((f) => f.syncId.equals(syncId))).getSingleOrNull();
    final int feedId;
    if (existing == null) {
      feedId = await into(feeds).insert(
        FeedsCompanion.insert(
          name: name,
          position: position,
          createdAt: updatedAt,
          syncId: Value(syncId),
          updatedAt: Value(updatedAt),
          filterJson: Value(filterJson),
        ),
      );
    } else {
      feedId = existing.id;
      await (update(feeds)..where((f) => f.id.equals(feedId))).write(
        FeedsCompanion(
          name: Value(name),
          position: Value(position),
          updatedAt: Value(updatedAt),
          filterJson: Value(filterJson),
        ),
      );
    }
    final keep = {for (final s in sources) s.chatId};
    await (delete(
      feedSources,
    )..where((s) => s.feedId.equals(feedId) & s.chatId.isNotIn(keep))).go();
    await (delete(
      feedReadMarks,
    )..where((r) => r.feedId.equals(feedId) & r.chatId.isNotIn(keep))).go();
    for (var i = 0; i < sources.length; i++) {
      final src = sources[i];
      await into(feedSources).insertOnConflictUpdate(
        FeedSourcesCompanion.insert(
          feedId: feedId,
          chatId: src.chatId,
          position: i,
          addedAt: updatedAt,
        ),
      );
      await into(watchedChannels).insertOnConflictUpdate(
        WatchedChannelsCompanion.insert(
          chatId: Value(src.chatId),
          title: src.title,
          username: Value.absentIfNull(src.username),
        ),
      );
    }
    await _pruneWatched();
  });

  /// Writes a rule as another device saved it ([rule] carries `syncId` and `updatedAt`).
  Future<void> applySyncedRule(RulesCompanion rule) => transaction(() async {
    final existing = await (select(
      rules,
    )..where((r) => r.syncId.equals(rule.syncId.value!))).getSingleOrNull();
    if (existing == null) {
      await into(rules).insert(rule);
    } else {
      await (update(rules)..where((r) => r.id.equals(existing.id))).write(rule);
    }
  });

  /// Removes what another device deleted and remembers the deletion.
  Future<void> applySyncedDeletion(
    String kind,
    String syncId,
    DateTime deletedAt,
  ) => transaction(() async {
    if (kind == 'feed') {
      await (delete(feeds)..where((f) => f.syncId.equals(syncId))).go();
      await _pruneWatched();
    } else if (kind == 'rule') {
      await (delete(rules)..where((r) => r.syncId.equals(syncId))).go();
    }
    await into(syncTombstones).insertOnConflictUpdate(
      SyncTombstonesCompanion.insert(
        kind: kind,
        syncId: syncId,
        deletedAt: deletedAt,
      ),
    );
  });

  Future<void> applySyncedSetting(
    String key,
    String value,
    DateTime updatedAt,
  ) => into(settings).insertOnConflictUpdate(
    SettingsCompanion.insert(
      key: key,
      value: value,
      updatedAt: Value(updatedAt),
    ),
  );

  Future<void> pruneTombstones(DateTime olderThan) => (delete(
    syncTombstones,
  )..where((t) => t.deletedAt.isSmallerThanValue(olderThan))).go();

  Future<bool> syncReadToTelegram() async =>
      (await setting(SettingKeys.syncReadToTelegram)) != 'false';

  /// Logout: everything goes (ARCHITECTURE.md section 10).
  Future<void> wipe() => transaction(() async {
    await delete(rules).go();
    await delete(feedReadMarks).go();
    await delete(feedSources).go();
    await delete(feeds).go();
    await delete(watchedChannels).go();
    await delete(settings).go();
    await delete(syncTombstones).go(); // a logout is not a deletion to sync
  });

  Future<int> _maxPosition<T extends Table>(
    TableInfo<T, dynamic> table,
    GeneratedColumn<int> column, {
    Expression<bool>? where,
  }) async {
    final max = column.max();
    final q = selectOnly(table)..addColumns([max]);
    if (where != null) q.where(where);
    final row = await q.getSingle();
    return row.read(max) ?? -1;
  }
}
