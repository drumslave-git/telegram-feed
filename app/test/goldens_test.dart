// Golden images of the main screens. Regenerate with:
//   flutter test --update-goldens test/goldens_test.dart
// Text renders with the test font (Ahem boxes), so layouts are deterministic across platforms.
import 'package:app_db/app_db.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/auth/login_screens.dart';
import 'package:telegram_feed/feeds/feed_editor_screen.dart';
import 'package:telegram_feed/feeds/timeline_screen.dart';
import 'package:telegram_feed/home/home_screen.dart';
import 'package:telegram_feed/settings/settings_screen.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'login_flow_test.dart' show ScriptedGateway;
import 'settings_screen_test.dart' show SettingsGateway;
import 'fixtures.dart';

const _phone = Size(412, 915); // Pixel-class portrait

Widget _app(Widget home, {ThemeMode mode = ThemeMode.light}) => MaterialApp(
  theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
  darkTheme: ThemeData(
    colorSchemeSeed: Colors.blue,
    brightness: Brightness.dark,
    useMaterial3: true,
  ),
  themeMode: mode,
  home: home,
);

Future<void> _settle(WidgetTester tester) => tester.runAsync(() async {
  await Future<void>.delayed(const Duration(milliseconds: 80));
  await tester.pump();
  await Future<void>.delayed(const Duration(milliseconds: 80));
  await tester.pump();
});

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
}

Post _post(
  int chat,
  int id,
  int date,
  String text, {
  Media? media,
  int replyCount = 0,
  LinkPreview? linkPreview,
}) => Post(
  chatId: chat,
  messageId: id,
  date: date,
  text: text,
  media: media,
  replyCount: replyCount,
  canComment: replyCount > 0,
  linkPreview: linkPreview,
);

