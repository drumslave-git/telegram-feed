import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

final class MemoryStore implements SyncStore {
  String? content;
  int writes = 0;

  @override
  Future<String?> read() async => content;

  @override
  Future<void> write(String c) async {
    content = c;
    writes++;
  }
}

/// One phone: its own database and clock, the shared file.
final class Device {
  Device(this.store, this.clock)
    : db = AppDatabase(NativeDatabase.memory(), clock: clock);
  final MemoryStore store;
  final DateTime Function() clock;
  final AppDatabase db;
  late final engine = SyncEngine(db: db, store: store, clock: clock);

  Future<SyncResult> sync() => engine.sync();

  Future<Map<String, List<int>>> feeds() async => {
    for (final f in await db.allFeeds())
      f.name: [for (final s in await db.sourcesOf(f.id)) s.chatId],
  };

  Future<Rule> addRule(String name, {String term = 'x'}) => db.insertRule(
    RulesCompanion.insert(
      name: name,
      scopeKind: 'global',
      conditionJson: '{"term":"$term"}',
      priority: 'normal',
      createdAt: clock(),
    ),
  );
}

void main() {
  late MemoryStore store;
  late Device phone;
  late Device tablet;
  var now = DateTime(2026, 1, 1);
  void tick([Duration d = const Duration(minutes: 1)]) => now = now.add(d);

  setUp(() {
    now = DateTime(2026, 1, 1);
    store = MemoryStore();
    phone = Device(store, () => now);
    tablet = Device(store, () => now);
  });
  tearDown(() async {
    await phone.db.close();
    await tablet.db.close();
  });

  test(
    'a second device receives feeds with sources, rules and settings',
    () async {
      final feed = await phone.db.createFeed('News');
      await phone.db.addSource(feed.id, -1, title: 'One', username: 'one');
      await phone.db.addSource(feed.id, -2, title: 'Two');
      await phone.addRule('rates');
      await phone.db.setSetting(SettingKeys.themeMode, 'dark');
      await phone.db.setSetting('ai.lastError', 'local only');
      final first = await phone.sync();
      expect(first.pushed, isTrue);
      expect(first.pulled, 0);

      final r = await tablet.sync();
      expect(r.pulled, 3); // feed, rule, setting
      expect(r.pushed, isFalse);
      expect(await tablet.feeds(), {
        'News': [-1, -2],
      });
      expect((await tablet.db.allWatched()).map((w) => w.username).toSet(), {
        'one',
        null,
      });
      expect((await tablet.db.allRules()).single.name, 'rates');
      expect(await tablet.db.setting(SettingKeys.themeMode), 'dark');
      expect(await tablet.db.setting('ai.lastError'), isNull);

      // Nothing changed: a further sync neither pulls nor pushes.
      final idle = await phone.sync();
      expect(idle.pulled, 0);
      expect(idle.pushed, isFalse);
    },
  );

  test('edits to different items on two devices both survive', () async {
    final feed = await phone.db.createFeed('News');
    await phone.addRule('rates');
    await phone.sync();
    await tablet.sync();

    tick();
    await phone.db.renameFeed(feed.id, 'World news');
    tick();
    final rule = (await tablet.db.allRules()).single;
    await tablet.db.updateRule(rule.copyWith(name: 'rate decisions'));

    await phone.sync();
    await tablet.sync();
    await phone.sync();
    for (final d in [phone, tablet]) {
      expect((await d.db.allFeeds()).single.name, 'World news');
      expect((await d.db.allRules()).single.name, 'rate decisions');
    }
  });

  test(
    'the same item edited on both devices: the newer edit wins everywhere',
    () async {
      final feed = await phone.db.createFeed('News');
      await phone.sync();
      await tablet.sync();

      tick();
      await phone.db.renameFeed(feed.id, 'older edit');
      tick();
      final onTablet = (await tablet.db.allFeeds()).single;
      await tablet.db.renameFeed(onTablet.id, 'newer edit');
      await tablet.db.addSource(onTablet.id, -9, title: 'Nine');

      await phone.sync();
      await tablet.sync();
      await phone.sync();
      expect(await phone.feeds(), {
        'newer edit': [-9],
      });
      expect(await tablet.feeds(), {
        'newer edit': [-9],
      });
    },
  );

  test(
    'deletions propagate, and an edit made after the deletion revives',
    () async {
      final a = await phone.db.createFeed('A');
      await phone.db.createFeed('B');
      final rule = await phone.addRule('r');
      await phone.sync();
      await tablet.sync();

      tick();
      await phone.db.deleteFeed(a.id);
      await phone.db.deleteRule(rule.id);
      await phone.sync();
      final r = await tablet.sync();
      expect(r.pulled, 2);
      expect(await tablet.feeds(), {'B': <int>[]});
      expect(await tablet.db.allRules(), isEmpty);

      // Tablet deletes B, but the phone renames it later: B lives on, renamed.
      tick();
      final bOnTablet = (await tablet.db.allFeeds()).single;
      await tablet.db.deleteFeed(bOnTablet.id);
      tick();
      final bOnPhone = (await phone.db.allFeeds()).single;
      await phone.db.renameFeed(bOnPhone.id, 'B2');
      await tablet.sync();
      await phone.sync();
      await tablet.sync();
      expect(await phone.feeds(), {'B2': <int>[]});
      expect(await tablet.feeds(), {'B2': <int>[]});
    },
  );

  test('a concurrent overwrite heals on the next sync', () async {
    await phone.db.createFeed('from phone');
    await tablet.db.createFeed('from tablet');
    // Both read the empty file, then both write: the tablet's write wins the race.
    final phoneView = SyncSnapshot.merge(
      await phone.engine.exportLocal(),
      const SyncSnapshot(),
      now: now,
    );
    await tablet.sync();
    store.content = phoneView.encode(); // phone overwrites with its stale merge
    await tablet.sync(); // tablet merges itself back in
    await phone.sync();
    expect((await phone.feeds()).keys.toSet(), {'from phone', 'from tablet'});
    expect((await tablet.feeds()).keys.toSet(), {'from phone', 'from tablet'});
  });

  test(
    'old tombstones are forgotten; unreadable or newer files are refused',
    () async {
      final feed = await phone.db.createFeed('gone');
      await phone.sync();
      await phone.db.deleteFeed(feed.id);
      await phone.sync();
      expect(SyncSnapshot.decode(store.content!).tombstones, hasLength(1));
      tick(const Duration(days: 181));
      await phone.sync();
      expect(SyncSnapshot.decode(store.content!).tombstones, isEmpty);
      expect(await phone.db.allTombstones(), isEmpty);

      store.content = 'not json';
      await expectLater(phone.sync(), throwsA(isA<SyncException>()));
      store.content = '{"version": 99}';
      await expectLater(
        phone.sync(),
        throwsA(
          isA<SyncException>().having(
            (e) => e.message,
            'message',
            contains('newer version'),
          ),
        ),
      );
    },
  );

  test('only whitelisted settings travel', () {
    expect(isSyncedSetting('themeMode'), isTrue);
    expect(isSyncedSetting(SettingKeys.countUnreadPosts), isTrue);
    expect(isSyncedSetting(SettingKeys.postTextScale), isTrue);
    expect(isSyncedSetting('tts.rate'), isTrue);
    expect(isSyncedSetting('ai.model'), isTrue);
    expect(isSyncedSetting('ai.lastError'), isFalse);
    expect(isSyncedSetting('sync.lastSyncedAt'), isFalse);
  });

  test('a feed filter travels with the feed', () async {
    final feed = await phone.db.createFeed('Video');
    await phone.sync();
    await tablet.sync();

    tick();
    await phone.db.setFeedFilter(feed.id, '{"kinds":["video"]}');
    await phone.sync();
    await tablet.sync();
    expect(
      (await tablet.db.allFeeds()).single.filterJson,
      '{"kinds":["video"]}',
    );

    tick();
    final onTablet = (await tablet.db.allFeeds()).single;
    await tablet.db.setFeedFilter(onTablet.id, null);
    await tablet.sync();
    await phone.sync();
    expect((await phone.db.allFeeds()).single.filterJson, isNull);
  });
}
