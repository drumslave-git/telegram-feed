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

  testWidgets('without a title the author stands in its place, and the '
      'description runs to six lines', (tester) async {
    await tester.pumpWidget(
      card(
        const LinkPreview(
          url: 'https://example.org/a',
          siteName: 'Example',
          author: 'Ada Writer',
          description: 'What happened',
        ),
      ),
    );
    expect(find.text('Ada Writer'), findsOneWidget);
    expect(tester.widget<Text>(find.text('What happened')).maxLines, 6);

    // With a title the author is left out, as in the official app.
    await tester.pumpWidget(
      card(
        const LinkPreview(
          url: 'https://example.org/a',
          title: 'A headline',
          author: 'Ada Writer',
        ),
      ),
    );
    expect(find.text('Ada Writer'), findsNothing);
  });

  testWidgets('a link into Telegram says what it opens; a web link does not', (
    tester,
  ) async {
    await tester.pumpWidget(
      card(
        const LinkPreview(
          url: 'https://t.me/harbourtimes',
          kind: LinkKind.channel,
          title: 'Harbour Times',
        ),
      ),
    );
    expect(find.text('View channel'), findsOneWidget);
    // The whole card is the button.
    await tester.tap(find.text('View channel'));
    expect(links, ['https://t.me/harbourtimes']);

    await tester.pumpWidget(
      card(
        const LinkPreview(
          url: 'https://t.me/harbourtimes/5',
          kind: LinkKind.message,
          title: 'Harbour Times',
        ),
      ),
    );
    expect(find.text('View message'), findsOneWidget);

    await tester.pumpWidget(
      card(const LinkPreview(url: 'https://example.org', title: 'Example')),
    );
    expect(find.text('View channel'), findsNothing);
    expect(find.text('View message'), findsNothing);
  });

  testWidgets('a caption the author put over the picture stands over it', (
    tester,
  ) async {
    Widget post({required bool above}) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PostCard(
            item: TimelineItem(
              Post(
                chatId: -1001,
                messageId: 6,
                date: 1700000000,
                text: 'the caption',
                media: photo,
                captionAbove: above,
              ),
            ),
            channelTitle: 'Alpha News',
            gateway: gw,
          ),
        ),
      ),
    );

    await tester.pumpWidget(post(above: false));
    await tester.pump();
    expect(
      tester.getTopLeft(find.text('the caption')).dy,
      greaterThan(tester.getBottomLeft(find.byType(PhotoView)).dy - 1),
    );

    await tester.pumpWidget(post(above: true));
    await tester.pump();
    final picture = tester.getRect(find.byType(PhotoView));
    expect(
      tester.getBottomLeft(find.text('the caption')).dy,
      lessThanOrEqualTo(picture.top),
    );
    // The picture ends the bubble, so the time lies on it.
    final footer = tester.getRect(find.byType(PostFooter));
    expect(footer.bottom, lessThanOrEqualTo(picture.bottom));
    expect(footer.top, greaterThan(picture.top));
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
