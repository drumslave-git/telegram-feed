import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/service/notifier.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

/// A notification goes when its post is read, and "N new posts" follows whatever leaves
/// the shade: a post read, swiped away or tapped.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  const chatId = -1001;
  final summaryId = NotificationPlan.summaryIdFor(chatId);

  NotificationPlan planFor(int messageId, {int chat = chatId}) =>
      NotificationPlan.forMatch(
        MatchEvent.of(
          Post(chatId: chat, messageId: messageId, date: 1, text: 'post'),
          const [
            MatchedRule(
              name: 'r',
              priority: RulePriority.normal,
              readAloud: false,
            ),
          ],
        ),
        channelTitle: 'News',
      );

  /// What Android shows: every notification posted and not cancelled since.
  late Map<int, Map<Object?, Object?>> shade;
  late List<int> cancelled;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    shade = {};
    cancelled = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'initialize':
              return true;
            case 'hasNotificationPolicyAccess':
              return false;
            case 'getActiveNotifications':
              return shade.values.toList();
            case 'show':
              final m = call.arguments as Map;
              final specifics = m['platformSpecifics'] as Map;
              shade[m['id'] as int] = {
                'id': m['id'],
                'title': m['title'],
                'body': m['body'],
                // Android reports the tag of a notification it shows, never its payload.
                'tag': (m['platformSpecifics'] as Map)['tag'],
                'groupKey': specifics['groupKey'],
                'channelId': specifics['channelId'],
              };
            case 'cancel':
              final id = (call.arguments as Map)['id'] as int;
              cancelled.add(id);
              shade.remove(id);
          }
          return null;
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  String? summaryBody() => shade[summaryId]?['body'] as String?;

  test('posts read up to a point lose their notifications', () async {
    final notifier = Notifier();
    await notifier.init();
    final a = planFor(5 << 20);
    final b = planFor(6 << 20);
    final c = planFor(7 << 20);
    final other = planFor(5 << 20, chat: -2002);
    for (final p in [a, b, c, other]) {
      await notifier.show(p);
    }
    expect(summaryBody(), '3 new posts');

    // Read up to the second post, here or in the official app.
    await notifier.cancelRead(chatId, 6 << 20);
    expect(shade.containsKey(a.id), isFalse);
    expect(shade.containsKey(b.id), isFalse);
    expect(shade.containsKey(c.id), isTrue);
    expect(summaryBody(), '1 new post');
    // Another channel's post with the same id stays.
    expect(shade.containsKey(other.id), isTrue);

    // The last one read takes the summary along.
    await notifier.cancelRead(chatId, 7 << 20);
    expect(shade.containsKey(c.id), isFalse);
    expect(shade.containsKey(summaryId), isFalse);
  });

  test(
    'a notification from before this notifier started goes as well',
    () async {
      final earlier = Notifier();
      await earlier.init();
      final a = planFor(5 << 20);
      await earlier.show(a);

      // The service restarted: a new notifier that has shown nothing itself.
      final notifier = Notifier();
      await notifier.init();
      await notifier.cancelRead(chatId, 5 << 20);
      expect(shade, isEmpty);
    },
  );

  test('a read position that passes no shown post changes nothing', () async {
    final notifier = Notifier();
    await notifier.init();
    await notifier.show(planFor(5 << 20));
    final before = cancelled.length;
    await notifier.cancelRead(chatId, 4 << 20);
    expect(cancelled.length, before);
    expect(summaryBody(), '1 new post');
  });

  test('a post swiped away or tapped is counted out of the summary', () async {
    final notifier = Notifier();
    await notifier.init();
    final a = planFor(5 << 20);
    final b = planFor(6 << 20);
    await notifier.show(a);
    await notifier.show(b);
    expect(summaryBody(), '2 new posts');

    // Android took one away; the notifier hears of it and recounts.
    shade.remove(a.id);
    await notifier.recount(chatId, gone: {a.id});
    expect(summaryBody(), '1 new post');

    shade.remove(b.id);
    await notifier.recount(chatId, gone: {b.id});
    expect(shade.containsKey(summaryId), isFalse);
  });
}
