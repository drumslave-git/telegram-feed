import 'dart:isolate';
import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/service/notifier.dart';

import 'notifier_harness.dart';

/// A channel's notification offers Stop while one of the posts it lists is read or waits
/// to be, and Listen otherwise.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const chatId = -1001;

  late FakeShade shade;
  late MemoryStore store;
  late DateTime now;

  void later() => now = now.add(const Duration(minutes: 5));

  Future<Notifier> start() async {
    final notifier = Notifier(null, () => now, store);
    await notifier.init();
    return notifier;
  }

  int idOf(int messageId) => NotificationPlan.idFor(chatId, messageId);

  setUp(() {
    shade = FakeShade()..install();
    store = MemoryStore();
    now = DateTime(2026, 10, 4, 12);
  });

  tearDown(() => shade.remove());

  test('Listen turns into Stop while a listed post is read, and back; '
      'nothing else changes and nothing sounds', () async {
    final notifier = await start();
    await notifier.show(planFor(10, text: 'a'));
    later();
    await notifier.show(planFor(11, text: 'b'));
    later();
    final before = shade.shown.last;
    expect(before.buttons, [actionOpenTelegram, actionListen]);

    await notifier.setReading({idOf(11)});
    var last = shade.shown.last;
    expect(last.buttons, [actionOpenTelegram, actionStop]);
    expect(last.alerts, isFalse);
    expect(last.texts, before.texts);
    expect(last.channel, before.channel);
    expect(last.when, before.when);

    // The next post of the queue is of the same notification: nothing to change.
    final count = shade.shown.length;
    await notifier.setReading({idOf(10)});
    expect(shade.shown, hasLength(count));

    await notifier.setReading({});
    last = shade.shown.last;
    expect(last.buttons, [actionOpenTelegram, actionListen]);
    expect(last.alerts, isFalse);
  });

  test('only the notification of the channel that is read changes', () async {
    final notifier = await start();
    await notifier.show(planFor(10));
    await notifier.show(planFor(5, chatId: -1002, title: 'Wire'));
    later();
    final count = shade.shown.length;
    await notifier.setReading({NotificationPlan.idFor(-1002, 5)});
    expect(shade.shown, hasLength(count + 1));
    expect(shade.shown.last.id, NotificationPlan.idForChat(-1002));
    expect(shade.shown.last.buttons.last, actionStop);
  });

  test('a post queued before it is shown offers Stop from the start', () async {
    final notifier = await start();
    await notifier.setReading({idOf(10)});
    await notifier.show(planFor(10));
    expect(shade.shown, hasLength(1));
    expect(shade.shown.single.buttons, [actionOpenTelegram, actionStop]);
  });

  test('a notification the reader dismissed is not brought back', () async {
    final notifier = await start();
    await notifier.show(planFor(10));
    await notifier.setReading({idOf(10)});
    later();
    final count = shade.shown.length;
    shade.swipe(chatId); // swiped away while it was read
    await notifier.setReading({});
    expect(shade.shown, hasLength(count));
  });

  test('a swipe reaches the service host as a dismissal', () async {
    final port = ReceivePort();
    IsolateNameServer.removePortNameMapping(notifierPortName);
    IsolateNameServer.registerPortWithName(port.sendPort, notifierPortName);
    addTearDown(() {
      IsolateNameServer.removePortNameMapping(notifierPortName);
      port.close();
    });
    final plan = planFor(5 << 20);
    notificationActionEntryPoint(
      NotificationResponse(
        notificationResponseType:
            NotificationResponseType.notificationDismissed,
        id: NotificationPlan.idForChat(chatId),
        payload: plan.payload,
      ),
    );
    final m = await port.first as Map;
    expect(m['type'], NotificationResponseType.notificationDismissed.name);
    expect(PostRef.decode(m['payload'] as String?)!.chatId, chatId);
  });

  test('a notification from before the host started changes too', () async {
    final before = await start();
    await before.show(planFor(10, text: 'old'));
    later();

    final after = await start();
    await after.setReading({idOf(10)});
    expect(shade.shown.last.buttons, [actionOpenTelegram, actionStop]);
    expect(shade.shown.last.texts, ['old']);
    expect(shade.shown.last.alerts, isFalse);
  });
}
