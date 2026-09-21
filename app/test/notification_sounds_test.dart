import 'package:app_db/app_db.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/service/notifier.dart';
import 'package:telegram_feed/settings/notifications_screen.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('the same choice gives the same channel, a change gives another', () {
    const a = NotificationSounds(normalSound: 'content://a');
    const b = NotificationSounds(normalSound: 'content://a');
    const c = NotificationSounds(normalSound: 'content://b');
    const d = NotificationSounds(
      normalSound: 'content://a',
      normalVibrate: false,
    );
    expect(a, b);
    expect(a == c, isFalse);
    expect(a == d, isFalse);
  });

  testWidgets('the settings offer a sound and a vibration per priority', (
    tester,
  ) async {
    final calls = <Map<Object?, Object?>>[];
    const channel = MethodChannel('tf/notifications');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add({'method': call.method, ...call.arguments as Map});
          return 'content://media/chosen';
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotificationSoundSettings(db: db, channel: channel),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Normal rules: sound'), findsOneWidget);
    expect(find.text('Urgent rules: vibrate'), findsOneWidget);
    expect(find.text('The system default'), findsNWidgets(2));

    await tester.tap(find.text('Normal rules: sound'));
    await tester.runAsync(() async {
      for (var i = 0; i < 3; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        await tester.pump();
      }
    });
    expect(calls.single['method'], 'pickSound');
    expect(
      await tester.runAsync(() => db.setting(SettingKeys.normalSound)),
      'content://media/chosen',
    );

    // Vibration is a plain switch.
    await tester.tap(find.text('Urgent rules: vibrate'));
    await tester.runAsync(() async {
      for (var i = 0; i < 3; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        await tester.pump();
      }
    });
    expect(
      await tester.runAsync(() => db.setting(SettingKeys.urgentVibrate)),
      'false',
    );

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('the watching notification row reads its channel and opens it', (
    tester,
  ) async {
    const channel = MethodChannel('tf/notifications-watching');
    final calls = <Map<Object?, Object?>>[];
    bool? shown = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add({'method': call.method, ...call.arguments as Map});
          return call.method == 'channelShown' ? shown : null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: WatchingNotificationRow(channel: channel)),
      ),
    );
    await tester.pump();
    expect(find.text("Shown. Tap to hide it in Android's settings"), findsOne);
    expect(calls.single, {'method': 'channelShown', 'channel': 'core'});

    await tester.tap(find.text('Watching notification'));
    await tester.pump();
    expect(calls.last, {'method': 'openChannelSettings', 'channel': 'core'});

    // The user turned the channel off and came back.
    shown = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('Hidden. Watching goes on'), findsOne);

    // No channel yet: the watcher has not run since background watching went on.
    shown = null;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('Available after the next start of the app'), findsOne);
    expect(tester.widget<ListTile>(find.byType(ListTile)).enabled, isFalse);
  });

  testWidgets('without the platform side there is no row', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WatchingNotificationRow(
            channel: MethodChannel('tf/notifications-none'),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Watching notification'), findsNothing);
  });

  test(
    'a chosen sound makes a channel of its own; the default keeps the old',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      const plugin = MethodChannel('dexterous.com/flutter/local_notifications');
      final created = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(plugin, (call) async {
            switch (call.method) {
              case 'createNotificationChannel':
                created.add((call.arguments as Map)['id'] as String);
              case 'initialize':
                return true;
              case 'hasNotificationPolicyAccess':
                return false;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(plugin, null),
      );

      // The default choice keeps the ids an older install already has.
      await Notifier().init();
      expect(
        created,
        containsAll(['posts_silent', 'posts_normal', 'posts_urgent']),
      );

      created.clear();
      await Notifier().init(
        sounds: const NotificationSounds(normalSound: 'content://media/42'),
      );
      expect(created.where((id) => id == 'posts_normal'), isEmpty);
      expect(created.where((id) => id.startsWith('posts_normal_')), isNotEmpty);
    },
  );
}