void main() {
  testWidgets('login: phone and code', (tester) async {
    await tester.binding.setSurfaceSize(_phone);
    final g = ScriptedGateway();
    await tester.pumpWidget(
      _app(AuthGate(gateway: g, child: const SizedBox())),
    );
    await tester.pump();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/login_phone.png'),
    );

    g.go(
      const AuthWaitCode(
        phoneNumber: '+1 555 0100',
        codeLength: 5,
        viaSms: true,
      ),
    );
    await tester.pump();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/login_code.png'),
    );

    g.go(const AuthWaitOtherDeviceConfirmation('tg://login?token=Z29sZGVu'));
    await tester.pump();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/login_qr.png'),
    );
  });

  testWidgets('home: feeds tab with badges, folder tab, all channels', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(_phone);
    final db = AppDatabase(NativeDatabase.memory());
    await tester.runAsync(() async {
      final a = await db.createFeed('Tech');
      await db.addSource(a.id, -1, title: 'Alpha News');
      await db.addSource(a.id, -2, title: 'Beta Daily');
      await db.createFeed('Sports');
    });
    // Beta Daily has three posts past Tech's mark: the feed's counter says 3 (J-1).
    final gw = TimelineGateway(
      {-2: fixtureHistory(-2, from: 198, to: 200)},
      channels: const [
        Channel(
          chatId: -1,
          title: 'Alpha News',
          lastMessageId: 100,
          lastMessageText: 'Quarterly results are out',
          lastMessageDate: 1,
        ),
        Channel(
          chatId: -2,
          title: 'Beta Daily',
          lastMessageId: 200,
          unreadCount: 12,
          lastMessageText: 'Photo',
          lastMessageDate: 1,
        ),
      ],
      folders: const [
        ChatFolder(id: 2, title: 'News', channelIds: [-2, -1]),
      ],
    );
    gw.readPositions[-1] = 100;
    await tester.pumpWidget(_app(HomeScreen(db: db, gateway: gw)));
    await _settle(tester);
    await _settle(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/home.png'),
    );
    await _unmount(tester);
  });

  testWidgets('feed editor', (tester) async {
    await tester.binding.setSurfaceSize(_phone);
    final db = AppDatabase(NativeDatabase.memory());
    late int feedId;
    await tester.runAsync(() async {
      feedId = (await db.createFeed('Tech')).id;
      await db.addSource(feedId, -1, title: 'Alpha News', username: 'alpha');
      await db.addSource(feedId, -3, title: 'Gone');
    });
    final gw = TimelineGateway(
      {},
      channels: const [
        Channel(chatId: -1, title: 'Alpha News', username: 'alpha'),
        Channel(chatId: -3, title: 'Gone', isMember: false),
      ],
    );
    await tester.pumpWidget(
      _app(FeedEditorScreen(db: db, gateway: gw, feedId: feedId)),
    );
    await _settle(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/feed_editor.png'),
    );
    await _unmount(tester);
  });

  testWidgets('timeline, light and dark', (tester) async {
    await tester.binding.setSurfaceSize(_phone);
    final db = AppDatabase(NativeDatabase.memory());
    late Feed feed;
    await tester.runAsync(() async {
      feed = await db.createFeed('Tech');
      await db.addSource(feed.id, -1, title: 'Alpha News');
      await db.addSource(feed.id, -2, title: 'Beta Daily');
    });
    final gw = TimelineGateway({
      -1: [
        _post(
          -1,
          300,
          1700010000, // fixed past dates: the header shows time only for today
          'A longer post with two lines of text so the card wraps and shows its shape.',
          replyCount: 12,
        ),
        // A link preview, without a picture of its own: a downloading one would turn a
        // spinner in the image.
        _post(
          -1,
          120,
          1700001000,
          'A post with a link in it',
          linkPreview: const LinkPreview(
            url: 'https://example.org/a',
            displayUrl: 'example.org/a',
            siteName: 'Example',
            title: 'A headline from the web',
            description: 'The description of the page the link leads to.',
          ),
        ),
        _post(
          -1,
          100,
          1700000000,
          'Older post',
          media: const UnsupportedMedia('messagePoll'),
        ),
      ],
      -2: [
        _post(
          -2,
          200,
          1700005000,
          'Video post',
          media: const VideoMedia(
            file: FileRef(
              id: 4,
              remoteId: 'd',
              size: 100,
              width: 640,
              height: 360,
            ),
            durationSeconds: 754,
          ),
        ),
        // An album: three videos without posters (flat cells), laid out as a mosaic.
        for (final (i, size) in const [
          (600, 900),
          (800, 800),
          (900, 600),
        ].indexed)
          Post(
            chatId: -2,
            messageId: 150 - i,
            date: 1700003000,
            text: i == 2 ? 'Album caption' : '',
            albumId: 77,
            views: 12400,
            editDate: 1700003500,
            reactions: const [
              Reaction(emoji: '+', count: 1200, chosen: true),
              Reaction(emoji: '-', count: 3),
            ],
            media: VideoMedia(
              file: FileRef(
                id: 10 + i,
                remoteId: 'a$i',
                size: 100,
                width: size.$1,
                height: size.$2,
              ),
              durationSeconds: 61,
            ),
          ),
      ],
    });
    gw.readPositions[-2] = 250;
    for (final (mode, name) in [
      (ThemeMode.light, 'timeline_light'),
      (ThemeMode.dark, 'timeline_dark'),
    ]) {
      await tester.pumpWidget(
        _app(
          TimelineScreen(db: db, gateway: gw, feed: feed),
          mode: mode,
        ),
      );
      await _settle(tester);
      // The switch to the dark theme is animated (200 ms); without letting it finish the
      // "dark" image shows the light theme. Widgets that animate their own colours
      // (avatars) only start once the new theme is there, hence the second pump.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/$name.png'),
      );
    }
    await _unmount(tester);
  });

  testWidgets('settings', (tester) async {
    await tester.binding.setSurfaceSize(_phone);
    final db = AppDatabase(NativeDatabase.memory());
    await tester.pumpWidget(
      _app(
        SettingsScreen(
          db: db,
          gateway: SettingsGateway(),
          onLogOut: () async {},
        ),
      ),
    );
    await _settle(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/settings.png'),
    );
    await _unmount(tester);
  });
}
