import 'dart:math';

import 'package:drift/drift.dart';

import 'connection.dart';

part 'database.g.dart';

// Schema per ARCHITECTURE.md section 5.1. TDLib owns messages, files and read state; this
// database only holds what the app adds on top: feeds, their sources, rules and settings.

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

/// Union of all feed sources; what rules see as "global". Kept in sync by [AppDatabase].
class WatchedChannels extends Table {
  IntColumn get chatId => integer()();
  TextColumn get title => text()();
  TextColumn get username => text().nullable()();

  @override
  Set<Column> get primaryKey => {chatId};
}

/// Rules (ARCHITECTURE.md section 6.1). Each belongs to one feed. `condition_json` and
/// `schedule_json` are the JSON forms of `rules.Expr` and `rules.Schedule`; `app_db` does
/// not parse them.
class Rules extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  /// The feed the rule belongs to; the rule goes with it.
  IntColumn get feedId =>
      integer().references(Feeds, #id, onDelete: KeyAction.cascade)();

  /// The one channel of the feed the rule watches; null for every channel of the feed.
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

  /// How much bigger or smaller the text of posts and comments is drawn, as a factor
  /// between 0.8 and 1.6 ('1.0' by default).
  static const postTextScale = 'appearance.postTextScale';

  /// Emoji a double tap on a post sends; the last one reacted with, a thumbs up at first.
  static const quickReaction = 'reactions.quick';

  /// The app asks for a PIN when it has rested; 'true' | 'false', default false. The PIN
  /// itself lives in the keystore, never here.
  static const lockEnabled = 'lock.enabled';

  /// How long the app may rest before it asks again, in seconds ('0' asks at once).
  static const lockTimeout = 'lock.timeoutSeconds';

  /// The device's own fingerprint or face is offered first; 'true' | 'false', default false.
  static const lockBiometrics = 'lock.biometrics';

  /// Sound of the notifications of normal and urgent rules: a content uri from Android's
  /// own picker, or '' for the system default. Silent rules stay silent.
  static const normalSound = 'notifications.normal.sound';
  static const urgentSound = 'notifications.urgent.sound';

  /// Whether those notifications vibrate; 'true' | 'false', default true.
  static const normalVibrate = 'notifications.normal.vibrate';
  static const urgentVibrate = 'notifications.urgent.vibrate';

  /// The badges of the feeds and of the folder tabs count unread posts; 'false' counts the
  /// channels with unread posts instead, as the official app's "Count unread messages"
  /// does. Default true.
  static const countUnreadPosts = 'badge.countPosts';

  /// The card on the Feeds tab that says notifications come from rules is gone for good;
  /// 'true' once the reader dismissed it. Default false.
  static const rulesHintDismissed = 'onboarding.rulesHintDismissed';

  /// The last words searched for, newest first, as a JSON list of strings.
  static const recentSearches = 'search.recent';

  /// What loads by itself on mobile data, on Wi-Fi and while roaming, as the official app's
  /// automatic media download: a JSON `DownloadPreset` each (the app's
  /// `media/auto_download.dart`), Telegram's Medium, High and Low until the reader changes
  /// them.
  static const downloadMobile = 'media.download.mobile';
  static const downloadWifi = 'media.download.wifi';
  static const downloadRoaming = 'media.download.roaming';

  /// The channel picker of the feed editor leaves out the channels that are already in a
  /// feed; 'true' | 'false', default false. Kept on this device.
  static const pickerHidesChannelsInFeeds = 'picker.hideInFeeds';

  /// Where the reader left a feed's or a channel's timeline scrolled up, as JSON (the app's
  /// `feeds/saved_position.dart`); absent when they left it at the newest post, as the
  /// official app keeps a chat's position. Kept on this device.
  static String positionOfFeed(int feedId) => 'position.feed.$feedId';
  static String positionOfChat(int chatId) => 'position.chat.$chatId';

  /// A video that loads by itself starts muted when it scrolls into view; 'true' | 'false',
  /// default true.
  static const autoplay = 'media.autoplay';

  /// The same for GIFs; 'true' | 'false', default true.
  static const autoplayGifs = 'media.autoplayGifs';

  /// Rules keep being evaluated while the app is closed, in the foreground service;
  /// 'true' | 'false', default true. Off means no permanent notification and no rule
  /// notifications unless the app is open.
  static const backgroundWatching = 'service.background';
}

