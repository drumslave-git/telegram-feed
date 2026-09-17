import 'package:drift/drift.dart';

part 'database.g.dart';

// Schema per ARCHITECTURE.md section 5.1. TDLib owns messages and files; this database only
// holds what the app adds on top: feeds, their sources, read marks and settings.

class Feeds extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  IntColumn get position => integer()();
  DateTimeColumn get createdAt => dateTime()();
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
}

class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
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
}

@DriftDatabase(
  tables: [Feeds, FeedSources, FeedReadMarks, WatchedChannels, Settings, Rules],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) await m.createTable(rules);
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

  Future<Rule> insertRule(RulesCompanion rule) =>
      into(rules).insertReturning(rule);

  Future<void> updateRule(Rule rule) => update(rules).replace(rule);

  Future<void> setRuleEnabled(int id, bool enabled) =>
      (update(rules)..where((r) => r.id.equals(id))).write(
        RulesCompanion(enabled: Value(enabled)),
      );

  Future<void> deleteRule(int id) =>
      (delete(rules)..where((r) => r.id.equals(id))).go();

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
            createdAt: now ?? DateTime.now(),
          ),
        );
      });

  Future<void> renameFeed(int feedId, String name) =>
      (update(feeds)..where((f) => f.id.equals(feedId))).write(
        FeedsCompanion(name: Value(name)),
      );

  /// Rewrites positions so [orderedFeedIds] becomes the feed order.
  Future<void> reorderFeeds(List<int> orderedFeedIds) => transaction(() async {
    for (var i = 0; i < orderedFeedIds.length; i++) {
      await (update(feeds)..where((f) => f.id.equals(orderedFeedIds[i]))).write(
        FeedsCompanion(position: Value(i)),
      );
    }
  });

  /// Deletes the feed, its sources and read marks (cascade), then prunes watched channels.
  Future<void> deleteFeed(int feedId) => transaction(() async {
    await (delete(feeds)..where((f) => f.id.equals(feedId))).go();
    await _pruneWatched();
  });

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
          addedAt: now ?? DateTime.now(),
        ),
      );
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

  Future<void> setSetting(String key, String value) => into(settings)
      .insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));

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
