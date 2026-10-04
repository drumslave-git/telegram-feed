import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/l10n/l10n.dart';
import 'package:telegram_feed/service/notifier.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

/// A channel sounds at most twice in three minutes; an edited post's notification says
/// the new words.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');

  NotificationPlan planFor(
    int messageId, {
    int chatId = -1001,
    RulePriority priority = RulePriority.normal,
    String text = 'post',
  }) => NotificationPlan.forMatch(
    MatchEvent.of(
      Post(chatId: chatId, messageId: messageId, date: 1, text: text),
      [MatchedRule(name: 'r', priority: priority, readAloud: false)],
    ),
    channelTitle: 'News',
  );

  /// Every post notification that was shown: its id, words and Android channel.
  late List<({int id, String body, String channel})> shown;
  late List<int> live;
  late DateTime now;
  late Notifier notifier;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    shown = [];
    live = [];
    now = DateTime(2026, 10, 4, 12);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'initialize':
              return true;
            case 'hasNotificationPolicyAccess':
              return false;
            case 'getActiveNotifications':
              return [
                for (final id in live)
                  <dynamic, dynamic>{'id': id, 'groupKey': 'chat--1001'},
              ];
            case 'show':
              final m = call.arguments as Map;
              final id = m['id'] as int;
              // The group's summary is not a post.
              if (id == NotificationPlan.summaryIdFor(-1001) ||
                  id == NotificationPlan.summaryIdFor(-1002)) {
                break;
              }
              shown.add((
                id: id,
                body: m['body'] as String,
                channel: (m['platformSpecifics'] as Map)['channelId'] as String,
              ));
              if (!live.contains(id)) live.add(id);
          }
          return null;
        });
    notifier = Notifier(null, () => now);
    await notifier.init(strings: AppLanguage.englishStrings);
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  bool quiet(String channelId) => channelId.startsWith(channelSilent);

  test('the third post of a channel within three minutes is shown quietly, '
      'and the channel sounds again when the three minutes are over', () async {
    await notifier.show(planFor(1));
    now = now.add(const Duration(seconds: 30));
    await notifier.show(planFor(2));
    expect(shown.map((s) => quiet(s.channel)), [false, false]);

    now = now.add(const Duration(seconds: 30));
    await notifier.show(planFor(3));
    now = now.add(const Duration(seconds: 30));
    await notifier.show(planFor(4, priority: RulePriority.urgent));
    // Shown, every one of them, but without sound and pop-up.
    expect(shown.map((s) => s.id).toSet(), hasLength(4));
    expect(shown.skip(2).map((s) => quiet(s.channel)), [true, true]);

    // Three minutes after the first sound one more may sound, then the second's
    // three minutes have to pass too.
    now = DateTime(2026, 10, 4, 12, 3, 1);
    await notifier.show(planFor(5));
    expect(quiet(shown.last.channel), isFalse);
    await notifier.show(planFor(6));
    expect(quiet(shown.last.channel), isTrue);
    now = DateTime(2026, 10, 4, 12, 3, 31);
    await notifier.show(planFor(7));
    expect(quiet(shown.last.channel), isFalse);
  });

  test(
    'each channel counts for itself, and silent rules count for nothing',
    () async {
      await notifier.show(planFor(1));
      await notifier.show(planFor(2));
      // Another channel is not held back by this one.
      await notifier.show(planFor(1, chatId: -1002));
      expect(quiet(shown.last.channel), isFalse);

      // Posts of silent rules never sounded: they use up nothing.
      final other = Notifier(null, () => now);
      await other.init(strings: AppLanguage.englishStrings);
      shown.clear();
      for (var i = 1; i <= 3; i++) {
        await other.show(planFor(i, priority: RulePriority.silent));
      }
      await other.show(planFor(4));
      await other.show(planFor(5));
      expect(shown.skip(3).map((s) => quiet(s.channel)), [false, false]);
    },
  );

  test('an edited post changes the words of its notification without '
      'sounding again', () async {
    await notifier.show(planFor(1, text: 'The bridge is closed.'));
    final id = NotificationPlan.idFor(-1001, 1);
    final before = shown.single;

    await notifier.updateBody(-1001, 1, 'The bridge is open again.');
    expect(shown, hasLength(2));
    expect(shown.last.id, id);
    expect(shown.last.body, 'The bridge is open again.');
    // The same channel: Android plays nothing for a notification posted again.
    expect(shown.last.channel, before.channel);

    // The same words again: nothing is posted.
    await notifier.updateBody(-1001, 1, 'The bridge is open again.');
    expect(shown, hasLength(2));
    // The edit did not use up one of the channel's two sounds.
    await notifier.show(planFor(2));
    expect(quiet(shown.last.channel), isFalse);
  });

  test('an edit brings back neither a dismissed notification nor one that '
      'was never shown', () async {
    await notifier.updateBody(-1001, 9, 'never matched');
    expect(shown, isEmpty);

    await notifier.show(planFor(1));
    live.clear(); // swiped away
    await notifier.updateBody(-1001, 1, 'edited');
    expect(shown, hasLength(1));
  });

  test(
    'the words of a notification: one line, cut, or what the post carries',
    () {
      final s = AppLanguage.englishStrings;
      expect(
        NotificationPlan.bodyOf(
          Post(chatId: -1, messageId: 1, date: 1, text: 'a\n\n b'),
          s,
        ),
        'a b',
      );
      expect(
        NotificationPlan.bodyOf(
          Post(chatId: -1, messageId: 1, date: 1, text: 'x' * 300),
          s,
        ),
        hasLength(241),
      );
    },
  );
}
