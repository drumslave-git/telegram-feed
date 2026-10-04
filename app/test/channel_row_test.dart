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
        body: ChannelTile(
          channel: channel,
          gateway: ChannelsGateway(const []),
          onTap: () {},
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
    expect(colorOf(tester, 'the quay this morning'), isNull);
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
}
