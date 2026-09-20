import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/service/notifier.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

/// The group summary counts what Android still holds, so dismissed, tapped and deleted
/// posts stop inflating it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  const chatId = -1001;
  final summaryId = NotificationPlan.summaryIdFor(chatId);

  NotificationPlan planFor(int messageId) => NotificationPlan.forMatch(
    MatchEvent.of(
      Post(chatId: chatId, messageId: messageId, date: 1, text: 'post'),
      const [
        MatchedRule(name: 'r', priority: RulePriority.normal, readAloud: false),
      ],
    ),
    channelTitle: 'News',
  );

  /// What Android reports as still showing, each with the group it belongs to.
  late List<({int id, String group})> live;
  late List<({int id, String body})> shown;
  late List<String> icons;
  late List<int> cancelled;

  ({int id, String group}) mine(int id) => (id: id, group: 'chat-$chatId');

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    live = [];
    shown = [];
    icons = [];
    cancelled = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'initialize':
              return true;
            case 'hasNotificationPolicyAccess':
              return false;
            case 'getActiveNotifications':
              return [
                for (final n in live)
                  <dynamic, dynamic>{
                    'id': n.id,
                    'groupKey': n.group,
                    'channelId': channelNormal,
                  },
              ];
            case 'show':
              final m = call.arguments as Map;
              shown.add((id: m['id'] as int, body: m['body'] as String));
              icons.add(
                (m['platformSpecifics'] as Map)['icon'] as String? ?? '',
              );
            case 'cancel':
              cancelled.add((call.arguments as Map)['id'] as int);
          }
          return null;
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  String summaryBody() => shown.lastWhere((s) => s.id == summaryId).body;

  test('the summary counts the posts Android still holds', () async {
    final notifier = Notifier();
    await notifier.init();

    final first = planFor(5 << 20);
    await notifier.show(first);
    // Android has not listed it yet; the post just shown still counts.
    expect(summaryBody(), '1 new post');

    live = [mine(first.id)];
    final second = planFor(6 << 20);
    await notifier.show(second);
    expect(summaryBody(), '2 new posts');

    // The user swipes the first one away: the count follows Android, it does not keep
    // climbing the way a tally would.
    live = [mine(second.id)];
    final third = planFor(7 << 20);
    await notifier.show(third);
    expect(summaryBody(), '2 new posts');
  });

  test('every notification names the status bar icon itself', () async {
    // The plugin's default icon lives in shared preferences, where the UI isolate's own
    // initialisation would otherwise decide it (the launcher icon, in colour).
    final notifier = Notifier();
    await notifier.init();
    await notifier.show(planFor(5 << 20));
    expect(icons, isNotEmpty);
    expect(icons.every((i) => i == notificationIcon), isTrue, reason: '$icons');
  });

  test('the summary counts neither itself nor another channel', () async {
    final notifier = Notifier();
    await notifier.init();
    live = [mine(summaryId), (id: 424242, group: 'chat--2002')];
    await notifier.show(planFor(5 << 20));
    expect(summaryBody(), '1 new post');
  });

  test(
    'a deleted post updates the summary; the last one takes it down',
    () async {
      final notifier = Notifier();
      await notifier.init();
      final a = planFor(5 << 20);
      final b = planFor(6 << 20);
      await notifier.show(a);
      live = [mine(a.id)];
      await notifier.show(b);
      expect(summaryBody(), '2 new posts');

      // A deleted post leaves one behind.
      live = [mine(b.id)];
      await notifier.cancel(chatId, [5 << 20]);
      expect(cancelled, contains(NotificationPlan.idFor(chatId, 5 << 20)));
      expect(summaryBody(), '1 new post');

      // The last one goes: the summary goes with it instead of lingering.
      live = [];
      await notifier.cancel(chatId, [6 << 20]);
      expect(cancelled, contains(summaryId));
    },
  );
}
