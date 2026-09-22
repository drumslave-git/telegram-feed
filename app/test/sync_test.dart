import 'dart:convert';

import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:telegram_feed/sync/drive_auth.dart';
import 'package:telegram_feed/sync/drive_sync_store.dart';
import 'package:telegram_feed/sync/sync_controller.dart';
import 'package:telegram_feed/sync/sync_settings_screen.dart';

/// Google Drive's files API, in memory, for the app data folder.
final class FakeDrive {
  final files = <String, String>{}; // id -> content
  final names = <String, String>{}; // id -> name
  final log = <String>[];
  String validToken = 'token-1';

  http.Client get client => MockClient((r) async {
    log.add('${r.method} ${r.url.path}');
    if (r.headers['authorization'] != 'Bearer $validToken') {
      return http.Response(
        jsonEncode({
          'error': {'message': 'Invalid Credentials'},
        }),
        401,
      );
    }
    final path = r.url.path;
    if (r.method == 'GET' && path == '/drive/v3/files') {
      expect(r.url.queryParameters['spaces'], 'appDataFolder');
      return http.Response(
        jsonEncode({
          'files': [
            for (final id in names.keys) {'id': id},
          ],
        }),
        200,
      );
    }
    if (r.method == 'GET' && path.startsWith('/drive/v3/files/')) {
      final id = path.split('/').last;
      return files.containsKey(id)
          ? http.Response.bytes(utf8.encode(files[id]!), 200)
          : http.Response('{}', 404);
    }
    if (r.method == 'POST' && path == '/upload/drive/v3/files') {
      final parts = r.body.split('--telegram-feed-sync-boundary');
      final metadata = jsonDecode(parts[1].split('\r\n\r\n')[1].trim()) as Map;
      expect(metadata['parents'], ['appDataFolder']);
      final id = 'file-${files.length + 1}';
      names[id] = metadata['name'] as String;
      files[id] = parts[2].split('\r\n\r\n')[1].trimRight();
      return http.Response(jsonEncode({'id': id}), 200);
    }
    if (r.method == 'PATCH' && path.startsWith('/upload/drive/v3/files/')) {
      files[path.split('/').last] = utf8.decode(r.bodyBytes);
      return http.Response('{}', 200);
    }
    return http.Response('unexpected', 500);
  });
}

final class FakeAuth implements DriveAuth {
  FakeAuth({this.configured = true});
  final bool configured;
  String? account;
  String token = 'token-1';
  String freshToken = 'token-1';
  bool cancel = false;

  @override
  bool get isConfigured => configured;

  String? restoredWith;

  @override
  Future<String?> restore({String? knownEmail}) async {
    restoredWith = knownEmail;
    return account;
  }

  @override
  Future<String> signIn() async {
    if (cancel) throw const SyncException('Sign-in was cancelled.');
    return account = 'me@example.com';
  }

  @override
  Future<String?> accessToken({bool fresh = false}) async =>
      account == null ? null : (fresh ? token = freshToken : token);

  @override
  Future<void> signOut() async => account = null;
}

