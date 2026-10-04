import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/home/channel_list.dart';
import 'package:telegram_feed/home/unread_badge.dart';
import 'package:telegram_feed/l10n/app_localizations.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fixtures.dart';

void main() {
  const picture = PhotoMedia(
    sizes: [FileRef(id: 1, remoteId: 'a', size: 10, width: 40, height: 30)],
  );
  const clip = VideoMedia(
    file: FileRef(id: 2, remoteId: 'b', size: 20),
    durationSeconds: 5,
  );
  const paper = DocumentMedia(
    file: FileRef(id: 3, remoteId: 'c', size: 30),
    fileName: 'a.pdf',
    mimeType: 'application/pdf',
  );

  Future<void> show(WidgetTester tester, Channel channel) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        // In a list, as it stands in the app: the row takes the height it wants.
        body: ListView(
          children: [
            ChannelTile(
              channel: channel,
              gateway: ChannelsGateway(const []),
              onTap: () {},
            ),
          ],
        ),
      ),
    ),
  );

  Color? colorOf(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).style?.color;

  testWidgets('an album without words shows its pictures and their number, in '
      'the accent colour', (tester) async {
    await show(
      tester,
      const Channel(
        chatId: -1,
        title: 'News',
        lastMessageAlbum: [picture, picture, picture, picture],
      ),
    );
    // Three thumbnails at most, whatever the album holds.
    expect(find.byType(RowThumbnail), findsNWidgets(3));
    final accent = Theme.of(tester.element(find.byType(ChannelTile)))
        .colorScheme
        .primary;
    expect(colorOf(tester, '4 photos'), accent);
  });

  test('an album is named by what it holds', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(albumLabel(const [clip, clip], l10n), '2 videos');
    expect(albumLabel(const [paper, paper, paper], l10n), '3 files');
    expect(albumLabel(const [picture, clip], l10n), '2 media');
    expect(albumLabel(const [picture], l10n), '1 photo');
  });

  testWidgets('a post with words keeps its picture before them, in the usual '
      'colour', (tester) async {
    await show(
      tester,
      const Channel(
        chatId: -1,
        title: 'News',
        lastMessageText: 'the quay this morning',
        lastMessageAlbum: [picture],
      ),
    );
    expect(find.byType(RowThumbnail), findsOneWidget);
    expect(
      colorOf(tester, 'the quay this morning'),
      Theme.of(tester.element(find.byType(ChannelTile)))
          .colorScheme
          .onSurfaceVariant,
    );
    expect(
      tester.getCenter(find.byType(RowThumbnail)).dx,
      lessThan(tester.getTopLeft(find.text('the quay this morning')).dx),
    );
  });

  testWidgets('a single picture without words is named in the accent colour, '
      'and a file has no thumbnail', (tester) async {
    await show(
      tester,
      const Channel(
        chatId: -1,
        title: 'News',
        lastMessageMedia: picture,
        lastMessageAlbum: [picture],
      ),
    );
    final accent = Theme.of(tester.element(find.byType(ChannelTile)))
        .colorScheme
        .primary;
    expect(colorOf(tester, 'Photo'), accent);
    expect(find.byType(RowThumbnail), findsOneWidget);

    await show(
      tester,
      const Channel(
        chatId: -1,
        title: 'News',
        lastMessageMedia: paper,
        lastMessageAlbum: [paper],
      ),
    );
    expect(find.byType(RowThumbnail), findsNothing);
  });

  testWidgets('a muted channel counts in grey, and a counter prints the whole '
      'number', (tester) async {
    await show(
      tester,
      const Channel(
        chatId: -1,
        title: 'News',
        lastMessageText: 'words',
        unreadCount: 12345,
        isMuted: true,
      ),
    );
    final scheme = Theme.of(tester.element(find.byType(ChannelTile)))
        .colorScheme;
    expect(find.text('12345'), findsOneWidget);
    expect(
      tester.widget<Badge>(find.byType(Badge)).backgroundColor,
      scheme.outline,
    );

    await show(
      tester,
      const Channel(
        chatId: -1,
        title: 'News',
        lastMessageText: 'words',
        unreadCount: 12345,
      ),
    );
    expect(
      tester.widget<Badge>(find.byType(Badge)).backgroundColor,
      scheme.primary,
    );
    expect(find.byType(UnreadBadge), findsOneWidget);
  });

  testWidgets('a row is 70 high with a photo of 52, and a verified channel '
      'carries the mark', (tester) async {
    await show(
      tester,
      const Channel(
        chatId: -1,
        title: 'News',
        lastMessageText: 'words',
        isVerified: true,
      ),
    );
    expect(tester.getSize(find.byType(ChannelTile)).height, 70);
    expect(tester.getSize(find.byType(ChannelAvatar)), const Size(52, 52));
    expect(find.byIcon(Icons.verified), findsOneWidget);
    // The mark stands right after the name.
    expect(
      tester.getTopLeft(find.byIcon(Icons.verified)).dx,
      greaterThan(tester.getTopRight(find.text('News')).dx),
    );

    // The date stands at the end of the row, whatever the length of the name.
    await show(
      tester,
      Channel(
        chatId: -1,
        title: 'A name that is much too long to fit beside any date at all, really',
        lastMessageText: 'words',
        lastMessageDate: DateTime(2019, 1, 5).millisecondsSinceEpoch ~/ 1000,
      ),
    );
    final row = tester.getRect(find.byType(ChannelTile));
    expect(tester.getTopRight(find.text('05.01.19')).dx, row.right - 16);
    expect(tester.takeException(), isNull);

    // A channel with nothing to show keeps the same height.
    await show(tester, const Channel(chatId: -2, title: 'Empty'));
    expect(tester.getSize(find.byType(ChannelTile)).height, 70);
    expect(find.byIcon(Icons.verified), findsNothing);
  });

  testWidgets('a channel that goes up slides to its place', (tester) async {
    const one = Channel(chatId: -1, title: 'One', lastMessageText: 'a');
    const two = Channel(chatId: -2, title: 'Two', lastMessageText: 'b');
    const three = Channel(chatId: -3, title: 'Three', lastMessageText: 'c');
    Widget list(List<Channel> channels) => MaterialApp(
      home: Scaffold(
        body: ChannelList(
          channels: channels,
          gateway: ChannelsGateway(const []),
          onOpen: (_) {},
        ),
      ),
    );
    await tester.pumpWidget(list(const [one, two, three]));
    final top = tester.getTopLeft(find.text('One')).dy;
    final third = tester.getTopLeft(find.text('Three')).dy;

    // Three got a post: it is the first row now.
    await tester.pumpWidget(list(const [three, one, two]));
    // At the start of the move every row still stands where it was.
    expect(tester.getTopLeft(find.text('Three')).dy, third);
    expect(tester.getTopLeft(find.text('One')).dy, top);
    await tester.pump(const Duration(milliseconds: 120));
    final onTheWay = tester.getTopLeft(find.text('Three')).dy;
    expect(onTheWay, lessThan(third));
    expect(onTheWay, greaterThan(top));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Three')).dy, top);
    expect(tester.getTopLeft(find.text('One')).dy, top + 70);
  });
}