@DriftDatabase(
  tables: [
    Feeds,
    FeedSources,
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
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => _migrate(m),
    onUpgrade: (m, from, to) => _migrate(m),
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement(
        'PRAGMA busy_timeout = ${dbBusyTimeout.inMilliseconds}',
      );
    },
  );

  /// The app, the foreground service and the core each hold a connection to the file, so
  /// after an update all three find the old schema at once. The work happens in an
  /// exclusive transaction and reads the version again inside it: whoever gets there second
  /// waits, then finds nothing left to do instead of migrating a schema that is already
  /// being replaced.
  Future<void> _migrate(Migrator m) async {
    // Waiting out another connection's migration is not "database is locked".
    await customStatement(
      'PRAGMA busy_timeout = ${dbMigrationTimeout.inMilliseconds}',
    );
    await customStatement('BEGIN EXCLUSIVE');
    try {
      final from = await _versionOnDisk();
      if (from != schemaVersion) {
        await _upgrade(m, from);
        // Drift stamps the version after this returns; stamping it here as well puts it in
        // the same transaction, so the schema and its version always match.
        await customStatement('PRAGMA user_version = $schemaVersion');
      }
      await customStatement('COMMIT');
    } on Object {
      await customStatement('ROLLBACK');
      rethrow;
    }
  }

  /// The schema version in the file itself, which is what another connection's migration
  /// changes; the one drift hands to [MigrationStrategy] was read before the lock.
  Future<int> _versionOnDisk() async {
    final row = await customSelect('PRAGMA user_version').getSingle();
    return row.read<int>('user_version');
  }

  /// [from] is 0 for a file that has no schema yet.
  Future<void> _upgrade(Migrator m, int from) async {
    if (from == 0) {
      await m.createAll();
      return;
    }
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
    if (from < 6) {
      // Read state is Telegram's own, one per channel, and reading always reaches it.
      await m.deleteTable('feed_read_marks');
      await customStatement(
        "DELETE FROM settings WHERE key = 'syncReadToTelegram'",
      );
    }
    if (from < 7) {
      // Rules belong to feeds now. The rules of before (global or per channel) are
      // deleted, and their tombstones delete them on every synced device too.
      await customStatement(
        "INSERT OR REPLACE INTO sync_tombstones (kind, sync_id, deleted_at) "
        "SELECT 'rule', sync_id, CAST(strftime('%s', 'now') AS INTEGER) "
        'FROM rules WHERE sync_id IS NOT NULL',
      );
      await m.deleteTable('rules');
      await m.createTable(rules);
    }
  }

  // ---- rules ----

  Future<List<Rule>> allRules() =>
      (select(rules)..orderBy([(r) => OrderingTerm.asc(r.createdAt)])).get();

  Stream<List<Rule>> watchRules() =>
      (select(rules)..orderBy([(r) => OrderingTerm.asc(r.createdAt)])).watch();

  /// Every feed with its channels and its filter: what the rules of each feed watch.
  Future<Map<int, ({Set<int> chats, String? filterJson})>>
  feedsForRules() async {
    final out = <int, ({Set<int> chats, String? filterJson})>{};
    for (final f in await allFeeds()) {
      out[f.id] = (
        chats: {for (final s in await sourcesOf(f.id)) s.chatId},
        filterJson: f.filterJson,
      );
    }
    return out;
  }

  /// Deletes rules and remembers the deletions for sync.
  Future<void> _deleteRules(
    Expression<bool> Function($RulesTable r) where,
  ) async {
    final gone = await (select(rules)..where(where)).get();
    if (gone.isEmpty) return;
    await (delete(rules)..where(where)).go();
    for (final r in gone) {
      await _bury('rule', r.syncId);
    }
  }

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

  /// Deletes the feed with its sources and rules and the position the reader left it at,
  /// then prunes watched channels.
  Future<void> deleteFeed(int feedId) => transaction(() async {
    final row = await (select(
      feeds,
    )..where((f) => f.id.equals(feedId))).getSingleOrNull();
    await _deleteRules((r) => r.feedId.equals(feedId));
    await (delete(feeds)..where((f) => f.id.equals(feedId))).go();
    await deleteSetting(SettingKeys.positionOfFeed(feedId));
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

  /// The names of the feeds each source channel belongs to, in feed order: the tags the
  /// channel lists show.
  Future<Map<int, List<String>>> feedNamesByChat() async {
    final q = select(feedSources).join([
      innerJoin(feeds, feeds.id.equalsExp(feedSources.feedId)),
    ])..orderBy([OrderingTerm.asc(feeds.position)]);
    final out = <int, List<String>>{};
    for (final r in await q.get()) {
      (out[r.readTable(feedSources).chatId] ??= []).add(
        r.readTable(feeds).name,
      );
    }
    return out;
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

  /// One feed by id, or null when it is gone.
  Future<Feed?> feedById(int feedId) =>
      (select(feeds)..where((f) => f.id.equals(feedId))).getSingleOrNull();

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

  /// Removes a channel from a feed, with the feed's rules that watched only that channel.
  Future<void> removeSource(int feedId, int chatId) => transaction(() async {
    await _deleteRules(
      (r) => r.feedId.equals(feedId) & r.scopeChatId.equals(chatId),
    );
    await (delete(
      feedSources,
    )..where((s) => s.feedId.equals(feedId) & s.chatId.equals(chatId))).go();
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

  /// Writes a feed as another device saved it. Its source list is replaced.
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

  /// The local id of the feed another device knows by [syncId]; null when there is none.
  Future<int?> feedIdOf(String syncId) async => (await (select(
    feeds,
  )..where((f) => f.syncId.equals(syncId))).getSingleOrNull())?.id;

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
      final feed = await (select(
        feeds,
      )..where((f) => f.syncId.equals(syncId))).getSingleOrNull();
      if (feed != null) await _deleteRules((r) => r.feedId.equals(feed.id));
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

  /// Logout: everything goes (ARCHITECTURE.md section 10).
  Future<void> wipe() => transaction(() async {
    await delete(rules).go();
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
