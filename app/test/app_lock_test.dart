import 'package:app_db/app_db.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/settings/app_lock.dart';

/// The keystore, in memory: the plugin needs a device.
class FakeStore implements LockStore {
  final values = <String, String>{};

  /// The stored hash of the PIN.
  String? get value => values['lock.pin'];

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String? v) async {
    if (v == null) {
      values.remove(key);
    } else {
      values[key] = v;
    }
  }
}

void main() {
  late AppDatabase db;
  late FakeStore store;
  late AppLock lock;
  late DateTime now;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = FakeStore();
    now = DateTime(2026, 10, 3, 12);
    lock = AppLock(store: store, clock: () => now);
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

  test('the lock belongs to the device: it is on while a PIN exists, whatever '
      "an account's database says", () async {
    await db.setSetting(SettingKeys.lockEnabled, 'true');
    expect(await lock.enabled, isFalse);
    await lock.setPin('9999');
    expect(await lock.enabled, isTrue);
    // Another account, or the same one after a logout wiped its database.
    await db.setSetting(SettingKeys.lockEnabled, 'false');
    expect(await lock.enabled, isTrue);
    expect(await AppLock(store: store).enabled, isTrue);
  });

  test('the timeout and the fingerprint switch of an older build are taken '
      'over once', () async {
    await db.setSetting(SettingKeys.lockTimeout, '300');
    await db.setSetting(SettingKeys.lockBiometrics, 'true');
    // Without a PIN there was no lock to take over.
    await lock.adoptLegacy(db);
    expect(await lock.timeout, const Duration(hours: 1));

    await lock.setPin('1234');
    await lock.adoptLegacy(db);
    expect(await lock.timeout, const Duration(minutes: 5));
    expect(await lock.biometrics, isTrue);

    // What the reader picks afterwards is not overwritten.
    await lock.setTimeout(60);
    await lock.adoptLegacy(db);
    expect(await lock.timeout, const Duration(minutes: 1));
  });

  test('from the third wrong PIN the next try has to wait, as in the '
      'official app', () async {
    await lock.setPin('1234');
    expect(await lock.check('0000'), isFalse);
    expect(await lock.check('0000'), isFalse);
    expect(await lock.retryIn(), Duration.zero);

    final waits = <int>[];
    for (var i = 0; i < 7; i++) {
      expect(await lock.check('0000'), isFalse);
      final wait = await lock.retryIn();
      waits.add(wait.inSeconds);
      // While it waits even the right PIN is refused.
      expect(await lock.check('1234'), isFalse);
      now = now.add(wait);
    }
    expect(waits, [5, 10, 15, 20, 25, 30, 30]);

    // The right PIN clears the count.
    expect(await lock.check('1234'), isTrue);
    expect(await lock.check('0000'), isFalse);
    expect(await lock.retryIn(), Duration.zero);
  });

  testWidgets('a locked app shows nothing until the PIN is right', (
    tester,
  ) async {
    await tester.runAsync(() => lock.setPin('1234'));
    await tester.pumpWidget(
      MaterialApp(
        home: LockGate(
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

    expect(find.text('Unofficial Telegram Feed is locked'), findsOneWidget);
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
    expect(find.text('Unofficial Telegram Feed is locked'), findsNothing);
    expect(find.text('the feed'), findsOneWidget);
  });

  testWidgets('without a PIN nothing is asked', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LockGate(
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
    expect(find.text('Unofficial Telegram Feed is locked'), findsNothing);
  });

  testWidgets('with a PIN set, the lock settings ask for it first', (
    tester,
  ) async {
    await tester.runAsync(() => lock.setPin('4321'));
    await tester.pumpWidget(MaterialApp(home: AppLockScreen(lock: lock)));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump();
    expect(find.text('Enter your PIN to change the lock'), findsOneWidget);
    expect(find.text('Remove the lock'), findsNothing);
    await tester.enterText(find.byType(TextField), '4321');
    await tester.tap(find.text('Unlock'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump();
    expect(find.text('Remove the lock'), findsOneWidget);
    // Until the reader picks another, the lock asks again after an hour.
    expect(await tester.runAsync(() => lock.timeout), const Duration(hours: 1));

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('the settings set a PIN, a timeout and the device check', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: AppLockScreen(lock: lock)));
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
    await tester.pumpAndSettle();
    expect(find.text('Remove the lock?'), findsOneWidget);
    await tester.tap(find.text('Remove'));
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
