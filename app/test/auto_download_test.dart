import 'package:app_db/app_db.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/media_view.dart';
import 'package:telegram_feed/media/auto_download.dart';
import 'package:telegram_feed/media/video_downloads.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'media_view_test.dart' show DownloadGateway;

const _mb = 1024 * 1024;

VideoMedia _video(int bytes, {int id = 9, bool gif = false}) => VideoMedia(
  file: FileRef(id: id, remoteId: 'v$id', size: bytes, width: 640, height: 360),
  durationSeconds: 20,
  isAnimation: gif,
);

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test("Telegram's presets, as the connection rows name them", () {
    expect(
      DownloadPreset.medium.summary,
      'Photos, Videos (10 MB), Files (1 MB)',
    );
    expect(DownloadPreset.high.summary, 'Photos, Videos (15 MB), Files (3 MB)');
    expect(DownloadPreset.low.summary, 'Photos');
    expect(DownloadPreset.high.copyWith(enabled: false).summary, 'Disabled');
    expect(Connection.mobile.defaults, DownloadPreset.medium);
    expect(Connection.wifi.defaults, DownloadPreset.high);
    expect(Connection.roaming.defaults, DownloadPreset.low);

    // Which preset a choice is; one of the reader's own is none of them.
    expect(DownloadPreset.low.presetIndex, 0);
    expect(DownloadPreset.high.copyWith(enabled: false).presetIndex, 2);
    expect(
      DownloadPreset.medium.copyWith(videoMaxBytes: 50 * _mb).presetIndex,
      -1,
    );
    expect(
      DownloadPreset.low.weight < DownloadPreset.medium.weight &&
          DownloadPreset.medium.weight < DownloadPreset.high.weight,
      isTrue,
    );
  });

  test('a preset survives the settings table, and garbage falls back', () {
    final own = DownloadPreset.medium.copyWith(
      enabled: false,
      files: false,
      videoMaxBytes: 50 * _mb,
      preloadLargeVideos: false,
    );
    expect(DownloadPreset.decode(own.encode(), DownloadPreset.low), own);
    expect(
      DownloadPreset.decode(null, DownloadPreset.high),
      DownloadPreset.high,
    );
    expect(
      DownloadPreset.decode('not json', DownloadPreset.low),
      DownloadPreset.low,
    );
    // Adopting a preset keeps the connection's switch.
    expect(own.adopt(DownloadPreset.high).enabled, isFalse);
    expect(
      own.adopt(DownloadPreset.high).sameKindsAs(DownloadPreset.high),
      isTrue,
    );
  });

  test('the policy follows the connection, its switch and its limits', () {
    const wifi = AutoDownloadPolicy(network: NetworkType.wifi);
    expect(wifi.photos, isTrue);
    expect(wifi.video(_video(12 * _mb)), isTrue); // High: up to 15 MB
    expect(wifi.video(_video(16 * _mb)), isFalse);
    expect(wifi.file(3 * _mb), isTrue);
    expect(wifi.file(4 * _mb), isFalse);
    // A size TDLib has not said yet waits for a tap.
    expect(wifi.video(_video(0)), isFalse);
    expect(wifi.file(0), isFalse);

    const mobile = AutoDownloadPolicy(network: NetworkType.mobile);
    expect(mobile.video(_video(12 * _mb)), isFalse); // Medium: up to 10 MB
    expect(mobile.video(_video(9 * _mb)), isTrue);

    const roaming = AutoDownloadPolicy(network: NetworkType.roaming);
    expect(roaming.photos, isTrue); // Low: photos only
    expect(roaming.video(_video(100 * 1024)), isFalse);
    expect(roaming.file(1024), isFalse);

    final off = AutoDownloadPolicy(
      network: NetworkType.wifi,
      wifi: DownloadPreset.high.copyWith(enabled: false),
    );
    expect(off.photos, isFalse);
    expect(off.video(_video(_mb)), isFalse);

    const nothing = AutoDownloadPolicy(network: NetworkType.none);
    expect(nothing.photos, isFalse);
    const unknown = AutoDownloadPolicy.unknown();
    expect(unknown.photos, isFalse);
  });

  test('a video autoplays only when it loads by itself and its switch is on', () {
    const on = AutoDownloadPolicy(network: NetworkType.wifi);
    expect(on.autoplay(_video(5 * _mb)), isTrue);
    expect(on.autoplay(_video(5 * _mb, gif: true)), isTrue);
    // Over the limit: no autoplay, but its first seconds load ahead.
    expect(on.autoplay(_video(20 * _mb)), isFalse);
    expect(on.preload(_video(20 * _mb)), isTrue);
    expect(on.preload(_video(5 * _mb)), isFalse);

    const noVideos = AutoDownloadPolicy(
      network: NetworkType.wifi,
      autoplayVideos: false,
    );
    expect(noVideos.autoplay(_video(5 * _mb)), isFalse);
    expect(noVideos.autoplay(_video(5 * _mb, gif: true)), isTrue);
    // Still loads by itself: autoplay and download are one choice only one way.
    expect(noVideos.video(_video(5 * _mb)), isTrue);

    const noGifs = AutoDownloadPolicy(
      network: NetworkType.wifi,
      autoplayGifs: false,
    );
    expect(noGifs.autoplay(_video(5 * _mb, gif: true)), isFalse);

    // Low preloads nothing.
    const roaming = AutoDownloadPolicy(network: NetworkType.roaming);
    expect(roaming.preload(_video(20 * _mb)), isFalse);
  });

  group('in the rows', () {
    const channel = MethodChannel('tf/network');
    var network = 'mobile';

    setUp(() {
      network = 'mobile';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => network);
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    Widget app(DownloadGateway gw, Widget child) => MaterialApp(
      home: AutoDownloadScope(
        db: db,
        watcher: const NetworkWatcher(channel: channel),
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

    Future<void> settle(WidgetTester tester) => tester.runAsync(() async {
      for (var i = 0; i < 3; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        await tester.pump();
      }
    });

    Future<void> unmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }

    Future<void> write(WidgetTester tester, String key, String value) =>
        tester.runAsync(() => db.setSetting(key, value));

    testWidgets('roaming is a connection of its own', (tester) async {
      network = 'roaming';
      expect(
        await const NetworkWatcher(channel: channel).type(),
        NetworkType.roaming,
      );
    });

    testWidgets('a picture waits for a tap when photos are off', (
      tester,
    ) async {
      final gw = DownloadGateway('/nonexistent.png');
      final picture = PhotoView(
        file: const FileRef(
          id: 1,
          remoteId: 'r1',
          size: 3 * _mb,
          width: 90,
          height: 90,
        ),
        gateway: gw,
      );

      await write(
        tester,
        SettingKeys.downloadMobile,
        DownloadPreset.medium.copyWith(photos: false).encode(),
      );
      await tester.pumpWidget(app(gw, picture));
      await settle(tester);
      expect(find.text('Tap to download'), findsOneWidget);
      await unmount(tester);

      // Photos have no size limit: a big one loads by itself.
      await write(
        tester,
        SettingKeys.downloadMobile,
        DownloadPreset.medium.encode(),
      );
      await tester.pumpWidget(app(gw, picture));
      await settle(tester);
      expect(find.text('Tap to download'), findsNothing);
      await unmount(tester);

      // The whole connection off.
      await write(
        tester,
        SettingKeys.downloadMobile,
        DownloadPreset.medium.copyWith(enabled: false).encode(),
      );
      await tester.pumpWidget(app(gw, picture));
      await settle(tester);
      expect(find.text('Tap to download'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('a video within the limit loads by itself, with its progress '
        'on the pill', (tester) async {
      final gw = DownloadGateway('/nonexistent.mp4');
      // No player in this test: the download alone is looked at.
      await write(tester, SettingKeys.autoplay, 'false');
      await tester.pumpWidget(
        app(gw, MediaView(media: _video(5 * _mb), gateway: gw)),
      );
      await settle(tester);
      expect(gw.priorities, [16]);
      expect(gw.limits, [0]);
      expect(VideoDownloads.of(gw).wants(9), isTrue);
      expect(find.text('0 B / 5.0 MB'), findsOneWidget);

      // Stopped by hand, it does not start by itself again.
      await VideoDownloads.of(gw).cancel(9);
      await unmount(tester);
      await tester.pumpWidget(
        app(gw, MediaView(media: _video(5 * _mb), gateway: gw)),
      );
      await settle(tester);
      expect(gw.priorities, [16]);
      expect(find.text('5.0 MB'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('a larger video loads its first seconds only, a larger one '
        'without preloading nothing', (tester) async {
      final gw = DownloadGateway('/nonexistent.mp4');
      await tester.pumpWidget(
        app(gw, MediaView(media: _video(40 * _mb), gateway: gw)),
      );
      await settle(tester);
      expect(gw.limits, [VideoDownloads.preloadBytes]);
      expect(gw.priorities, [1]);
      // Nothing shows for it: the pill offers the whole file.
      expect(VideoDownloads.of(gw).wants(9), isFalse);
      expect(find.text('40 MB'), findsOneWidget);
      await unmount(tester);

      await write(
        tester,
        SettingKeys.downloadMobile,
        DownloadPreset.medium.copyWith(preloadLargeVideos: false).encode(),
      );
      await tester.pumpWidget(
        app(gw, MediaView(media: _video(40 * _mb, id: 10), gateway: gw)),
      );
      await settle(tester);
      expect(gw.limits, [VideoDownloads.preloadBytes]);
      await unmount(tester);
    });

    testWidgets('a file within the limit loads by itself', (tester) async {
      final gw = DownloadGateway('/nonexistent.pdf');
      DocumentMedia doc(int id, int bytes) => DocumentMedia(
        file: FileRef(id: id, remoteId: 'd$id', size: bytes),
        fileName: 'paper.pdf',
        mimeType: 'application/pdf',
      );
      await tester.pumpWidget(
        app(gw, MediaView(media: doc(3, 512 * 1024), gateway: gw)),
      );
      await settle(tester);
      expect(find.text('Downloading…'), findsOneWidget);
      await unmount(tester);

      // Medium stops files at 1 MB.
      await tester.pumpWidget(
        app(gw, MediaView(media: doc(4, 2 * _mb), gateway: gw)),
      );
      await settle(tester);
      expect(find.text('Tap to download'), findsOneWidget);
      await unmount(tester);
    });
  });
}
