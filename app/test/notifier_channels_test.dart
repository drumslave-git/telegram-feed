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
        MatchEvent(
          post: Post(chatId: -1001, messageId: 5 << 20, date: 1, text: 'now'),
          priority: RulePriority.urgent,
          readAloud: false,
          ruleNames: const ['r'],
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
}
