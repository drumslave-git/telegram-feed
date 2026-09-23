import 'package:app_db/app_db.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/main.dart' show themeModeFrom;
import 'package:telegram_feed/feeds/timeline_screen.dart';
import 'package:telegram_feed/media/auto_download.dart';
import 'package:telegram_feed/settings/chat_settings_screen.dart';
import 'package:telegram_feed/settings/data_storage_screen.dart';
import 'package:telegram_feed/settings/notifications_screen.dart';
import 'package:telegram_feed/settings/privacy_screen.dart';
import 'package:telegram_feed/settings/read_aloud_screen.dart';
import 'package:telegram_feed/settings/settings_screen.dart';
import 'package:telegram_feed/widgets/destructive_button.dart';
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
    // Two initials while there is no photo, as the official app draws them.
    expect(find.text('AL'), findsOneWidget);
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
      'About Unofficial Telegram Feed',
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
    expect(find.text('Unofficial Telegram Feed for Android'), findsOneWidget);
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
    await tester.tap(find.widgetWithText(DestructiveButton, 'Log out'));
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

    // Reading always reaches Telegram, as in the official app: no switch for it.
    expect(find.text('Mark posts read in Telegram'), findsNothing);
    await unmount(tester);
  });

  testWidgets('notifications: the rule sounds and the background switch', (
    tester,
  ) async {
    await tester.pumpWidget(app(NotificationsScreen(db: db)));
    await settle(tester);
    expect(find.text('Normal rules: sound'), findsOneWidget);
    // The badges count posts until the switch says channels (J-1).
    final countPosts = find.widgetWithText(
      SwitchListTile,
      'Count unread posts',
    );
    await tester.scrollUntilVisible(
      countPosts,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.widget<SwitchListTile>(countPosts).value, isTrue);
    await tester.tap(countPosts);
    await settle(tester);
    await tester.runAsync(
      () async =>
          expect(await db.setting(SettingKeys.countUnreadPosts), 'false'),
    );
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
    await tester.pumpAndSettle();
    // It asks first, naming how much goes.
    expect(find.text('Clear 3.0 MB of cache?'), findsOneWidget);
    await tester.tap(find.text('Clear'));
    await settle(tester);
    expect(find.text('0 files'), findsOneWidget);
    // Back on Data and storage, the row says what is left.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await settle(tester);
    expect(find.text('512 KB'), findsOneWidget);
    await unmount(tester);
  });

  Future<DownloadPreset> stored(WidgetTester tester, Connection c) async =>
      DownloadPreset.decode(
        await tester.runAsync<String?>(() => db.setting(c.settingKey)),
        c.defaults,
      );

  testWidgets('data and storage: a row per connection with its switch, the '
      'autoplay switches and the reset', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(DataStorageScreen(db: db, gateway: gw)));
    await settle(tester);
    expect(find.text('When using mobile data'), findsOneWidget);
    expect(find.text('Photos, Videos (10 MB), Files (1 MB)'), findsOneWidget);
    expect(find.text('When connected on Wi-Fi'), findsOneWidget);
    expect(find.text('Photos, Videos (15 MB), Files (3 MB)'), findsOneWidget);
    expect(find.text('When roaming'), findsOneWidget);
    expect(find.text('Photos'), findsOneWidget);
    final reset = find.widgetWithText(ListTile, 'Reset auto-download settings');
    // Nothing to reset while every connection has Telegram's default.
    expect(tester.widget<ListTile>(reset).enabled, isFalse);

    // The switch beside a row turns the whole connection off, and only that.
    final rowSwitches = find.descendant(
      of: find.byType(SplitSwitchTile),
      matching: find.byType(Switch),
    );
    await tester.tap(rowSwitches.first);
    await settle(tester);
    expect(find.text('Disabled'), findsOneWidget);
    expect((await stored(tester, Connection.mobile)).enabled, isFalse);
    expect(
      (await stored(
        tester,
        Connection.mobile,
      )).sameKindsAs(DownloadPreset.medium),
      isTrue,
    );
    expect(tester.widget<ListTile>(reset).enabled, isTrue);

    // Autoplay: GIFs and videos, each its own switch.
    await tester.tap(find.widgetWithText(SwitchListTile, 'GIFs'));
    await settle(tester);
    await tester.runAsync(
      () async => expect(await db.setting(SettingKeys.autoplayGifs), 'false'),
    );
    expect(
      tester
          .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Videos'))
          .value,
      isTrue,
    );

    await tester.tap(reset);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Reset'));
    await tester.pumpAndSettle();
    await settle(tester);
    expect(await stored(tester, Connection.mobile), DownloadPreset.medium);
    expect(find.text('Disabled'), findsNothing);
    await unmount(tester);
  });

  testWidgets('a connection screen: the presets on the slider, the kinds of '
      'media and their limits', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      app(AutoDownloadScreen(db: db, connection: Connection.mobile)),
    );
    await settle(tester);
    expect(find.text('Using mobile data'), findsOneWidget);
    expect(find.text('Auto-download media'), findsOneWidget);
    for (final name in ['Low', 'Medium', 'High']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.text('Custom'), findsNothing);
    expect(find.text('Up to 10 MB'), findsOneWidget);
    expect(find.text('Up to 1 MB'), findsOneWidget);

    // The slider picks Telegram's High.
    final usage = find.descendant(
      of: find.byType(DataUsageSlider),
      matching: find.byType(Slider),
    );
    tester.widget<Slider>(usage).onChanged!(2);
    await settle(tester);
    expect(
      (await stored(
        tester,
        Connection.mobile,
      )).sameKindsAs(DownloadPreset.high),
      isTrue,
    );
    expect(find.text('Up to 15 MB'), findsOneWidget);

    // Videos: a larger limit and no preloading, saved from the sheet.
    await tester.tap(find.text('Videos'));
    await tester.pumpAndSettle();
    expect(find.text('Maximum video size'), findsOneWidget);
    final size = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(Slider),
    );
    tester.widget<Slider>(size).onChanged!(
      downloadSizeStep(50 * 1024 * 1024).toDouble(),
    );
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Up to 50 MB'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Preload larger videos'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    await settle(tester);
    final own = await stored(tester, Connection.mobile);
    expect(own.videoMaxBytes, 50 * 1024 * 1024);
    expect(own.preloadLargeVideos, isFalse);
    // A choice of one's own sits on the slider as Custom, past High here.
    expect(find.text('Custom'), findsOneWidget);
    expect(find.text('Up to 50 MB'), findsOneWidget);

    // Off, nothing below can be changed.
    await tester.tap(find.text('Auto-download media'));
    await settle(tester);
    expect((await stored(tester, Connection.mobile)).enabled, isFalse);
    final kinds = find.descendant(
      of: find.byType(SplitSwitchTile),
      matching: find.byType(Switch),
    );
    expect(kinds, findsNWidgets(3));
    for (final e in kinds.evaluate()) {
      expect((e.widget as Switch).onChanged, isNull);
    }
    expect(tester.widget<Slider>(usage).onChanged, isNull);
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
