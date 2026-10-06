import 'package:app_db/app_db.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:core/core.dart';
import 'package:telegram_feed/feeds/channel_mute.dart';
import 'package:telegram_feed/feeds/feed_editor_screen.dart';
import 'package:telegram_feed/feeds/shared_media.dart';
import 'package:telegram_feed/feeds/timeline_screen.dart';
import 'package:telegram_feed/home/channel_info_screen.dart';
import 'package:telegram_feed/home/channel_list.dart' show ChannelAvatar;
import 'package:telegram_feed/media/media_viewer.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fixtures.dart';

/// Histories answered by media kind, the way TDLib's search filters do.
final class MediaGateway extends ChannelsGateway {
  /// What Telegram suggests as similar (H-32).
  List<Channel> similar = const [];

  @override
  Future<List<Channel>> similarChannels(int chatId) async => similar;

  MediaGateway(this.histories, {List<Channel> channels = const []})
    : super(channels);
  final Map<int, List<Post>> histories;

  @override
  Future<List<Post>> history(
    int chatId, {
    int fromMessageId = 0,
    int limit = 30,
    bool onlyLocal = false,
  }) async {
    final all = histories[chatId] ?? const <Post>[];
    return (fromMessageId == 0
            ? all
            : all.where((p) => p.messageId < fromMessageId))
        .take(limit)
        .toList();
  }

  /// What the info screen is told about the channel; a test may put its own in.
  ChannelInfo? info;

  @override
  Future<ChannelInfo> channelInfo(int chatId) async =>
      info ??
      ChannelInfo(
        chatId: chatId,
        description: 'All the news that fits',
        memberCount: 1234,
        inviteLink: 'https://t.me/+private',
      );

  @override
  Future<SearchPage> searchHistory(
    int chatId, {
    String query = '',
    HistoryFilter filter = HistoryFilter.any,
    int fromMessageId = 0,
    int limit = 30,
  }) async {
    bool matches(Post p) {
      final m = p.media;
      return switch (filter) {
        HistoryFilter.any => true,
        HistoryFilter.photoAndVideo => m is PhotoMedia || m is VideoMedia,
        HistoryFilter.document => m is DocumentMedia,
        HistoryFilter.url => p.text.contains('http'),
        HistoryFilter.audio => m is AudioMedia && !m.isVoice,
        HistoryFilter.voice => m is AudioMedia && m.isVoice,
        HistoryFilter.photo => m is PhotoMedia,
        HistoryFilter.video => m is VideoMedia && !m.isAnimation,
        HistoryFilter.animation => m is VideoMedia && m.isAnimation,
      };
    }

    final all = [
      for (final p in histories[chatId] ?? const <Post>[])
        if (matches(p)) p,
    ];
    return SearchPage(posts: all, totalCount: all.length);
  }
}

