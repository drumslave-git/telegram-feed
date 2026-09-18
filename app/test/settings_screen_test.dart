import 'package:app_db/app_db.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/main.dart' show themeModeFrom;
import 'package:telegram_feed/settings/settings_screen.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'feeds_screen_test.dart' show ChannelsGateway;

class SettingsGateway extends ChannelsGateway {
  SettingsGateway() : super(const []);
  var files = 3;
  @override
  Future<UserInfo> me() async => const UserInfo(
    id: 9,
    firstName: 'Ann',
    lastName: 'Lee',
    username: 'ann',
    phoneNumber: '+1555',
  );
  @override
  Future<StorageStats> storageStats() async => StorageStats(
    filesBytes: files * 1024 * 1024,
    fileCount: files,
    databaseBytes: 512 * 1024,
  );
  @override
  Future<StorageStats> clearCache() {
    files = 0;
    return storageStats();
  }
}

void main() {
  late AppDatabase db;
  late SettingsGateway gw;
  var loggedOut = 0;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    gw = SettingsGateway();
    loggedOut = 0;
  });

  Widget app() => MaterialApp(
    home: SettingsScreen(
      db: db,
      gateway: gw,
      onLogOut: () async => loggedOut++,
    ),
  );

  Future<void> settle(WidgetTester tester) => tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await tester.pump();
  });

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  test('formatBytes and themeModeFrom', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(3 * 1024 * 1024 + 512 * 1024), '3.5 MB');
    expect(formatBytes(20 * 1024 * 1024), '20 MB');
    expect(themeModeFrom(null), ThemeMode.system);
    expect(themeModeFrom('dark'), ThemeMode.dark);
    expect(themeModeFrom('light'), ThemeMode.light);
  });

  testWidgets('account, storage, cache clearing, toggles', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await settle(tester);
    expect(find.text('Ann Lee'), findsOneWidget);
    expect(find.text('@ann · +1555'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('3.5 MB'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('3.5 MB'), findsOneWidget);

    await tester.ensureVisible(find.text('Clear cache'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear cache'));
    await settle(tester);
    expect(find.text('512 KB'), findsOneWidget);
    expect(find.textContaining('0 cached files'), findsOneWidget);

    // Reading toggle writes the setting.
    final readSync = find.widgetWithText(
      SwitchListTile,
      'Mark posts read in Telegram',
    );
    expect(tester.widget<SwitchListTile>(readSync).value, isTrue);
    await tester.ensureVisible(readSync);
    await tester.pumpAndSettle();
    await tester.tap(readSync);
    await settle(tester);
    expect(tester.widget<SwitchListTile>(readSync).value, isFalse);
    await tester.runAsync(
      () async => expect(await db.syncReadToTelegram(), isFalse),
    );

    // Autoplay: on by default, the switch and a limit write their settings.
    final autoplay = find.widgetWithText(
      SwitchListTile,
      'Autoplay short videos',
    );
    await tester.ensureVisible(autoplay);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(autoplay).value, isTrue);
    await tester.tap(find.text('1 min'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30 s').last);
    await settle(tester);
    await tester.tap(autoplay);
    await settle(tester);
    await tester.runAsync(() async {
      expect(await db.setting(SettingKeys.autoplayMaxSeconds), '30');
      expect(await db.setting(SettingKeys.autoplay), 'false');
    });

    // Appearance.
    await tester.ensureVisible(find.text('Dark'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await settle(tester);
    await tester.runAsync(
      () async => expect(await db.setting(SettingKeys.themeMode), 'dark'),
    );
    await unmount(tester);
  });

  testWidgets('log out asks for confirmation', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);
    await tester.tap(find.byIcon(Icons.logout).last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Log out'));
    await tester.pumpAndSettle();
    expect(loggedOut, 1);
    await unmount(tester);
  });
}
