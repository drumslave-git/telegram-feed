import 'package:app_db/app_db.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/main.dart' show themeModeFrom;
import 'package:telegram_feed/feeds/timeline_screen.dart';
import 'package:telegram_feed/settings/chat_settings_screen.dart';
import 'package:telegram_feed/settings/data_storage_screen.dart';
import 'package:telegram_feed/settings/notifications_screen.dart';
import 'package:telegram_feed/settings/privacy_screen.dart';
import 'package:telegram_feed/settings/read_aloud_screen.dart';
import 'package:telegram_feed/settings/settings_screen.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fixtures.dart';

class SettingsGateway extends ChannelsGateway {
  SettingsGateway() : super(const []);
  var files = 3;
  @override
  Future<UserInfo> me() async => const UserInfo(
    id: 9,
    firstName: 'Ann',
    lastName: 'Lee',
    username: 'ann',
    phoneNumber: '1555',
    bio: 'Reads a lot',
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

  Widget app([Widget? home]) => MaterialApp(
    home:
        home ??
        SettingsScreen(db: db, gateway: gw, onLogOut: () async => loggedOut++),
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

  /// Taps a row of the list, scrolling to it first.
  Future<void> open(WidgetTester tester, String row) async {
    await tester.scrollUntilVisible(
      find.text(row),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text(row));
    // Not pumpAndSettle: a screen that reads its settings shows a spinner until then.
    await tester.pump();
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 600));
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

  testWidgets('the profile on top and one row per screen, as short as the '
      'official list', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);
    expect(find.text('Ann Lee'), findsOneWidget);
    expect(find.text('@ann'), findsOneWidget);
    expect(find.text('+1555'), findsOneWidget);
    expect(find.text('Reads a lot'), findsOneWidget);
    expect(find.text('Telegram ID 9'), findsOneWidget);
    expect(find.text('A'), findsOneWidget); // initial while there is no photo
    // Screens, not settings: no switch lives on the first screen any more.
    for (final row in const [
      'Accounts',
      'Saved Messages',
      'Chat settings',
      'Privacy and security',
      'Notifications and sounds',
      'Data and storage',
      'Read aloud',
      'AI rules',
      'About telegram-feed',
      'Open-source licenses',
    ]) {
      await tester.scrollUntilVisible(
        find.text(row),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(row), findsOneWidget, reason: row);
    }
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.byType(Slider), findsNothing);
    // The official app signs its list; tests have no platform to ask for the version.
    expect(find.text('telegram-feed for Android'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('each row opens its screen', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);
    for (final (row, screen) in [
      ('Chat settings', ChatSettingsScreen),
      ('Privacy and security', PrivacyScreen),
      ('Notifications and sounds', NotificationsScreen),
      ('Data and storage', DataStorageScreen),
      ('Read aloud', ReadAloudScreen),
    ]) {
      await open(tester, row);
      expect(find.byType(screen), findsOneWidget, reason: row);
      await tester.pageBack();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }
    await unmount(tester);
  });

  testWidgets('log out sits in the menu and asks for confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await settle(tester);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();
    expect(find.text('Log out?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Log out'));
    await tester.pumpAndSettle();
    expect(loggedOut, 1);
    await unmount(tester);
  });

  testWidgets('chat settings: the theme and the text size of posts', (
    tester,
  ) async {
    await tester.pumpWidget(app(ChatSettingsScreen(db: db)));
    await settle(tester);
    expect(find.text('100 %'), findsOneWidget);
    expect(find.text('A post is drawn at this size.'), findsOneWidget);
    await tester.tap(find.text('Dark'));
    await settle(tester);
    await tester.runAsync(
      () async => expect(await db.setting(SettingKeys.themeMode), 'dark'),
    );
    await unmount(tester);
  });

  testWidgets('privacy: the app lock row and read sync', (tester) async {
    await tester.pumpWidget(app(PrivacyScreen(db: db)));
    await settle(tester);
    expect(find.text('App lock'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);

    final readSync = find.widgetWithText(
      SwitchListTile,
      'Mark posts read in Telegram',
    );
    expect(tester.widget<SwitchListTile>(readSync).value, isTrue);
    await tester.tap(readSync);
    await settle(tester);
    expect(tester.widget<SwitchListTile>(readSync).value, isFalse);
    await tester.runAsync(
      () async => expect(await db.syncReadToTelegram(), isFalse),
    );
    await unmount(tester);
  });

  testWidgets('notifications: the rule sounds and the background switch', (
    tester,
  ) async {
    await tester.pumpWidget(app(NotificationsScreen(db: db)));
    await settle(tester);
    expect(find.text('Normal rules: sound'), findsOneWidget);
    final background = find.widgetWithText(
      SwitchListTile,
      'Watch channels in the background',
    );
    await tester.scrollUntilVisible(
      background,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(background);
    await settle(tester);
    await tester.runAsync(
      () async =>
          expect(await db.setting(SettingKeys.backgroundWatching), 'false'),
    );
    await unmount(tester);
  });

  testWidgets('data and storage: the storage screen measures and clears the '
      'cache', (tester) async {
    await tester.pumpWidget(app(DataStorageScreen(db: db, gateway: gw)));
    await settle(tester);
    expect(find.text('3.5 MB'), findsOneWidget);
    await tester.tap(find.text('Storage usage'));
    await tester.pumpAndSettle();
    await settle(tester);
    expect(find.text('3 files'), findsOneWidget);
    expect(find.text('512 KB'), findsOneWidget);
    await tester.tap(find.text('Clear cache (3.0 MB)'));
    await settle(tester);
    expect(find.text('0 files'), findsOneWidget);
    // Back on Data and storage, the row says what is left.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await settle(tester);
    expect(find.text('512 KB'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('Saved Messages opens as a timeline of its own', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Saved Messages'));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    // The screen it opens is a timeline with that title.
    expect(find.byType(TimelineScreen), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Saved Messages'),
      ),
      findsOneWidget,
    );

    // The timeline keeps a database stream of its own; take it down first.
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  });
}
