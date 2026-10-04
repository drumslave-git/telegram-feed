import 'dart:async';

import 'package:app_db/app_db.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/service/launcher_badge.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

/// The number on the app's icon follows the unread posts and the three switches of the
/// official app's badge counter.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('tf/badge');

  const loud = Channel(chatId: -1, title: 'Loud', unreadCount: 5);
  const quiet = Channel(
    chatId: -2,
    title: 'Muted',
    unreadCount: 40,
    isMuted: true,
  );
  const read = Channel(chatId: -3, title: 'Read');
  const marked = Channel(chatId: -4, title: 'Marked', isMarkedUnread: true);

  test('unread posts, or channels with unread posts; muted ones only when '
      'they are asked for; a channel marked unread is one', () {
    const all = [loud, quiet, read, marked];
    expect(LauncherBadge.countOf(all, muted: false, posts: true), 6);
    expect(LauncherBadge.countOf(all, muted: true, posts: true), 46);
    expect(LauncherBadge.countOf(all, muted: false, posts: false), 2);
    expect(LauncherBadge.countOf(all, muted: true, posts: false), 3);
    expect(LauncherBadge.countOf(const [], muted: true, posts: true), 0);
  });

  group('the launcher is told', () {
    late AppDatabase db;
    late List<int> sent;
    late List<Channel> channels;
    late StreamController<Object?> changes;
    late LauncherBadge badge;

    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 60));

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      sent = [];
      channels = [loud, quiet];
      changes = StreamController<Object?>.broadcast();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'set') sent.add(call.arguments as int);
        return null;
      });
      badge = LauncherBadge(
        db: db,
        channels: () async => channels,
        changes: [changes.stream],
        settle: const Duration(milliseconds: 10),
      );
      await badge.start();
    });

    tearDown(() async {
      await badge.dispose();
      await changes.close();
      await db.close();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });

    test('at the start, and again a moment after posts arrive or are read; '
        'the same number is not said twice', () async {
      expect(sent, [5]);

      channels = [
        const Channel(chatId: -1, title: 'Loud', unreadCount: 7),
        quiet,
      ];
      // A burst of posts is counted once.
      changes
        ..add(null)
        ..add(null)
        ..add(null);
      await settle();
      expect(sent, [5, 7]);

      changes.add(null);
      await settle();
      expect(sent, [5, 7]);

      channels = [read, quiet];
      changes.add(null);
      await settle();
      expect(sent, [5, 7, 0]);
    });

    test(
      'each switch changes the number when the app says it changed',
      () async {
        await db.setSetting(SettingKeys.badgeMuted, 'true');
        await badge.refresh();
        expect(sent.last, 45);

        await db.setSetting(SettingKeys.countUnreadPosts, 'false');
        await badge.refresh();
        expect(sent.last, 2);

        await db.setSetting(SettingKeys.badgeEnabled, 'false');
        await badge.refresh();
        expect(sent.last, 0);

        await db.setSetting(SettingKeys.badgeEnabled, 'true');
        await badge.refresh();
        expect(sent.last, 2);
      },
    );

    test('an account that cannot be asked has nothing unread', () async {
      final none = LauncherBadge(
        db: db,
        channels: () async => throw StateError('not logged in'),
        changes: const [],
      );
      sent.clear();
      await none.start();
      expect(sent, [0]);
      await none.dispose();
    });
  });
}
