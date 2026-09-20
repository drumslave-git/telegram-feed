import 'package:app_db/app_db.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/settings/app_lock.dart';

/// The keystore, in memory: the plugin needs a device.
class FakeStore implements PinStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String v) async => value = v;

  @override
  Future<void> delete() async => value = null;
}

void main() {
  late AppDatabase db;
  late FakeStore store;
  late AppLock lock;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = FakeStore();
    lock = AppLock(db: db, store: store);
  });

  tearDown(() => db.close());

  test('the PIN is kept as a salted hash, never as itself', () async {
    expect(await lock.enabled, isFalse);
    await lock.setPin('1234');
    expect(await lock.enabled, isTrue);
    final stored = store.value!;
    expect(stored.contains('1234'), isFalse);
    expect(stored.split(':').length, 2);

    expect(await lock.check('1234'), isTrue);
    expect(await lock.check('4321'), isFalse);

    // A second PIN gets its own salt, so the same digits hash differently.
    final first = store.value;
    await lock.setPin('1234');
    expect(store.value, isNot(first));
    expect(await lock.check('1234'), isTrue);

    await lock.remove();
    expect(await lock.enabled, isFalse);
    expect(await lock.hasPin(), isFalse);
  });

  test(
    'the lock is off until a PIN exists, whatever the setting says',
    () async {
      await db.setSetting(SettingKeys.lockEnabled, 'true');
      expect(await lock.enabled, isFalse);
      await lock.setPin('9999');
      expect(await lock.enabled, isTrue);
    },
  );

  testWidgets('a locked app shows nothing until the PIN is right', (
    tester,
  ) async {
    await tester.runAsync(() => lock.setPin('1234'));
    await tester.pumpWidget(
      MaterialApp(
        home: LockGate(
          db: db,
          lock: lock,
          child: const Scaffold(body: Center(child: Text('the feed'))),
        ),
      ),
    );
    await tester.runAsync(() async {
      for (var i = 0; i < 3; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        await tester.pump();
      }
    });

    expect(find.text('telegram-feed is locked'), findsOneWidget);
    // The feed is behind the lock, not on top of it.
    expect(find.text('Unlock'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '4321');
    await tester.tap(find.text('Unlock'));
    await tester.runAsync(() async {
      for (var i = 0; i < 3; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        await tester.pump();
      }
    });
    expect(find.text('Wrong PIN'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('Unlock'));
    await tester.runAsync(() async {
      for (var i = 0; i < 3; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        await tester.pump();
      }
    });
    expect(find.text('telegram-feed is locked'), findsNothing);
    expect(find.text('the feed'), findsOneWidget);
  });

  testWidgets('without a PIN nothing is asked', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LockGate(
          db: db,
          lock: lock,
          child: const Scaffold(body: Center(child: Text('the feed'))),
        ),
      ),
    );
    await tester.runAsync(() async {
      for (var i = 0; i < 3; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        await tester.pump();
      }
    });
    expect(find.text('the feed'), findsOneWidget);
    expect(find.text('telegram-feed is locked'), findsNothing);
  });

  testWidgets('the settings set a PIN, a timeout and the device check', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppLockScreen(db: db, lock: lock),
      ),
    );
    await tester.pump();
    await tester.pump();

    final fields = find.byType(TextField);
    await tester.enterText(fields.first, '12');
    await tester.tap(find.text('Set the PIN'));
    await tester.pump();
    expect(find.text('At least four digits'), findsOneWidget);

    await tester.enterText(fields.first, '1234');
    await tester.enterText(fields.last, '9999');
    await tester.tap(find.text('Set the PIN'));
    await tester.pump();
    expect(find.text('The two do not match'), findsOneWidget);

    await tester.enterText(fields.first, '1234');
    await tester.enterText(fields.last, '1234');
    await tester.tap(find.text('Set the PIN'));
    await tester.runAsync(() async {
      for (var i = 0; i < 3; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        await tester.pump();
      }
    });
    expect(await tester.runAsync(lock.hasPin), isTrue);
    expect(find.text('Replace the PIN'), findsOneWidget);

    await tester.tap(find.text('After five minutes'));
    await tester.runAsync(() async {
      for (var i = 0; i < 3; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        await tester.pump();
      }
    });
    expect(
      await tester.runAsync(() => lock.timeout),
      const Duration(minutes: 5),
    );

    await tester.tap(find.text('Remove the lock'));
    await tester.runAsync(() async {
      for (var i = 0; i < 3; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        await tester.pump();
      }
    });
    expect(await tester.runAsync(lock.hasPin), isFalse);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  });
}
