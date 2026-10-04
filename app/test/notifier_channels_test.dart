import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/service/notifier.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');

  test(
    'urgent posts move to the DND-bypass channel once access is granted',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      var access = false;
      final created = <String>[];
      final deleted = <String>[];
      final shownOn = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            final args = call.arguments;
            switch (call.method) {
              case 'hasNotificationPolicyAccess':
                return access;
              case 'createNotificationChannel':
                final m = args as Map;
                created.add('${m['id']}:${m['bypassDnd']}');
              case 'deleteNotificationChannel':
                deleted.add(args as String);
              case 'show':
                shownOn.add(
                  ((args as Map)['platformSpecifics'] as Map)['channelId']
                      as String,
                );
              case 'initialize':
                return true;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final notifier = Notifier();
      await notifier.init();
      expect(created, contains('posts_urgent:false'));

      final plan = NotificationPlan.forMatch(
        MatchEvent.of(
          Post(chatId: -1001, messageId: 5 << 20, date: 1, text: 'now'),
          const [
            MatchedRule(
              name: 'r',
              priority: RulePriority.urgent,
              readAloud: false,
            ),
          ],
        ),
        channelTitle: 'News',
      );
      await notifier.show(plan);
      expect(shownOn.toSet(), {'posts_urgent'});

      access = true;
      shownOn.clear();
      await notifier.show(plan);
      expect(created, contains('posts_urgent_dnd:true'));
      expect(deleted, contains('posts_urgent'));
      expect(shownOn.toSet(), {'posts_urgent_dnd'});
    },
  );

  test('posts pop up unless their timeline is on screen; a silent post is '
      'added without a sound', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    final importanceOf = <String, int>{};
    final deleted = <String>[];
    final shown = <Map<Object?, Object?>>[];
    final live = <int>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = call.arguments;
          switch (call.method) {
            case 'hasNotificationPolicyAccess':
              return false;
            case 'createNotificationChannel':
              final m = args as Map;
              importanceOf[m['id'] as String] = m['importance'] as int;
            case 'getNotificationChannels':
              // A phone that had the channel of normal posts that did not pop up.
              return [
                {
                  'id': 'posts_normal',
                  'name': 'Posts',
                  'importance': Importance.defaultImportance.value,
                  'showBadge': true,
                  'bypassDnd': false,
                  'playSound': true,
                  'enableLights': false,
                  'enableVibration': true,
                  'ledColor': 0,
                },
              ];
            case 'deleteNotificationChannel':
              deleted.add(args as String);
            case 'getActiveNotifications':
              return [
                for (final id in live) <dynamic, dynamic>{'id': id},
              ];
            case 'show':
              live.add((args as Map)['id'] as int);
              shown.add(args['platformSpecifics'] as Map);
            case 'initialize':
              return true;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    // Minutes apart, so the limit on how often one channel sounds does not come in.
    var now = DateTime(2026, 10, 4, 12);
    final notifier = Notifier(
      null,
      () => now = now.add(const Duration(minutes: 5)),
    );
    await notifier.init();
    expect(importanceOf['posts_normal_popup'], Importance.high.value);
    expect(importanceOf['posts_urgent'], Importance.high.value);
    expect(importanceOf['posts_silent'], Importance.low.value);
    expect(
      importanceOf['posts_normal_inapp'],
      Importance.defaultImportance.value,
    );
    expect(
      importanceOf['posts_urgent_inapp'],
      Importance.defaultImportance.value,
    );
    expect(deleted, contains('posts_normal'));

    NotificationPlan planOf(int messageId, RulePriority priority) =>
        NotificationPlan.forMatch(
          MatchEvent.of(
            Post(chatId: -1001, messageId: messageId, date: 1, text: 'now'),
            [MatchedRule(name: 'r', priority: priority, readAloud: false)],
          ),
          channelTitle: 'News',
        );

    await notifier.show(planOf(5 << 20, RulePriority.normal));
    final post = shown.single;
    expect(post['channelId'], 'posts_normal_popup');
    expect(post['importance'], Importance.high.value);
    expect(post['priority'], Priority.high.value);
    expect(post['onlyAlertOnce'], isFalse);

    // The app open on another screen: posts pop up as they do outside it.
    notifier.appOpen = true;
    shown.clear();
    await notifier.show(planOf(4 << 20, RulePriority.normal));
    expect(shown.first['channelId'], 'posts_normal_popup');
    expect(shown.first['importance'], Importance.high.value);

    // Their own timeline on screen: they keep their sound but do not pop up.
    notifier.viewing = {-1001};
    shown.clear();
    await notifier.show(planOf(6 << 20, RulePriority.normal));
    await notifier.show(planOf(7 << 20, RulePriority.urgent));
    await notifier.show(planOf(8 << 20, RulePriority.silent));
    final [normal, urgent, silent] = shown;
    expect(normal['channelId'], 'posts_normal_inapp');
    expect(normal['importance'], Importance.defaultImportance.value);
    expect(normal['priority'], Priority.defaultPriority.value);
    expect(urgent['channelId'], 'posts_urgent_inapp');
    expect(urgent['importance'], Importance.defaultImportance.value);
    // A silent post is added to the notification where it is, without a sound.
    expect(silent['channelId'], 'posts_urgent_inapp');
    expect(silent['onlyAlertOnce'], isTrue);

    notifier.appOpen = false;
    shown.clear();
    await notifier.show(planOf(9 << 20, RulePriority.urgent));
    expect(shown.first['channelId'], 'posts_urgent');
  });
}
