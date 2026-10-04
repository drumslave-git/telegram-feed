import 'dart:convert';
import 'dart:io';

import 'package:app_db/app_db.dart';
import 'package:drift/native.dart';
import 'package:fake_telegram/fake_telegram.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/host/app_host.dart';
import 'package:telegram_feed/l10n/l10n.dart';
import 'package:telegram_feed/main.dart';
import 'package:telegram_feed/service/reading_now.dart';
import 'package:telegram_feed/settings/language_screen.dart';
import 'package:telegram_feed/sync/sync_controller.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

/// The host of a logged-out account: the app shows its login screen.
final class _Host implements AppHost {
  _Host(this.db, this.gateway);

  @override
  final AppDatabase db;
  @override
  final TelegramGateway gateway;
  @override
  bool get runningInService => false;
  @override
  SyncController get sync => throw UnimplementedError();
  @override
  final ValueNotifier<ReadingNow?> reading = ValueNotifier(null);
  @override
  void stopReading({bool clear = false}) {}
  @override
  final ValueNotifier<bool> paused = ValueNotifier(false);
  @override
  Future<void> setPaused(bool paused) async => this.paused.value = paused;
  @override
  Future<bool> get isBatteryExempt async => true;
  @override
  Future<void> requestBatteryExemption() async {}
  @override
  Future<void> restart() async {}
  @override
  Future<void> logOutAndWipe() async {}
  @override
  Future<void> dispose() async {}
  @override
  Future<void> standDown() async {}
}

void main() {
  Map<String, Object?> arb(String locale) =>
      (jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync()) as Map)
          .cast<String, Object?>();

  test('every English string has its Ukrainian one', () {
    final en = {
      for (final k in arb('en').keys)
        if (!k.startsWith('@')) k,
    };
    final uk = arb('uk');
    expect({
      for (final k in uk.keys)
        if (!k.startsWith('@')) k,
    }, en);
    for (final key in en) {
      expect((uk[key]! as String).trim(), isNotEmpty, reason: key);
    }
  });

  test('a Ukrainian count takes the form of its number', () {
    final uk = lookupAppLocalizations(const Locale('uk'));
    expect(uk.timelineNewPosts(1), '1 новий допис');
    expect(uk.timelineNewPosts(3), '3 нові дописи');
    expect(uk.timelineNewPosts(5), '5 нових дописів');
    expect(uk.timelineNewPosts(11), '11 нових дописів');
    expect(uk.timelineNewPosts(21), '21 новий допис');
    expect(uk.timelineNewPosts(22), '22 нові дописи');
    expect(uk.serviceWatching(21), 'Стеження за 21 каналом');
    final en = lookupAppLocalizations(const Locale('en'));
    expect(en.timelineNewPosts(1), '1 new post');
    expect(en.timelineNewPosts(21), '21 new posts');
  });

  test('the language is the setting, or the phone\'s while it says System', () {
    expect(AppLanguage.localeOf('uk'), const Locale('uk'));
    expect(AppLanguage.localeOf('en'), const Locale('en'));
    expect(AppLanguage.localeOf(AppLanguage.system), isNull);
    expect(AppLanguage.localeOf(null), isNull);
    // The first of the phone's languages the app has; English when it has none.
    expect(
      AppLanguage.ofPhone(const [Locale('de'), Locale('uk', 'UA')]),
      const Locale('uk'),
    );
    expect(AppLanguage.ofPhone(const [Locale('de')]), const Locale('en'));
    expect(
      AppLanguage.strings(null, const [Locale('uk', 'UA')]).localeName,
      'uk',
    );
    expect(AppLanguage.strings('en', const [Locale('uk')]).localeName, 'en');
    // A post's language picks the words read around it when the app has it.
    expect(AppLanguage.stringsOfLanguage('en-US')!.localeName, 'en');
    expect(AppLanguage.stringsOfLanguage('uk')!.localeName, 'uk');
    expect(AppLanguage.stringsOfLanguage('ru'), isNull);
  });

  group('the app', () {
    late AppDatabase db;
    late FakeTelegram gateway;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      gateway = FakeTelegram(mediaDirectory: '', arrivalEvery: null);
    });

    tearDown(() async {
      await gateway.close();
      await db.close();
    });

    Future<void> settle(WidgetTester tester) => tester.runAsync(() async {
      for (var i = 0; i < 3; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 60));
        await tester.pump();
      }
    });

    /// Drift closes a query stream on a timer once its widget is gone.
    Future<void> unmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
      await tester.pump(const Duration(seconds: 4));
    }

    testWidgets('speaks the language the setting names', (tester) async {
      await tester.runAsync(() => db.setSetting(SettingKeys.language, 'uk'));
      await tester.pumpWidget(
        TelegramFeedApp(host: Future.value(_Host(db, gateway))),
      );
      await settle(tester);
      expect(find.text('Увійти в Telegram'), findsOneWidget);

      await tester.runAsync(() => db.setSetting(SettingKeys.language, 'en'));
      await settle(tester);
      expect(find.text('Log in to Telegram'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('follows the phone while the setting says System', (
      tester,
    ) async {
      tester.platformDispatcher.localesTestValue = const [Locale('uk', 'UA')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await tester.pumpWidget(
        TelegramFeedApp(host: Future.value(_Host(db, gateway))),
      );
      await settle(tester);
      expect(find.text('Увійти в Telegram'), findsOneWidget);

      tester.platformDispatcher.localesTestValue = const [Locale('de')];
      await settle(tester);
      expect(find.text('Log in to Telegram'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('the Language screen keeps the choice', (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('en', 'US')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await tester.pumpWidget(
        StreamBuilder<String?>(
          stream: db.watchSetting(SettingKeys.language),
          builder: (context, snap) => MaterialApp(
            locale: AppLanguage.localeOf(snap.data),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: LanguageScreen(db: db),
          ),
        ),
      );
      await settle(tester);
      expect(find.text('Language'), findsOneWidget);
      // System says which language the phone leads to.
      expect(
        find.descendant(
          of: find.widgetWithText(RadioListTile<String>, 'System'),
          matching: find.text('English'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Українська'));
      await settle(tester);
      expect(
        await tester.runAsync(() => db.setting(SettingKeys.language)),
        'uk',
      );
      expect(find.text('Мова'), findsOneWidget);

      await tester.tap(find.text('Як у системі'));
      await settle(tester);
      expect(
        await tester.runAsync(() => db.setting(SettingKeys.language)),
        AppLanguage.system,
      );
      expect(find.text('Language'), findsOneWidget);
      await unmount(tester);
    });
  });
}
