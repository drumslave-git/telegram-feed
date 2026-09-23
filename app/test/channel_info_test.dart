import 'package:app_db/app_db.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:core/core.dart';
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

  @override
  Future<ChannelInfo> channelInfo(int chatId) async => ChannelInfo(
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
    // The full info replaces the count the channel list carried.
    expect(find.text('1.2K subscribers'), findsOneWidget);
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
    await db.close();
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
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
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

  testWidgets('a channel with no photo says so instead', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChannelInfoScreen(gateway: gw, channel: channel),
      ),
    );
    await settle(tester);
    await tester.tap(find.byType(ChannelAvatar).first);
    await tester.pump();
    await tester.pump();
    expect(find.text('This channel has no photo.'), findsOneWidget);
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
