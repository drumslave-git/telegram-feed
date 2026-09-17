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
}
