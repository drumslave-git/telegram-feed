import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/link_preview.dart';
import 'package:telegram_feed/feeds/media_view.dart';
import 'package:telegram_feed/feeds/post_card.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'media_view_test.dart' show DownloadGateway;

void main() {
  late DownloadGateway gw;

  setUp(() => gw = DownloadGateway('/nonexistent.png'));

  const photo = PhotoMedia(
    sizes: [FileRef(id: 1, remoteId: 'r1', size: 100, width: 640, height: 360)],
  );

  final links = <String>[];

  Widget card(LinkPreview preview, {String text = 'Read this'}) {
    links.clear();
    return MaterialApp(
      home: Scaffold(
        body: PostCard(
          item: TimelineItem(
            Post(
              chatId: -1001,
              messageId: 5,
              date: 1700000000,
              text: text,
              linkPreview: preview,
            ),
          ),
          channelTitle: 'Alpha News',
          gateway: gw,
          onOpenLink: links.add,
        ),
      ),
    );
  }

  testWidgets('the card shows the site, the title and the description', (
    tester,
  ) async {
    await tester.pumpWidget(
      card(
        const LinkPreview(
          url: 'https://example.org/a',
          displayUrl: 'example.org/a',
          siteName: 'Example',
          title: 'A headline',
          description: 'What happened',
        ),
      ),
    );
    expect(find.text('Example'), findsOneWidget);
    expect(find.text('A headline'), findsOneWidget);
    expect(find.text('What happened'), findsOneWidget);

    // A tap anywhere on the card opens the link, not the post menu.
    await tester.tap(find.text('A headline'));
    await tester.pumpAndSettle();
    expect(links, ['https://example.org/a']);
  });

  testWidgets('a preview with no words of its own says where it leads', (
    tester,
  ) async {
    await tester.pumpWidget(
      card(
        const LinkPreview(
          url: 'https://example.org/a',
          displayUrl: 'example.org/a',
        ),
      ),
    );
    expect(find.text('example.org/a'), findsOneWidget);
  });

  testWidgets('the card stands under the text, or over it when TDLib asks', (
    tester,
  ) async {
    const preview = LinkPreview(
      url: 'https://example.org/a',
      siteName: 'Example',
      title: 'A headline',
    );
    await tester.pumpWidget(card(preview));
    double y(Finder f) => tester.getTopLeft(f).dy;
    expect(y(find.text('Read this')), lessThan(y(find.text('A headline'))));

    await tester.pumpWidget(card(preview));
    await tester.pumpWidget(
      card(
        const LinkPreview(
          url: 'https://example.org/a',
          siteName: 'Example',
          title: 'A headline',
          aboveText: true,
        ),
      ),
    );
    expect(y(find.text('A headline')), lessThan(y(find.text('Read this'))));
  });

  testWidgets('large media fills the card, a small picture is a square', (
    tester,
  ) async {
    await tester.pumpWidget(
      card(
        const LinkPreview(
          url: 'https://example.org/a',
          title: 'A headline',
          photo: photo,
          largeMedia: true,
        ),
      ),
    );
    final wide = tester.getSize(find.byType(PhotoView)).width;
    expect(wide, greaterThan(300));

    await tester.pumpWidget(
      card(
        const LinkPreview(
          url: 'https://example.org/a',
          title: 'A headline',
          photo: photo,
        ),
      ),
    );
    expect(tester.getSize(find.byType(PhotoView)), const Size(56, 56));
  });

  testWidgets('a video link carries a play badge and its length', (
    tester,
  ) async {
    await tester.pumpWidget(
      card(
        const LinkPreview(
          url: 'https://youtu.be/x',
          siteName: 'YouTube',
          title: 'A clip',
          photo: photo,
          isVideo: true,
          durationSeconds: 754,
          largeMedia: true,
        ),
      ),
    );
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.text('12:34'), findsOneWidget);
  });

  testWidgets('a post without a link has no card', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostCard(
            item: TimelineItem(
              const Post(
                chatId: -1001,
                messageId: 5,
                date: 1700000000,
                text: 'plain',
              ),
            ),
            channelTitle: 'Alpha News',
            gateway: gw,
          ),
        ),
      ),
    );
    expect(find.byType(LinkPreviewCard), findsNothing);
  });
}
