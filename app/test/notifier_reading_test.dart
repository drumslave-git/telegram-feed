import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/service/notifier.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

/// A post being read aloud offers Stop in place of Listen; neither button takes the
/// notification away, and a change of button changes nothing else.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  const chatId = -1001;

  NotificationPlan planFor(int messageId) => NotificationPlan.forMatch(
    MatchEvent.of(
      Post(chatId: chatId, messageId: messageId, date: 1700000000, text: 'x'),
      const [
        MatchedRule(
          name: 'rates',
          priority: RulePriority.normal,
          readAloud: true,
        ),
      ],
    ),
    channelTitle: 'News',
  );

  /// What Android reports as still showing.
  late List<Map<dynamic, dynamic>> live;

  /// Post notifications as posted, summaries left out.
  late List<Map<dynamic, dynamic>> posted;

  Map<dynamic, dynamic> androidOf(Map<dynamic, dynamic> shown) =>
      shown['platformSpecifics'] as Map<dynamic, dynamic>;
  List<String> buttonsOf(Map<dynamic, dynamic> shown) => [
    for (final a in androidOf(shown)['actions'] as List)
      (a as Map)['id'] as String,
  ];

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    live = [];
    posted = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'initialize':
              return true;
            case 'hasNotificationPolicyAccess':
              return false;
            case 'getActiveNotifications':
              return live;
            case 'show':
              final m = call.arguments as Map;
              if (androidOf(m)['setAsGroupSummary'] != true) posted.add(m);
          }
          return null;
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Map<dynamic, dynamic> activeOf(NotificationPlan p) => {
    'id': p.id,
    'groupKey': p.groupKey,
    'channelId': channelNormal,
    'title': p.title,
    'body': p.body,
    'payload': p.payload,
  };

  test('Listen turns into Stop and back; nothing else changes', () async {
    final notifier = Notifier();
    await notifier.init();
    final plan = planFor(5 << 20);
    await notifier.show(plan);
    live = [activeOf(plan)];
    expect(buttonsOf(posted.last), [actionOpenTelegram, actionListen]);
    final listen = (androidOf(posted.last)['actions'] as List).last as Map;
    expect(listen['cancelNotification'], isFalse);

    await notifier.setReading({plan.id});
    expect(posted, hasLength(2));
    expect(buttonsOf(posted.last), [actionOpenTelegram, actionStop]);
    final stop = (androidOf(posted.last)['actions'] as List).last as Map;
    expect(stop['cancelNotification'], isFalse);

    await notifier.setReading({});
    expect(posted, hasLength(3));
    expect(buttonsOf(posted.last), [actionOpenTelegram, actionListen]);

    // The same notification each time: its time is the post's, it does not sound again,
    // and it keeps its text, rule and group.
    for (final p in posted) {
      expect(p['id'], plan.id);
      expect(p['body'], plan.body);
      expect(androidOf(p)['when'], 1700000000 * 1000);
      expect(androidOf(p)['onlyAlertOnce'], isTrue);
      expect(androidOf(p)['subText'], 'rates');
      expect(androidOf(p)['groupKey'], plan.groupKey);
    }

    // No change, nothing posted.
    await notifier.setReading({});
    expect(posted, hasLength(3));
  });

  test('a post queued before it is shown offers Stop from the start', () async {
    final notifier = Notifier();
    await notifier.init();
    final plan = planFor(5 << 20);
    await notifier.setReading({plan.id});
    await notifier.show(plan);
    expect(posted, hasLength(1));
    expect(buttonsOf(posted.single), [actionOpenTelegram, actionStop]);
  });

  test('a notification the reader dismissed is not brought back', () async {
    final notifier = Notifier();
    await notifier.init();
    final plan = planFor(5 << 20);
    await notifier.setReading({plan.id});
    await notifier.show(plan);
    live = []; // swiped away while it was read
    await notifier.setReading({});
    expect(posted, hasLength(1));
  });

  test('a notification from before the service started changes too', () async {
    final old = planFor(5 << 20);
    live = [activeOf(old)];
    final notifier = Notifier();
    await notifier.init();

    await notifier.setReading({old.id});
    expect(posted, hasLength(1));
    final again = posted.single;
    expect(buttonsOf(again), [actionOpenTelegram, actionStop]);
    expect(again['title'], 'News');
    expect(again['body'], old.body);
    expect(again['payload'], old.payload);
    expect(androidOf(again)['subText'], 'rates');
    expect(androidOf(again)['when'], 1700000000 * 1000);

    await notifier.setReading({});
    expect(buttonsOf(posted.last), [actionOpenTelegram, actionListen]);
  });

  test('a restored plan keeps priority, rule and time', () {
    final plan = planFor(5 << 20);
    final back = NotificationPlan.restore(
      id: plan.id,
      androidChannelId: '${channelUrgentDnd}_k3f9',
      title: plan.title,
      body: plan.body,
      groupKey: plan.groupKey,
      payload: plan.payload,
    )!;
    expect(back.channelId, channelUrgent);
    expect(back.rule, 'rates');
    expect(back.when, 1700000000 * 1000);
    expect(back.summaryId, plan.summaryId);
    expect(PostRef.decode(back.payload)!.messageId, 5 << 20);
    expect(
      NotificationPlan.restore(
        id: 1,
        androidChannelId: channelSilent,
        title: '',
        body: '',
        groupKey: '',
        payload: '',
      ),
      isNull,
    );
  });
}
