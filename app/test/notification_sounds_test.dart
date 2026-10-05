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
          // Android names the sound as its picker lists it.
          if (call.method == 'soundTitle') return 'Argon';
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
    expect(calls.first['method'], 'pickSound');
    expect(
      await tester.runAsync(() => db.setting(SettingKeys.normalSound)),
      'content://media/chosen',
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump();
    expect(find.text('Argon'), findsOneWidget);

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

  testWidgets("one row opens Android's notification settings of the app", (
    tester,
  ) async {
    const channel = MethodChannel('tf/notifications-system');
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SystemNotificationSettingsRow(channel: channel)),
      ),
    );
    await tester.tap(find.text('System notification settings'));
    await tester.pump();
    expect(calls, ['openAppSettings']);
  });

  testWidgets('a warning banner when Android blocks the notifications', (
    tester,
  ) async {
    const channel = MethodChannel('tf/notifications-off');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'areNotificationsEnabled') return false;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(db: db, channel: channel),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Android blocks'), findsOneWidget);
    expect(find.text('Turn them on'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('the screen says whether rules notify while the app is closed: '
      'with push, and how muted channels come late; without it, only while the '
      'app is open', (tester) async {
    Future<void> show(bool push) async {
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationsScreen(
            key: ValueKey(push),
            db: db,
            pushAvailable: () async => push,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Notify while the app is closed', skipOffstage: false),
        200,
      );
    }

    await show(true);
    expect(
      find.textContaining("Telegram's push wakes the app", skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.textContaining('about every tenth post', skipOffstage: false),
      findsOneWidget,
    );
    await show(false);
    expect(
      find.text(
        'This build or this phone gets no push from Telegram. Rules notify only '
        'while the app is open.',
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('the screen has no watching notification row or note any more', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: NotificationsScreen(db: db)));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('System notification settings'),
      200,
    );
    expect(find.text('System notification settings'), findsOneWidget);
    expect(find.text('Watching notification'), findsNothing);
    expect(find.textContaining('Android requires'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
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

      // The default choice uses the plain ids.
      await Notifier().init();
      expect(
        created,
        containsAll(['posts_silent', 'posts_normal_popup', 'posts_urgent']),
      );

      created.clear();
      await Notifier().init(
        sounds: const NotificationSounds(normalSound: 'content://media/42'),
      );
      expect(created.where((id) => id == 'posts_normal_popup'), isEmpty);
      expect(
        created.where((id) => id.startsWith('posts_normal_popup_')),
        isNotEmpty,
      );
    },
  );
}
