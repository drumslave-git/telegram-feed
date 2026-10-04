import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/service/notifier.dart';

import 'notifier_harness.dart';

/// Posts that were read or deleted leave their channel's notification, which goes with
/// the last of them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const chatId = -1001;
  final chatNotification = NotificationPlan.idForChat(chatId);

  late FakeShade shade;
  late MemoryStore store;
  late DateTime now;

  void later() => now = now.add(const Duration(minutes: 5));

  Future<Notifier> start() async {
    final notifier = Notifier(null, () => now, store);
    await notifier.init();
    return notifier;
  }

  setUp(() {
    shade = FakeShade()..install();
    store = MemoryStore();
    now = DateTime(2026, 10, 4, 12);
  });

  tearDown(() => shade.remove());

  test('posts read up to a point leave the list without a sound; the '
      'notification goes with the last one', () async {
    final notifier = await start();
    for (final id in [10, 11, 12]) {
      await notifier.show(planFor(id, text: 'p$id'));
      later();
    }

    await notifier.cancelRead(chatId, 11);
    expect(shade.shown.last.texts, ['p12']);
    expect(shade.shown.last.alerts, isFalse);
    expect(shade.shown.last.opens.messageId, 12);
    expect(shade.cancelled, isEmpty);

    await notifier.cancelRead(chatId, 12);
    expect(shade.cancelled, [chatNotification]);
    expect(shade.live, isEmpty);
    expect(notifier.listed(chatId), isEmpty);

    // The next post starts a new list.
    await notifier.show(planFor(13, text: 'p13'));
    expect(shade.shown.last.texts, ['p13']);
  });

  test('a read position that passes no listed post changes nothing', () async {
    final notifier = await start();
    await notifier.show(planFor(10));
    final count = shade.shown.length;
    await notifier.cancelRead(chatId, 9);
    await notifier.cancelRead(-1002, 99);
    expect(shade.shown, hasLength(count));
    expect(shade.cancelled, isEmpty);
  });

  test('a deleted post leaves the list; the last one takes the notification '
      'down', () async {
    final notifier = await start();
    await notifier.show(planFor(10, text: 'stays'));
    later();
    await notifier.show(planFor(11, text: 'deleted'));
    later();

    await notifier.cancel(chatId, [11, 99]);
    expect(shade.shown.last.texts, ['stays']);
    expect(shade.shown.last.alerts, isFalse);

    await notifier.cancel(chatId, [10]);
    expect(shade.cancelled, [chatNotification]);
  });

  test('a notification from before the notifier started loses its read posts '
      'as well', () async {
    final before = await start();
    await before.show(planFor(10, text: 'old'));
    later();
    await before.show(planFor(11, text: 'not so old'));
    later();

    final after = await start();
    await after.cancelRead(chatId, 10);
    expect(shade.shown.last.texts, ['not so old']);
    await after.cancelRead(chatId, 11);
    expect(shade.cancelled, [chatNotification]);
  });

  test(
    'nothing is posted again for a notification the reader swiped away',
    () async {
      final notifier = await start();
      await notifier.show(planFor(10));
      later();
      await notifier.show(planFor(11));
      later();
      shade.swipe(chatId);
      final count = shade.shown.length;
      await notifier.cancelRead(chatId, 10);
      await notifier.cancel(chatId, [11]);
      expect(shade.shown, hasLength(count));
      expect(shade.cancelled, isEmpty);
    },
  );
}
