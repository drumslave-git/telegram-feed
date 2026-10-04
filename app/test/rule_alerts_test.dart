import 'dart:async';

import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/ai/semantic_gate.dart';
import 'package:telegram_feed/l10n/l10n.dart';
import 'package:telegram_feed/service/notifier.dart';
import 'package:telegram_feed/service/reading_now.dart';
import 'package:telegram_feed/service/rule_alerts.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'semantic_gate_test.dart' show MemorySecrets;
import 'tts_service_test.dart' show FakeSpeaker;

/// A match becomes a notification and, when a rule asks, speech, wherever the alerts run:
/// in the service host, or in the app while background watching is off.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  const chatId = -1001;

  late AppDatabase db;
  late FakeSpeaker speaker;
  late StreamController<MatchEvent> matches;
  late StreamController<PostEvent> posts;
  late StreamController<bool> paused;
  late StreamController<ReadState> reads;
  late Map<int, Map<Object?, Object?>> shade;
  late List<ReadingNow?> reading;
  late List<({int id, String title, String body})> shown;
  late List<int> cancelled;
  late RuleAlerts alerts;

  MatchEvent match(int messageId, {bool readAloud = false}) => MatchEvent.of(
    Post(chatId: chatId, messageId: messageId, date: 1, text: 'rates cut'),
    [
      MatchedRule(
        name: 'macro',
        priority: RulePriority.normal,
        readAloud: readAloud,
      ),
    ],
  );

  /// Whether the app has a lock, and how many buttons each notification was shown with.
  var hasLock = false;
  var buttons = <int, int>{};

  Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 20));

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    hasLock = false;
    buttons = {};
    shown = [];
    cancelled = [];
    shade = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'initialize':
              return true;
            case 'hasNotificationPolicyAccess':
              return false;
            case 'getActiveNotifications':
              return shade.values.toList();
            case 'getNotificationChannels':
              return <Object?>[];
            case 'show':
              final m = call.arguments as Map;
              shown.add((
                id: m['id'] as int,
                title: m['title'] as String? ?? '',
                body: m['body'] as String? ?? '',
              ));
              buttons[m['id'] as int] =
                  ((m['platformSpecifics'] as Map)['actions'] as List?)
                      ?.length ??
                  0;
              shade[m['id'] as int] = {
                'id': m['id'],
                'title': m['title'],
                // Android reports the tag of a notification it shows, never its payload.
                'tag': (m['platformSpecifics'] as Map)['tag'],
                'groupKey': (m['platformSpecifics'] as Map)['groupKey'],
                'channelId': (m['platformSpecifics'] as Map)['channelId'],
              };
            case 'cancel':
              cancelled.add((call.arguments as Map)['id'] as int);
              shade.remove((call.arguments as Map)['id']);
          }
          return null;
        });
    db = AppDatabase(NativeDatabase.memory());
    final feed = await db.createFeed('News');
    await db.addSource(feed.id, chatId, title: 'Wire');
    speaker = FakeSpeaker();
    matches = StreamController<MatchEvent>.broadcast();
    posts = StreamController<PostEvent>.broadcast();
    paused = StreamController<bool>.broadcast();
    reads = StreamController<ReadState>.broadcast();
    reading = [];
    alerts = RuleAlerts(
      db: db,
      matches: matches.stream,
      postEvents: posts.stream,
      pausedChanges: paused.stream,
      readUpdates: reads.stream,
      history: (chatId, {required fromMessageId, required limit}) async => [
        Post(
          chatId: chatId,
          messageId: fromMessageId - 1,
          date: 1,
          text: 'asked of the core',
        ),
      ],
      onReading: reading.add,
      speaker: speaker,
      gate: SemanticGate(db: db, secrets: MemorySecrets()),
      lockSet: () async => hasLock,
      log: (_) {},
    );
    await alerts.start(AppLanguage.englishStrings);
  });

  tearDown(() async {
    await alerts.dispose();
    await db.close();
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('with a lock set and the app not open and unlocked, a notification says '
      'only that there is a new post', () async {
    hasLock = true;
    matches.add(match(7));
    await tick();
    final id = NotificationPlan.idFor(chatId, 7);
    final hidden = shown.firstWhere((s) => s.id == id);
    // Neither the channel nor the words, and no button that would say them aloud.
    expect(
      (hidden.title, hidden.body),
      ('Unofficial Telegram Feed', 'New post'),
    );
    expect(buttons[id], 0);
    // The tap still knows which post it is; the rule's name is not in it.
    final tag = shade[id]!['tag'] as String;
    expect(PostRef.decode(tag)!.messageId, 7);
    expect(tag, isNot(contains('macro')));

    // An edit of that post does not uncover it.
    posts.add(
      PostEdited(
        Post(chatId: chatId, messageId: 7, date: 1, text: 'rates cut twice'),
      ),
    );
    await tick();
    expect(shown.where((s) => s.id == id).map((s) => s.body).toSet(), {
      'New post',
    });

    // The app on screen and past its lock: the post is shown as it is.
    alerts.unlocked = true;
    matches.add(match(8));
    await tick();
    final open = shown.firstWhere(
      (s) => s.id == NotificationPlan.idFor(chatId, 8),
    );
    expect((open.title, open.body), ('Wire', 'rates cut'));
    expect(buttons[NotificationPlan.idFor(chatId, 8)], 2);

    // Behind the lock again, or gone from the screen: hidden again.
    alerts.unlocked = false;
    matches.add(match(9));
    await tick();
    expect(
      shown.firstWhere((s) => s.id == NotificationPlan.idFor(chatId, 9)).body,
      'New post',
    );
  });

  test('without a lock a notification shows its post whether the app is open '
      'or not', () async {
    matches.add(match(7));
    await tick();
    expect(
      shown.firstWhere((s) => s.id == NotificationPlan.idFor(chatId, 7)).body,
      'rates cut',
    );
  });

  test('a match is shown under its channel, and not spoken unasked', () async {
    matches.add(match(7));
    await tick();
    final post = shown.firstWhere(
      (s) => s.id == NotificationPlan.idFor(chatId, 7),
    );
    expect((post.title, post.body), ('Wire', 'rates cut'));
    expect(speaker.spoken, isEmpty);
    expect(reading, isEmpty);
  });

  test('a read-aloud match is spoken, and the banner hears of it', () async {
    matches.add(match(7, readAloud: true));
    await tick();
    expect(speaker.spoken.single, contains('rates cut'));
    expect(reading.last, isA<ReadingNow>());
    expect((reading.last!.chatId, reading.last!.messageId), (chatId, 7));
    expect(reading.last!.channelTitle, 'Wire');
    speaker.finish();
    await tick();
    expect(reading.last, isNull);
  });

  test('Stop on the banner silences the post', () async {
    matches.add(match(7, readAloud: true));
    await tick();
    await alerts.stop(chatId, 7);
    await tick();
    expect(reading.last, isNull);
  });

  test('pausing stops what is read and what waits', () async {
    matches
      ..add(match(7, readAloud: true))
      ..add(match(8, readAloud: true));
    await tick();
    expect(reading.last!.waiting, 1);
    paused.add(true);
    await tick();
    expect(reading.last, isNull);
    expect(speaker.spoken, hasLength(1));
  });

  test(
    'a post read here or in the official app loses its notification',
    () async {
      matches
        ..add(match(7))
        ..add(match(8));
      await tick();
      reads.add(
        const ReadState(chatId: chatId, lastReadMessageId: 7, unreadCount: 1),
      );
      await tick();
      expect(cancelled, contains(NotificationPlan.idFor(chatId, 7)));
      expect(cancelled, isNot(contains(NotificationPlan.idFor(chatId, 8))));
    },
  );

  test('a deleted post takes its notification along', () async {
    matches.add(match(7));
    await tick();
    posts.add(const PostsDeleted(chatId: chatId, messageIds: [7]));
    await tick();
    expect(cancelled, contains(NotificationPlan.idFor(chatId, 7)));
  });
}
