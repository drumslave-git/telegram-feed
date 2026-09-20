import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/read_marker.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'feeds_screen_test.dart' show ChannelsGateway;

class ViewedGateway extends ChannelsGateway {
  ViewedGateway() : super(const []);
  final viewed = <String>[];
  @override
  Future<void> markViewed(int chatId, List<int> messageIds) async {
    markedViewed[chatId] = messageIds;
    viewed.add('$chatId:${messageIds.join(',')}');
  }
}

TimelineItem item(int chat, int id, {List<int> parts = const []}) =>
    TimelineItem(Post(chatId: chat, messageId: id, date: id, text: 'x'), [
      for (final p in parts)
        Post(chatId: chat, messageId: p, date: p, text: 'y'),
    ]);

void main() {
  late AppDatabase db;
  late ViewedGateway gw;
  late int feedId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    gw = ViewedGateway();
    feedId = (await db.createFeed('F')).id;
    await db.addSource(feedId, -1, title: 'One');
    await db.addSource(feedId, -2, title: 'Two');
  });

  test(
    'debounced write of the newest id per chat, synced to Telegram',
    () async {
      final m = ReadMarker(
        db: db,
        gateway: gw,
        feedId: feedId,
        debounce: const Duration(milliseconds: 20),
      );
      m.seen([
        item(-1, 30),
        item(-2, 5, parts: [4, 3]),
        item(-1, 20),
      ]);
      expect(await db.readMarks(feedId), {-1: 0, -2: 0}); // not yet
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(await db.readMarks(feedId), {-1: 30, -2: 5});
      expect(gw.viewed, unorderedEquals(['-1:20,30', '-2:3,4,5']));

      // Older items scrolled past later do not move marks back or re-report.
      m.seen([item(-1, 10)]);
      await m.flush();
      expect(await db.readMarks(feedId), {-1: 30, -2: 5});
      expect(gw.viewed.length, 2);
    },
  );

  test('setting off: local marks only', () async {
    await db.setSetting(SettingKeys.syncReadToTelegram, 'false');
    final m = ReadMarker(db: db, gateway: gw, feedId: feedId);
    m.seen([item(-1, 7)]);
    await m.flush();
    expect(await db.readMarks(feedId), {-1: 7, -2: 0});
    expect(gw.viewed, isEmpty);
  });
}