void main() {
  group('DriveSyncStore', () {
    test(
      'creates the file in appDataFolder, then updates and reads it',
      () async {
        final drive = FakeDrive();
        final store = DriveSyncStore(
          ({fresh = false}) async => 'token-1',
          client: drive.client,
        );
        expect(await store.read(), isNull);
        await store.write('{"v":1,"имя":"тест"}');
        expect(drive.names.values.single, DriveSyncStore.fileName);
        await store.write('{"v":2}');
        expect(drive.files, hasLength(1));
        expect(await store.read(), '{"v":2}');

        // A second device finds the same file by name.
        final other = DriveSyncStore(
          ({fresh = false}) async => 'token-1',
          client: drive.client,
        );
        expect(await other.read(), '{"v":2}');
      },
    );

    test(
      'an expired token is refreshed once; other failures are readable',
      () async {
        final drive = FakeDrive()..validToken = 'token-2';
        var asked = <bool>[];
        final store = DriveSyncStore(({fresh = false}) async {
          asked.add(fresh);
          return fresh ? 'token-2' : 'token-1';
        }, client: drive.client);
        expect(await store.read(), isNull);
        expect(asked, [false, true]);

        final locked = DriveSyncStore(
          ({fresh = false}) async => 'wrong',
          client: drive.client,
        );
        await expectLater(
          locked.read(),
          throwsA(
            isA<SyncException>().having(
              (e) => e.message,
              'message',
              allOf(contains('401'), contains('Invalid Credentials')),
            ),
          ),
        );
        final signedOut = DriveSyncStore(
          ({fresh = false}) async => null,
          client: drive.client,
        );
        await expectLater(signedOut.read(), throwsA(isA<SyncException>()));
      },
    );
  });

  group('SyncController', () {
    late AppDatabase db;
    late FakeDrive drive;
    late FakeAuth auth;
    var now = DateTime(2026, 3, 1, 10);

    SyncController controller() => SyncController(
      db: db,
      auth: auth,
      store: DriveSyncStore(auth.accessToken, client: drive.client),
      clock: () => now,
      debounce: const Duration(milliseconds: 20),
      interval: const Duration(hours: 1),
    );

    setUp(() {
      db = AppDatabase(NativeDatabase.memory(), clock: () => now);
      drive = FakeDrive();
      auth = FakeAuth();
      now = DateTime(2026, 3, 1, 10);
    });
    tearDown(() => db.close());

    test(
      'turning on signs in, syncs, and later edits sync by themselves',
      () async {
        await db.createFeed('News');
        final c = controller();
        await c.start();
        expect(c.status.value.isOn, isFalse);

        await c.turnOn();
        expect(c.status.value.account, 'me@example.com');
        expect(c.status.value.lastSyncedAt, now);
        expect(c.status.value.error, isNull);
        expect(drive.files.values.single, contains('News'));
        expect(await db.setting(SyncKeys.enabled), 'true');

        await db.createFeed('Tech');
        await Future<void>.delayed(const Duration(milliseconds: 120));
        expect(drive.files.values.single, contains('Tech'));
        // Sync bookkeeping itself never travels.
        expect(drive.files.values.single, isNot(contains('sync.')));
        await c.dispose();
      },
    );

    test(
      'a sync does not set off the next one: only synced data does',
      () async {
        await db.createFeed('News');
        final c = controller();
        await c.turnOn();
        await Future<void>.delayed(const Duration(milliseconds: 200));
        final quiet = drive.log.length;
        // Each run records its time in the settings table, which the watcher sees too; so
        // do device-local settings. Neither is a reason to talk to Drive.
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(drive.log.length, quiet);
        await db.setSetting('ai.lastFailure', 'local note');
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(drive.log.length, quiet);

        await db.setSetting(
          SettingKeys.themeMode,
          'dark',
        ); // travels between devices
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(drive.log.length, greaterThan(quiet));
        expect(drive.files.values.single, contains('dark'));
        await c.dispose();
      },
    );

    test('a restart resumes sync; a lost Google session is reported', () async {
      final first = controller();
      await first.turnOn();
      await first.dispose();

      final resumed = controller();
      await resumed.start();
      // The account signed in with before is handed over, so no Google sheet is needed.
      expect(auth.restoredWith, 'me@example.com');
      await resumed.syncNow();
      expect(resumed.status.value.account, 'me@example.com');
      expect(resumed.status.value.lastSyncedAt, isNotNull);
      await resumed.dispose();

      auth.account = null;
      final lost = controller();
      await lost.start();
      expect(lost.status.value.isOn, isFalse);
      expect(lost.status.value.error, contains('Sign in again'));
      await lost.dispose();
    });

    test('errors are shown and cleared; turning off stops syncing', () async {
      final c = controller();
      auth.cancel = true;
      await c.turnOn();
      expect(c.status.value.error, 'Sign-in was cancelled.');
      expect(c.status.value.isOn, isFalse);

      auth.cancel = false;
      await c.turnOn();
      expect(c.status.value.error, isNull);

      drive.validToken = 'rotated';
      await c.syncNow();
      expect(c.status.value.error, contains('401'));
      auth.freshToken = 'rotated';
      await c.syncNow();
      expect(c.status.value.error, isNull);

      await c.turnOff();
      expect(c.status.value.isOn, isFalse);
      expect(auth.account, isNull);
      final before = drive.log.length;
      await db.createFeed('after off');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(drive.log.length, before);
      await c.dispose();
    });
  });

  testWidgets('sync screen: unavailable build, off, on', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final unavailable = SyncController(
      db: db,
      auth: FakeAuth(configured: false),
    );
    await tester.pumpWidget(
      MaterialApp(home: SyncSettingsScreen(controller: unavailable)),
    );
    expect(find.textContaining('without a Google client id'), findsOneWidget);
    expect(find.text('Sign in with Google and sync'), findsNothing);

    final drive = FakeDrive();
    final auth = FakeAuth();
    final c = SyncController(
      db: db,
      auth: auth,
      store: DriveSyncStore(auth.accessToken, client: drive.client),
    );
    await tester.pumpWidget(
      MaterialApp(home: SyncSettingsScreen(controller: c)),
    );
    expect(find.text('Sign in with Google and sync'), findsOneWidget);
    await tester.runAsync(c.turnOn);
    await tester.pump();
    expect(find.text('me@example.com'), findsOneWidget);
    expect(find.textContaining('Last synced'), findsOneWidget);
    expect(find.text('Sync now'), findsOneWidget);
    await tester.runAsync(c.turnOff);
    await tester.pump();
    expect(find.text('Sign in with Google and sync'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(c.dispose);
  });

  testWidgets('the last sync names its day unless it was today', (
    tester,
  ) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            ctx = context;
            return const SizedBox();
          },
        ),
      ),
    );
    final now = DateTime(2026, 9, 22, 18);
    String at(DateTime t) => SyncSettingsScreen.syncedAt(t, ctx, now: now);
    expect(at(DateTime(2026, 9, 22, 14, 32)), 'at 2:32 PM');
    expect(at(DateTime(2026, 9, 21, 14, 32)), 'yesterday at 2:32 PM');
    expect(at(DateTime(2026, 9, 20, 14, 32)), 'Sep 20 at 2:32 PM');
  });
}