void main() {
  /// The tiles keep a download spinner turning, so the tests step the clock by hand
  /// instead of waiting for the tree to settle.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  const photo = PhotoMedia(
    sizes: [FileRef(id: 1, remoteId: 'p', size: 10, width: 90, height: 90)],
  );
  const video = VideoMedia(
    file: FileRef(id: 2, remoteId: 'v', size: 99),
    durationSeconds: 754,
    thumbnail: FileRef(id: 3, remoteId: 't', size: 5, width: 90, height: 90),
  );
  const doc = DocumentMedia(
    file: FileRef(id: 4, remoteId: 'd', size: 20),
    fileName: 'report.pdf',
    mimeType: 'application/pdf',
  );

  Post post(int id, int date, {String text = '', Media? media}) =>
      Post(chatId: -1, messageId: id, date: date, text: text, media: media);

  late MediaGateway gw;
  const channel = Channel(
    chatId: -1,
    title: 'Alpha News',
    username: 'alpha',
    memberCount: 1200,
  );

  setUp(() {
    gw = MediaGateway(
      {
        -1: [
          post(5, 1700000500, media: photo),
          post(4, 1700000400, media: video),
          post(3, 1700000300, media: doc),
          post(2, 1700000200, text: 'read this https://example.org/story'),
          post(1, 1700000100, text: 'plain'),
        ],
      },
      channels: const [channel],
    );
  });

  testWidgets('channel info: subscribers, description, link and media tabs', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChannelInfoScreen(gateway: gw, channel: channel),
      ),
    );
    await settle(tester);

    expect(find.text('Alpha News'), findsOneWidget);
    // The full info replaces the count the channel list carried, and is written in full.
    expect(find.text('1,234 subscribers'), findsOneWidget);
    expect(find.text('All the news that fits'), findsOneWidget);
    // A public channel is known by its username, not by the invite link.
    expect(find.text('@alpha'), findsOneWidget);
    expect(find.text('https://t.me/alpha'), findsOneWidget);

    // Media: the photo and the video, the video with its length.
    expect(find.byType(MediaTile), findsNWidgets(2));
    expect(find.text('12:34'), findsOneWidget);

    await tester.tap(find.text('Files'));
    await settle(tester);
    expect(find.text('report.pdf'), findsOneWidget);

    await tester.tap(find.text('Links'));
    await settle(tester);
    expect(find.text('https://example.org/story'), findsOneWidget);
    expect(find.byType(LinkRow), findsOneWidget);

    await tester.tap(find.text('Voice'));
    await settle(tester);
    expect(find.text('Nothing here yet.'), findsOneWidget);
  });

  testWidgets(
    'a channel is muted and unmuted in Telegram from the bar under '
    'its posts and from the switch on its info screen, and both show the same',
    (tester) async {
      ChannelMutes.changes.value = const {};
      final db = AppDatabase(NativeDatabase.memory());
      await tester.pumpWidget(
        MaterialApp(
          home: TimelineScreen(db: db, gateway: gw, channel: channel),
        ),
      );
      await settle(tester);
      expect(find.text('MUTE'), findsOneWidget);
      await tester.tap(find.text('MUTE'));
      await settle(tester);
      expect(gw.mutedNow[-1], isTrue);
      expect(find.text('UNMUTE'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Alpha News'),
        ),
      );
      await settle(tester);
      final notifications = find.widgetWithText(
        SwitchListTile,
        'Notifications',
        skipOffstage: false,
      );
      await tester.scrollUntilVisible(
        notifications,
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.widget<SwitchListTile>(notifications).value, isFalse);
      expect(find.textContaining('Muted in Telegram'), findsOneWidget);
      await tester.tap(notifications);
      await settle(tester);
      expect(gw.mutedNow[-1], isFalse);
      expect(
        find.textContaining('Telegram pushes this channel'),
        findsOneWidget,
      );

      await tester.pageBack();
      await settle(tester);
      expect(find.text('MUTE'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      addTearDown(db.close);
    },
  );

  testWidgets('the channel title in the timeline opens the info screen', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(db: db, gateway: gw, channel: channel),
      ),
    );
    await settle(tester);

    expect(find.text('1.2K subscribers'), findsOneWidget); // under the title
    // The name is also on every bubble; the one in the app bar opens the info.
    await tester.tap(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Alpha News'),
      ),
    );
    await settle(tester);
    expect(find.byType(ChannelInfoScreen), findsOneWidget);
    expect(find.text('Channel info'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    // After the test: the timeline watches a setting, and the database closes its
    // streams on the real event loop.
    addTearDown(db.close);
  });
  testWidgets('the feed editor shows the media of all its channels, filtered', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    late Feed feed;
    await tester.runAsync(() async {
      feed = await db.createFeed('Mix');
      await db.addSource(feed.id, -1, title: 'Alpha News');
      await db.addSource(feed.id, -2, title: 'Beta Daily');
    });
    gw = MediaGateway({
      -1: [post(5, 1700000500, media: photo)],
      -2: [
        Post(
          chatId: -2,
          messageId: 4,
          date: 1700000400,
          text: '',
          media: video,
        ),
        Post(chatId: -2, messageId: 3, date: 1700000300, text: '', media: doc),
      ],
    });
    await tester.pumpWidget(
      MaterialApp(
        home: FeedEditorScreen(db: db, gateway: gw, feedId: feed.id),
      ),
    );
    await settle(tester);
    expect(find.text('Alpha News'), findsOneWidget); // the Channels tab

    await tester.tap(find.text('Shared media'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // The kinds are counted first, then the tab loads its page.
    for (var i = 0; i < 2; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    // Both channels, merged: the photo of one and the video of the other.
    expect(find.byType(MediaTile), findsNWidgets(2));

    await tester.tap(find.text('Files'));
    await settle(tester);
    expect(find.text('report.pdf'), findsOneWidget);

    // The feed's own filter applies here too.
    await tester.runAsync(
      () => db.setFeedFilter(
        feed.id,
        const FeedFilter(kinds: {MediaKind.photo}).encode(),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('Media')); // back to the first inner tab
    await settle(tester);
    expect(find.byType(MediaTile), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('a tap on the channel photo opens it on the whole screen', (
    tester,
  ) async {
    const withPhoto = Channel(
      chatId: -1,
      title: 'Alpha News',
      username: 'alpha',
      memberCount: 1200,
      photo: FileRef(id: 3, remoteId: 'r3', size: 10, width: 640, height: 640),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ChannelInfoScreen(gateway: gw, channel: withPhoto),
      ),
    );
    await settle(tester);

    await tester.tap(find.byType(ChannelAvatar).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(MediaViewerScreen), findsOneWidget);
    // The viewer names the channel the picture belongs to.
    expect(
      find.descendant(
        of: find.byType(MediaViewerScreen),
        matching: find.text('Alpha News'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the link row hands the link to the share sheet, and a link in '
      'the description opens', (tester) async {
    gw.info = const ChannelInfo(
      chatId: -1,
      description: 'Tips to example.org please',
      descriptionEntities: [
        TextEntity(
          offset: 8,
          length: 11,
          kind: TextEntityKind.link,
          url: 'https://example.org',
        ),
      ],
      memberCount: 48210,
    );
    final shared = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: ChannelInfoScreen(
          gateway: gw,
          channel: channel,
          share: (text, {required subject}) async =>
              shared.add('$subject: $text'),
        ),
      ),
    );
    await settle(tester);
    expect(find.text('48,210 subscribers'), findsOneWidget);

    await tester.tap(find.text('@alpha'));
    await tester.pump();
    expect(shared, ['Alpha News: https://t.me/alpha']);

    // The link stands out in the description and answers a tap.
    final words = tester.widget<Text>(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            (w.textSpan?.toPlainText() ?? '') == 'Tips to example.org please',
      ),
    );
    final link = (words.textSpan! as TextSpan).children!
        .whereType<TextSpan>()
        .firstWhere((s) => s.text == 'example.org');
    expect(link.recognizer, isNotNull);
    expect(
      link.style?.color,
      Theme.of(tester.element(find.byType(ChannelInfoScreen)))
          .colorScheme
          .primary,
    );
  });

  testWidgets('a pull down opens the gallery of every photo the channel has '
      'had, and a tap opens the viewer on that photo', (tester) async {
    FileRef file(int id) =>
        FileRef(id: id, remoteId: 'r$id', size: 10, width: 640, height: 640);
    gw.info = ChannelInfo(
      chatId: -1,
      memberCount: 1200,
      photos: [
        PhotoMedia(sizes: [file(11)]),
        PhotoMedia(sizes: [file(12)]),
        PhotoMedia(sizes: [file(13)]),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ChannelInfoScreen(gateway: gw, channel: channel),
      ),
    );
    await settle(tester);
    final gallery = find.byKey(const ValueKey('channel-photos'));
    expect(gallery, findsNothing);
    expect(find.byType(ChannelAvatar), findsOneWidget);

    await tester.drag(find.text('Alpha News'), const Offset(0, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // As wide as the screen, with the name on it and no small photo beside it.
    expect(tester.getSize(gallery).width, 800);
    expect(find.byType(ChannelAvatar), findsNothing);
    expect(find.text('Alpha News'), findsOneWidget);
    expect(find.text('1,200 subscribers'), findsOneWidget);
    expect(find.bySemanticsLabel('Photo 1 of 3'), findsOneWidget);

    // One swipe to the next photo.
    await tester.drag(gallery, const Offset(-600, 0));
    // The page comes to rest: a tap on a page that still moves only stops it.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.bySemanticsLabel('Photo 2 of 3'), findsOneWidget);

    await tester.tap(gallery);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(MediaViewerScreen), findsOneWidget);
    final viewer = tester.widget<MediaViewerScreen>(
      find.byType(MediaViewerScreen),
    );
    expect(viewer.items, hasLength(3));
    expect(viewer.initialIndex, 1);
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The arrow brings the small photo back.
    // On this wide test surface the square gallery reaches below the screen.
    await tester.ensureVisible(find.byTooltip('Show the small photo'));
    await tester.pump();
    await tester.tap(find.byTooltip('Show the small photo'));
    await tester.pump();
    await tester.pump();
    expect(gallery, findsNothing);
    expect(find.byType(ChannelAvatar), findsOneWidget);
  });

  testWidgets('a channel with no photo opens nothing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChannelInfoScreen(gateway: gw, channel: channel),
      ),
    );
    await settle(tester);
    await tester.tap(find.byType(ChannelAvatar).first);
    await tester.pump();
    await tester.pump();
    // No viewer and no apology: the initials are simply not a button.
    expect(find.byType(MediaViewerScreen), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('similar channels and the QR code are in the info screen', (
    tester,
  ) async {
    gw.similar = const [
      Channel(chatId: -7, title: 'Beta Daily', username: 'beta'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: ChannelInfoScreen(gateway: gw, channel: channel),
      ),
    );
    await settle(tester);

    expect(find.text('Similar channels'), findsOneWidget);
    expect(find.text('Beta Daily'), findsOneWidget);

    // The media tabs keep a spinner turning, so the frames are pumped by hand.
    await tester.tap(find.byTooltip('QR code'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('https://t.me/alpha'), findsWidgets);
    await tester.tap(find.text('Close'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(QrImageView), findsNothing);
  });
}
