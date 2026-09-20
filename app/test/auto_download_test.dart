import 'package:app_db/app_db.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/media_view.dart';
import 'package:telegram_feed/media/auto_download.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'media_view_test.dart' show DownloadGateway;

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('the policy follows the connection, the switch and the limit', () {
    const wifi = AutoDownloadPolicy(network: NetworkType.wifi, wifiMaxMb: 10);
    expect(wifi.allows(5 * 1024 * 1024), isTrue);
    expect(wifi.allows(20 * 1024 * 1024), isFalse);
    // A size TDLib has not said yet goes through.
    expect(wifi.allows(0), isTrue);

    const mobile = AutoDownloadPolicy(
      network: NetworkType.mobile,
      mobileMaxMb: 2,
    );
    expect(mobile.allows(1024 * 1024), isTrue);
    expect(mobile.allows(5 * 1024 * 1024), isFalse);

    const off = AutoDownloadPolicy(
      network: NetworkType.mobile,
      onMobile: false,
    );
    expect(off.allows(1), isFalse);
    const nothing = AutoDownloadPolicy(network: NetworkType.none);
    expect(nothing.allows(1), isFalse);
  });

  testWidgets('a picture waits for a tap when the settings say so', (
    tester,
  ) async {
    final gw = DownloadGateway('/nonexistent.png');
    const channel = MethodChannel('tf/network');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => 'mobile');
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    Widget app() => MaterialApp(
      home: AutoDownloadScope(
        db: db,
        watcher: const NetworkWatcher(channel: channel),
        child: Scaffold(
          body: PhotoView(
            file: const FileRef(
              id: 1,
              remoteId: 'r1',
              size: 3 * 1024 * 1024,
              width: 90,
              height: 90,
            ),
            gateway: gw,
          ),
        ),
      ),
    );

    Future<void> settle() => tester.runAsync(() async {
      for (var i = 0; i < 3; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        await tester.pump();
      }
    });

    Future<void> unmount() async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
    }

    // Pictures off for mobile data: the row waits for a tap.
    await tester.runAsync(
      () => db.setSetting(SettingKeys.autoDownloadMobile, 'false'),
    );
    await tester.pumpWidget(app());
    await settle();
    expect(find.text('Tap to download'), findsOneWidget);
    await unmount();

    // On again, and under the limit: it loads by itself.
    await tester.runAsync(
      () => db.setSetting(SettingKeys.autoDownloadMobile, 'true'),
    );
    await tester.pumpWidget(app());
    await settle();
    expect(find.text('Tap to download'), findsNothing);
    await unmount();

    // On, but the picture is over the limit for mobile data.
    await tester.runAsync(
      () => db.setSetting(SettingKeys.autoDownloadMobileMaxMb, '1'),
    );
    await tester.pumpWidget(app());
    await settle();
    expect(find.text('Tap to download'), findsOneWidget);
    await unmount();
  });
}
