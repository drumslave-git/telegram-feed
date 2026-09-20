import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/host/accounts.dart';
import 'package:telegram_feed/settings/accounts_screen.dart';

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
    await store.rename(1, 'Reading');
    final fresh = AccountStore(dir.path);
    final now = await fresh.load();
    expect(now.active, 1);
    expect(now.accounts.first.label, 'Reading');
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

  testWidgets('the screen switches, adds and removes', (tester) async {
    var switches = 0;
    await tester.runAsync(store.add); // two accounts, the second in use
    // The screen reads the file in initState, which is real I/O: it has to start inside
    // runAsync, or the fake clock never lets it finish.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: AccountsScreen(
            store: store,
            onSwitched: () async => switches++,
          ),
        ),
      );
      for (var i = 0; i < 3; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        await tester.pump();
      }
    });

    expect(find.text('Account 1'), findsOneWidget);
    expect(find.text('Account 2'), findsOneWidget);
    expect(find.text('In use'), findsOneWidget);

    // The tap starts real I/O too, so it runs inside runAsync as well.
    await tester.runAsync(() async {
      await tester.tap(find.text('Account 1'));
      for (var i = 0; i < 4; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        await tester.pump();
      }
    });
    expect(switches, 1);
    expect(await tester.runAsync(store.activeId), 1);
  });
}
