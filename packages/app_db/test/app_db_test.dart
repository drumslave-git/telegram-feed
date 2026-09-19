import 'package:app_db/app_db.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:test/test.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('schema matches the generated definitions', () async {
    await db.validateDatabaseSchema();
  });

  test('feeds: create appends, rename, reorder, delete', () async {
    final a = await db.createFeed('A');
    final b = await db.createFeed('B');
    expect((await db.allFeeds()).map((f) => f.name), ['A', 'B']);
    expect(b.position, a.position + 1);

    await db.renameFeed(a.id, 'Alpha');
    await db.reorderFeeds([b.id, a.id]);
    expect((await db.allFeeds()).map((f) => f.name), ['B', 'Alpha']);

    await db.deleteFeed(b.id);
    expect((await db.allFeeds()).map((f) => f.id), [a.id]);
  });

  test(
    'sources: add is idempotent, ordered, and maintains watched channels',
    () async {
      final a = await db.createFeed('A');
      final b = await db.createFeed('B');
      await db.addSource(a.id, -1, title: 'One');
      await db.addSource(a.id, -2, title: 'Two', username: 'two');
      await db.addSource(
        a.id,
        -1,
        title: 'One renamed',
      ); // no duplicate, title refreshed
      await db.addSource(b.id, -2, title: 'Two');

      final sources = await db.sourcesOf(a.id);
      expect(sources.map((s) => s.chatId), [-1, -2]);
      expect(
        (await db.allWatched()).map(
          (w) => '${w.chatId}:${w.title}:${w.username}',
        ),
        ['-1:One renamed:null', '-2:Two:two'],
      );

      await db.reorderSources(a.id, [-2, -1]);
      expect((await db.sourcesOf(a.id)).map((s) => s.chatId), [-2, -1]);

      // -2 is still used by feed B, -1 is not: only -1 leaves the watched set.
      await db.removeSource(a.id, -1);
      await db.removeSource(a.id, -2);
      expect((await db.allWatched()).map((w) => w.chatId), [-2]);

      // Deleting B cascades its sources and prunes the last watched channel.
      await db.deleteFeed(b.id);
      expect(await db.allWatched(), isEmpty);
    },
  );

  test('feedsContaining lists feeds with a source, in feed order', () async {
    final a = await db.createFeed('A');
    final b = await db.createFeed('B');
    await db.addSource(b.id, -1, title: 'One');
    await db.addSource(a.id, -1, title: 'One');
    await db.addSource(a.id, -2, title: 'Two');
    expect((await db.feedsContaining(-1)).map((f) => f.name), ['A', 'B']);
    expect((await db.feedsContaining(-2)).map((f) => f.name), ['A']);
    expect(await db.feedsContaining(-9), isEmpty);
  });

  test('watchSourceChannels joins titles in position order', () async {
    final a = await db.createFeed('A');
    await db.addSource(a.id, -1, title: 'One');
    await db.addSource(a.id, -2, title: 'Two', username: 'two');
    await db.reorderSources(a.id, [-2, -1]);
    final rows = await db.watchSourceChannels(a.id).first;
    expect(rows.map((w) => w.title), ['Two', 'One']);
    expect(rows.first.username, 'two');
  });

  test('foreign keys are enforced', () async {
    await expectLater(
      db.addSource(999, -1, title: 'x'),
      throwsA(isA<SqliteException>()),
    );
  });

  test('read marks move forward only and default to 0', () async {
    final a = await db.createFeed('A');
    await db.addSource(a.id, -1, title: 'One');
    await db.addSource(a.id, -2, title: 'Two');
    expect(await db.readMarks(a.id), {-1: 0, -2: 0});

    await db.markRead(a.id, -1, 500);
    await db.markRead(a.id, -1, 300); // older: ignored
    expect(await db.readMarks(a.id), {-1: 500, -2: 0});

    await db.removeSource(a.id, -1);
    expect(await db.readMarks(a.id), {-2: 0});
  });

  test('settings and wipe', () async {
    expect(await db.syncReadToTelegram(), isTrue);
    await db.setSetting(SettingKeys.syncReadToTelegram, 'false');
    expect(await db.syncReadToTelegram(), isFalse);
    await db.setSetting(SettingKeys.syncReadToTelegram, 'true');
    expect(await db.syncReadToTelegram(), isTrue);

    final a = await db.createFeed('A');
    await db.addSource(a.id, -1, title: 'One');
    await db.markRead(a.id, -1, 1);
    await db.wipe();
    expect(await db.allFeeds(), isEmpty);
    expect(await db.allWatched(), isEmpty);
    expect(await db.setting(SettingKeys.syncReadToTelegram), isNull);
  });

  test('watchFeeds emits on changes', () async {
    final names = <List<String>>[];
    final sub = db.watchFeeds().listen(
      (l) => names.add(l.map((f) => f.name).toList()),
    );
    await db.createFeed('A');
    await db.createFeed('B');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();
    expect(names.last, ['A', 'B']);
  });

  group('sync bookkeeping', () {
    late AppDatabase sdb;
    var now = DateTime(2026, 1, 1);

    setUp(() {
      now = DateTime(2026, 1, 1);
      sdb = AppDatabase(NativeDatabase.memory(), clock: () => now);
    });
    tearDown(() => sdb.close());

    test('edits stamp the feed; its sources count as part of it', () async {
      final feed = await sdb.createFeed('F');
      expect(feed.syncId, hasLength(32));
      expect(feed.updatedAt, DateTime(2026, 1, 1));

      now = DateTime(2026, 1, 2);
      await sdb.addSource(feed.id, -1, title: 'One');
      expect((await sdb.allFeeds()).single.updatedAt, DateTime(2026, 1, 2));

      now = DateTime(2026, 1, 3);
      await sdb.removeSource(feed.id, -1);
      expect((await sdb.allFeeds()).single.updatedAt, DateTime(2026, 1, 3));

      // Reordering stamps only feeds that moved.
      final other = await sdb.createFeed('G');
      now = DateTime(2026, 1, 4);
      await sdb.reorderFeeds([feed.id, other.id]);
      expect(
        (await sdb.allFeeds()).map((f) => f.updatedAt),
        everyElement(isNot(DateTime(2026, 1, 4))),
      );
      await sdb.reorderFeeds([other.id, feed.id]);
      expect(
        (await sdb.allFeeds()).map((f) => f.updatedAt),
        everyElement(DateTime(2026, 1, 4)),
      );
    });

    test(
      'deleting a feed or rule leaves a tombstone; wipe leaves none',
      () async {
        final feed = await sdb.createFeed('F');
        final rule = await sdb.insertRule(
          RulesCompanion.insert(
            name: 'r',
            scopeKind: 'global',
            conditionJson: '{"term":"x"}',
            priority: 'normal',
            createdAt: now,
          ),
        );
        expect(rule.updatedAt, now);
        now = DateTime(2026, 2, 1);
        await sdb.setRuleEnabled(rule.id, false);
        expect((await sdb.allRules()).single.updatedAt, now);
        await sdb.deleteFeed(feed.id);
        await sdb.deleteRule(rule.id);
        final graves = await sdb.allTombstones();
        expect(graves.map((t) => (t.kind, t.syncId)).toSet(), {
          ('feed', feed.syncId),
          ('rule', rule.syncId),
        });
        expect(graves.map((t) => t.deletedAt), everyElement(now));

        await sdb.pruneTombstones(DateTime(2026, 3, 1));
        expect(await sdb.allTombstones(), isEmpty);

        final again = await sdb.createFeed('again');
        await sdb.deleteFeed(again.id);
        await sdb.wipe();
        expect(await sdb.allTombstones(), isEmpty);
      },
    );

    test(
      'applying synced items creates, updates and deletes by sync id',
      () async {
        await sdb.applySyncedFeed(
          syncId: 'feed-a',
          name: 'Remote',
          position: 0,
          updatedAt: DateTime(2026, 5, 1),
          sources: [
            (chatId: -1, title: 'One', username: 'one'),
            (chatId: -2, title: 'Two', username: null),
          ],
        );
        var feed = (await sdb.allFeeds()).single;
        expect(feed.name, 'Remote');
        expect(feed.updatedAt, DateTime(2026, 5, 1));
        expect((await sdb.sourcesOf(feed.id)).map((s) => s.chatId), [-1, -2]);
        expect((await sdb.allWatched()).map((w) => w.title).toSet(), {
          'One',
          'Two',
        });
        await sdb.markRead(feed.id, -2, 50);

        await sdb.applySyncedFeed(
          syncId: 'feed-a',
          name: 'Renamed',
          position: 3,
          updatedAt: DateTime(2026, 5, 2),
          sources: [(chatId: -2, title: 'Two', username: null)],
        );
        feed = (await sdb.allFeeds()).single;
        expect(feed.name, 'Renamed');
        expect((await sdb.sourcesOf(feed.id)).map((s) => s.chatId), [-2]);
        expect(await sdb.readMarks(feed.id), {-2: 50});
        expect((await sdb.allWatched()).map((w) => w.chatId), [-2]);

        await sdb.applySyncedRule(
          RulesCompanion.insert(
            name: 'remote rule',
            scopeKind: 'global',
            conditionJson: '{"term":"x"}',
            priority: 'urgent',
            createdAt: DateTime(2026, 5, 1),
            syncId: const Value('rule-a'),
            updatedAt: Value(DateTime(2026, 5, 1)),
          ),
        );
        await sdb.applySyncedRule(
          RulesCompanion.insert(
            name: 'remote rule 2',
            scopeKind: 'global',
            conditionJson: '{"term":"y"}',
            priority: 'silent',
            createdAt: DateTime(2026, 5, 1),
            syncId: const Value('rule-a'),
            updatedAt: Value(DateTime(2026, 5, 3)),
          ),
        );
        final rule = (await sdb.allRules()).single;
        expect(rule.name, 'remote rule 2');
        expect(rule.priority, 'silent');

        await sdb.applySyncedDeletion('feed', 'feed-a', DateTime(2026, 6, 1));
        await sdb.applySyncedDeletion('rule', 'rule-a', DateTime(2026, 6, 1));
        expect(await sdb.allFeeds(), isEmpty);
        expect(await sdb.allRules(), isEmpty);
        expect(await sdb.allTombstones(), hasLength(2));

        await sdb.applySyncedSetting('themeMode', 'dark', DateTime(2026, 6, 2));
        final setting = (await sdb.allSettings()).single;
        expect(setting.value, 'dark');
        expect(setting.updatedAt, DateTime(2026, 6, 2));
      },
    );
  });
  test(
    'feed filters: stored per feed, stamped as an edit, listed per channel',
    () async {
      var now = DateTime(2026, 1, 1);
      final fdb = AppDatabase(NativeDatabase.memory(), clock: () => now);
      final a = await fdb.createFeed('A');
      final b = await fdb.createFeed('B');
      await fdb.addSource(a.id, -1, title: 'One');
      await fdb.addSource(b.id, -1, title: 'One');
      await fdb.addSource(b.id, -2, title: 'Two');
      now = DateTime(2026, 1, 2);
      await fdb.setFeedFilter(a.id, '{"media":"withMedia"}');
      final feeds = await fdb.allFeeds();
      expect(feeds.first.filterJson, '{"media":"withMedia"}');
      expect(feeds.first.updatedAt, DateTime(2026, 1, 2));
      final byChat = await fdb.filtersByChat();
      expect(byChat[-1], unorderedEquals(['{"media":"withMedia"}', null]));
      expect(byChat[-2], [null]);
      await fdb.close();
    },
  );
}
