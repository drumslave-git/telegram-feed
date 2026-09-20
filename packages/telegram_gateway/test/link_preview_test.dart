import 'package:tdlib_bindings/tdlib_bindings.dart' as td;
import 'package:telegram_gateway/src/mapping.dart' as map;
import 'package:telegram_gateway/telegram_gateway.dart';
import 'package:test/test.dart';

Map<String, Object?> _file(int id, {int size = 1000}) => {
  '@type': 'file',
  'id': id,
  'size': size,
  'expected_size': size,
  'remote': {'@type': 'remoteFile', 'id': 'r$id'},
};

Map<String, Object?> _photo(List<(int, int, int)> sizes) => {
  '@type': 'photo',
  'sizes': [
    for (final (id, w, h) in sizes)
      {
        '@type': 'photoSize',
        'type': 'x',
        'photo': _file(id),
        'width': w,
        'height': h,
      },
  ],
};

td.Message _message(String text, Map<String, Object?>? preview) =>
    td.Message.fromJson({
      '@type': 'message',
      'id': 7,
      'chat_id': -1001,
      'date': 1700000000,
      'content': {
        '@type': 'messageText',
        'text': {'@type': 'formattedText', 'text': text},
        'link_preview': ?preview,
      },
    });

void main() {
  test('an article preview carries its words and its picture', () {
    final post = map.post(
      _message('Read this: example.org/a', {
        '@type': 'linkPreview',
        'url': 'https://example.org/a',
        'display_url': 'example.org/a',
        'site_name': 'Example',
        'title': 'A headline',
        'description': {'@type': 'formattedText', 'text': 'What happened'},
        'author': 'A. Writer',
        'show_large_media': true,
        'show_media_above_description': true,
        'show_above_text': true,
        'type': {
          '@type': 'linkPreviewTypeArticle',
          // Out of order on purpose: the card picks a size by width.
          'photo': _photo([(2, 800, 400), (1, 320, 160)]),
        },
      }),
    );
    final preview = post.linkPreview!;
    expect(preview.url, 'https://example.org/a');
    expect(preview.displayUrl, 'example.org/a');
    expect(preview.siteName, 'Example');
    expect(preview.title, 'A headline');
    expect(preview.description, 'What happened');
    expect(preview.author, 'A. Writer');
    expect(preview.largeMedia, isTrue);
    expect(preview.photoAbove, isTrue);
    expect(preview.aboveText, isTrue);
    expect(preview.isVideo, isFalse);
    expect(preview.photo!.sizes.map((s) => s.width), [320, 800]);
    // A link does not make the post a media post: a feed of text posts still shows it.
    expect(post.media, isNull);
    expect(post.text, 'Read this: example.org/a');
  });

  test('a video link is marked as one, with its length and thumbnail', () {
    final post = map.post(
      _message('youtu.be/x', {
        '@type': 'linkPreview',
        'url': 'https://youtu.be/x',
        'display_url': 'youtu.be/x',
        'site_name': 'YouTube',
        'title': 'A clip',
        'author': '',
        'show_large_media': true,
        'type': {
          '@type': 'linkPreviewTypeEmbeddedVideoPlayer',
          'url': 'https://youtube.com/embed/x',
          'thumbnail': _photo([(3, 640, 360)]),
          'duration': 754,
          'width': 640,
          'height': 360,
        },
      }),
    );
    final preview = post.linkPreview!;
    expect(preview.isVideo, isTrue);
    expect(preview.durationSeconds, 754);
    expect(preview.photo!.sizes.single.width, 640);
  });

  test('a kind without a picture still gives a card', () {
    final post = map.post(
      _message('t.me/durov', {
        '@type': 'linkPreview',
        'url': 'https://t.me/durov',
        'display_url': 't.me/durov',
        'site_name': 'Telegram',
        'title': 'Durov',
        'author': '',
        'type': {'@type': 'linkPreviewTypeUser'},
      }),
    );
    expect(post.linkPreview!.photo, isNull);
    expect(post.linkPreview!.title, 'Durov');
  });

  test('a post without a link has no preview', () {
    expect(map.post(_message('plain', null)).linkPreview, isNull);
    // Media messages never carry one.
    final photo = td.Message.fromJson({
      '@type': 'message',
      'id': 8,
      'chat_id': -1001,
      'date': 1,
      'content': {
        '@type': 'messagePhoto',
        'photo': _photo([(1, 100, 50)]),
        'caption': {'@type': 'formattedText', 'text': 'see example.org'},
      },
    });
    expect(map.post(photo).linkPreview, isNull);
  });

  test('the preview survives the trip between isolates', () {
    const post = Post(
      chatId: -1,
      messageId: 2,
      date: 3,
      text: 'example.org',
      linkPreview: LinkPreview(
        url: 'https://example.org',
        displayUrl: 'example.org',
        siteName: 'Example',
        title: 'Title',
        author: 'Author',
        description: 'Description',
        photo: PhotoMedia(
          sizes: [
            FileRef(id: 1, remoteId: 'r1', size: 10, width: 320, height: 160),
          ],
        ),
        isVideo: true,
        durationSeconds: 42,
        largeMedia: true,
        photoAbove: true,
        aboveText: true,
      ),
    );
    final back = decodePost(encodePost(post)).linkPreview!;
    final sent = post.linkPreview!;
    expect(back.url, sent.url);
    expect(back.displayUrl, sent.displayUrl);
    expect(back.siteName, sent.siteName);
    expect(back.title, sent.title);
    expect(back.author, sent.author);
    expect(back.description, sent.description);
    expect(back.photo!.sizes.single.width, 320);
    expect(back.isVideo, isTrue);
    expect(back.durationSeconds, 42);
    expect(back.largeMedia, isTrue);
    expect(back.photoAbove, isTrue);
    expect(back.aboveText, isTrue);
    // A post encoded by a core that predates previews has none.
    expect(
      decodePost(encodePost(post)..remove('linkPreview')).linkPreview,
      isNull,
    );
  });
}
