import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/home/unread_badge.dart';
import 'package:telegram_feed/host/account_record.dart';
import 'package:telegram_feed/host/accounts.dart';
import 'package:telegram_feed/settings/account_rows.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'settings_screen_test.dart' show SettingsGateway;

void main() {
  late Directory dir;
  late AccountStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('accounts');
    store = AccountStore(dir.path);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test(
    'a device with no file has one account, which is the one in use',
    () async {
      final now = await store.load();
      expect(now.accounts.map((a) => a.id), [1]);
      expect(now.active, 1);
    },
  );

  test('accounts are added up to four, and the new one is used', () async {
    final second = await store.add();
    expect(second!.id, 2);
    expect(await store.activeId(), 2);
    expect((await store.add())!.id, 3);
    expect((await store.add())!.id, 4);
    // Four is as many as the official app holds.
    expect(await store.add(), isNull);
  });

  test('switching and naming an account survive a reload', () async {
    await store.add();
    await store.setActive(1);
    await store.update(1, name: 'Reading', phone: '+1555', unread: 3);
    final fresh = AccountStore(dir.path);
    final now = await fresh.load();
    expect(now.active, 1);
    expect(now.accounts.first.name, 'Reading');
    expect(now.accounts.first.phone, '+1555');
    expect(now.accounts.first.unread, 3);
    // What is not given stays.
    await fresh.update(1, unread: 0);
    expect((await fresh.load()).accounts.first.name, 'Reading');
    // An id that is not there changes nothing.
    await fresh.setActive(9);
    expect(await fresh.activeId(), 1);
  });

  test('removing an account deletes its data; the last one stays', () async {
    final second = await store.add();
    final tdlib = Directory('${dir.path}/tdlib-2')..createSync(recursive: true);
    File('${tdlib.path}/db.sqlite').writeAsStringSync('x');
    final db = File('${dir.path}/app-2.sqlite')..writeAsStringSync('x');

    expect(
      await store.remove(second!.id, tdlib: tdlib.path, db: db.path),
      isTrue,
    );
    expect(tdlib.existsSync(), isFalse);
    expect(db.existsSync(), isFalse);
    // The account that is left becomes the one in use.
    expect(await store.activeId(), 1);

    expect(
      await store.remove(
        1,
        tdlib: '${dir.path}/tdlib',
        db: '${dir.path}/app.sqlite',
      ),
      isFalse,
    );
  });

  test('a broken file does not lock the reader out', () async {
    File('${dir.path}/accounts.json').writeAsStringSync('not json at all');
    final now = await store.load();
    expect(now.accounts.map((a) => a.id), [1]);
    expect(now.active, 1);
  });

  test('the paths of an account follow from its id; account 1 keeps the old '
      'ones', () {
    expect(store.tdlibOf(1), '${dir.path}/tdlib');
    expect(store.dbOf(1), '${dir.path}/app.sqlite');
    expect(store.tdlibOf(3), '${dir.path}/tdlib-3');
    expect(store.dbOf(3), '${dir.path}/app-3.sqlite');
  });

  test('an account that was added and never logged in is dropped with its '
      'data; one in use and one of an older build stay', () async {
    // An older build's file: nothing says whether its accounts logged in.
    File('${dir.path}/accounts.json').writeAsStringSync(
      '{"active":1,"accounts":[{"id":1,"label":"Ann · +1555"},'
      '{"id":2,"label":""}]}',
    );
    final third = await store.add();
    expect(third!.id, 3);
    expect(third.loggedIn, isFalse);
    Directory(store.tdlibOf(3)).createSync(recursive: true);
    File(store.dbOf(3)).writeAsStringSync('x');
    Directory(store.tdlibOf(2)).createSync(recursive: true);

    // While it is the one in use it may be logging in: it stays.
    await store.dropNeverLoggedIn();
    expect((await store.load()).accounts.map((a) => a.id), [1, 2, 3]);

    // The reader went back to another account: it goes, and what it had with it.
    await store.setActive(1);
    await store.dropNeverLoggedIn();
    final now = await store.load();
    expect(now.accounts.map((a) => a.id), [1, 2]);
    expect(Directory(store.tdlibOf(3)).existsSync(), isFalse);
    expect(File(store.dbOf(3)).existsSync(), isFalse);
    // The older build's second account is not known to be empty: untouched.
    expect(Directory(store.tdlibOf(2)).existsSync(), isTrue);
    expect(now.accounts.first.title, 'Ann · +1555');
  });

  test('an account that logged in is never dropped', () async {
    final second = await store.add();
    await AccountRecorder(store, second!.id).loggedIn();
    await store.setActive(1);
    await store.dropNeverLoggedIn();
    expect((await store.load()).accounts.map((a) => a.id), [1, 2]);
  });

  test('the recorder keeps the profile with a copy of the photo, and forgets '
      'both at a logout', () async {
    final photo = File('${dir.path}/tdlib/photo.jpg')
      ..createSync(recursive: true)
      ..writeAsStringSync('jpeg');
    final recorder = AccountRecorder(store, 1);
    await recorder.profile(
      const UserInfo(
        id: 9,
        firstName: 'Ann',
        lastName: 'Lee',
        phoneNumber: '1555',
      ),
      photoPath: photo.path,
    );
    await recorder.unread(7);
    var me = (await store.load()).accounts.single;
    expect(me.name, 'Ann Lee');
    expect(me.phone, '+1555');
    expect(me.unread, 7);
    expect(me.loggedIn, isTrue);
    // A copy outside the account's own TDLib directory.
    expect(me.photo, store.photoOf(1));
    expect(File(me.photo).readAsStringSync(), 'jpeg');

    await recorder.loggedOut();
    me = (await store.load()).accounts.single;
    expect(me.title, isEmpty);
    expect(me.unread, 0);
    expect(me.loggedIn, isFalse);
    expect(File(store.photoOf(1)).existsSync(), isFalse);
  });

  /// Real file I/O under a widget test has to run inside runAsync, or the fake clock
  /// never lets it finish.
  Future<void> settle(WidgetTester tester) => tester.runAsync(() async {
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await tester.pump();
    }
  });

  testWidgets('the home screen of a logged-in account records its profile and '
      'its unread count', (tester) async {
    await tester.runAsync(store.add);
    late ValueChanged<int> report;
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: AccountRecord(
            gateway: SettingsGateway(),
            store: store,
            builder: (context, onUnread) {
              report = onUnread;
              return const SizedBox();
            },
          ),
        ),
      );
    });
    // Whether or not the store is read by now, the count is written once it is.
    await tester.runAsync(() async => report(4));
    await settle(tester);
    var second = (await tester.runAsync(store.load))!.accounts.last;
    expect(second.id, 2);
    expect(second.loggedIn, isTrue);
    expect(second.name, 'Ann Lee');
    expect(second.phone, '+1555');
    expect(second.unread, 4);

    await tester.runAsync(() async => report(1));
    await settle(tester);
    second = (await tester.runAsync(store.load))!.accounts.last;
    expect(second.unread, 1);
  });

  testWidgets('the other accounts are rows with name, phone and unread count; '
      'a tap switches, a long press removes', (tester) async {
    var switches = 0;
    await tester.runAsync(() async {
      await store.update(1, name: 'Ann Lee', phone: '+1555', loggedIn: true);
      final second = await store.add();
      await store.update(
        second!.id,
        name: 'Bo Reader',
        phone: '+1777',
        unread: 12,
        loggedIn: true,
      );
      final third = await store.add(); // in use from here on
      await store.update(third!.id, name: 'Cy', loggedIn: true);
      Directory(store.tdlibOf(2)).createSync(recursive: true);
    });
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccountRows(store: store, onSwitched: () async => switches++),
          ),
        ),
      );
    });
    await settle(tester);

    // The account in use is the profile on top of Settings, not a row here.
    expect(find.text('Cy'), findsNothing);
    expect(find.text('Ann Lee'), findsOneWidget);
    expect(find.text('+1555'), findsOneWidget);
    expect(find.text('Bo Reader'), findsOneWidget);
    expect(find.text('+1777'), findsOneWidget);
    // Initials while there is no photo.
    expect(find.text('BR'), findsOneWidget);
    // The unread count of the one that has unread channels, and of no other.
    expect(find.byType(UnreadBadge), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('account-2')),
        matching: find.text('12'),
      ),
      findsOneWidget,
    );
    expect(find.text('Add an account'), findsOneWidget);

    // A long press asks, then takes the account and its data off the device.
    // The press is held in real time: what it starts writes the accounts file, and a
    // change begun under the fake clock never finishes.
    await tester.runAsync(() async {
      final press = await tester.startGesture(
        tester.getCenter(find.text('Bo Reader')),
      );
      await Future<void>.delayed(const Duration(milliseconds: 700));
      await press.up();
      await tester.pump();
    });
    await tester.pump();
    expect(find.text('Remove Bo Reader?'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('Remove'));
      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        await tester.pump();
      }
    });
    await settle(tester);
    expect(find.text('Bo Reader'), findsNothing);
    expect(Directory(store.tdlibOf(2)).existsSync(), isFalse);
    expect(switches, 0);

    // A tap switches.
    await tester.runAsync(() async {
      await tester.tap(find.text('Ann Lee'));
      for (var i = 0; i < 4; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        await tester.pump();
      }
    });
    expect(switches, 1);
    expect(await tester.runAsync(store.activeId), 1);
  });

  testWidgets('an account whose login was given up has no row, and four '
      'accounts leave no room for another', (tester) async {
    await tester.runAsync(() async {
      await store.update(1, name: 'Ann Lee', loggedIn: true);
      await store.add(); // never logs in
      await store.setActive(1);
    });
    Future<void> show() async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: AccountRows(store: store)),
          ),
        );
      });
      await settle(tester);
    }

    await show();
    expect(find.text('Account 2'), findsNothing);
    expect(find.byType(ListTile), findsOneWidget);
    expect(find.text('Add an account'), findsOneWidget);
    expect((await tester.runAsync(store.load))!.accounts.map((a) => a.id), [1]);

    // Four accounts that logged in: every other one is a row, and nothing is added.
    await tester.runAsync(() async {
      for (var i = 0; i < 3; i++) {
        final a = await store.add();
        await store.update(a!.id, loggedIn: true);
      }
      await store.setActive(1);
    });
    await show();
    // Until its profile is known an account goes by its number.
    for (final name in ['Account 2', 'Account 3', 'Account 4']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.text('Add an account'), findsNothing);
  });
}
