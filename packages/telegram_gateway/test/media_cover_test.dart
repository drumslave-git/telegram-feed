import 'package:tdlib_bindings/tdlib_bindings.dart' as td;
import 'package:telegram_gateway/src/mapping.dart' as map;
import 'package:telegram_gateway/telegram_gateway.dart';
import 'package:test/test.dart';

Map<String, Object?> _file(int id) => {
  '@type': 'file',
  'id': id,
  'size': 100,
  'expected_size': 100,
  'local': {'@type': 'localFile', 'path': ''},
  'remote': {'@type': 'remoteFile', 'id': 'r$id', 'unique_id': 'u$id'},
};

Map<String, Object?> _photo({required bool spoiler}) => {
  '@type': 'messagePhoto',
  'has_spoiler': spoiler,
  'caption': {'@type': 'formattedText', 'text': 'look', 'entities': const []},
  'photo': {
    '@type': 'photo',
    'minithumbnail': {
      '@type': 'minithumbnail',
      'width': 40,
      'height': 30,
      'data': '/9j/4AAQ',
    },
    'sizes': [
      {
        '@type': 'photoSize',
        'type': 'm',
        'width': 320,
        'height': 240,
        'photo': _file(1),
      },
    ],
  },
};

Map<String, Object?> _video({required bool spoiler}) => {
  '@type': 'messageVideo',
  'has_spoiler': spoiler,
  'caption': {'@type': 'formattedText', 'text': '', 'entities': const []},
  'video': {
    '@type': 'video',
    'duration': 5,
    'width': 320,
    'height': 240,
    'video': _file(2),
  },
};

td.Message _message(Map<String, Object?> content, {bool sensitive = false}) =>
    td.Message.fromJson({
      '@type': 'message',
      'id': 7,
      'chat_id': -1001,
      'date': 1700000000,
      'content': content,
      if (sensitive)
        'restriction_info': {
          '@type': 'restrictionInfo',
          'restriction_reason': '',
          'has_sensitive_content': true,
        },
    });

MediaCover? _coverOf(Post post) => switch (post.media) {
  PhotoMedia(:final cover) => cover,
  VideoMedia(:final cover) => cover,
  _ => null,
};

void main() {
  test('a photo or a video under a spoiler is covered', () {
    expect(
      _coverOf(map.post(_message(_photo(spoiler: true)))),
      MediaCover.spoiler,
    );
    expect(
      _coverOf(map.post(_message(_video(spoiler: true)))),
      MediaCover.spoiler,
    );
    expect(
      _coverOf(map.post(_message(_photo(spoiler: false)))),
      MediaCover.none,
    );
  });

  test('content for adults is covered as such, spoiler or not', () {
    expect(
      _coverOf(map.post(_message(_photo(spoiler: false), sensitive: true))),
      MediaCover.sensitive,
    );
    expect(
      _coverOf(map.post(_message(_video(spoiler: true), sensitive: true))),
      MediaCover.sensitive,
    );
  });

  test('the cover crosses the core boundary', () {
    for (final content in [_photo(spoiler: true), _video(spoiler: true)]) {
      final post = map.post(_message(content));
      expect(_coverOf(decodePost(encodePost(post))), MediaCover.spoiler);
    }
    final plain = map.post(_message(_photo(spoiler: false)));
    expect(_coverOf(decodePost(encodePost(plain))), MediaCover.none);
  });

  test('a photo brings its miniature, and it crosses the core boundary', () {
    final post = map.post(_message(_photo(spoiler: true)));
    expect((post.media! as PhotoMedia).miniature, '/9j/4AAQ');
    final back = decodePost(encodePost(post)).media! as PhotoMedia;
    expect(back.miniature, '/9j/4AAQ');
    expect(back.cover, MediaCover.spoiler);
    final video = map.post(_message(_video(spoiler: false)));
    expect((video.media! as VideoMedia).miniature, isNull);
  });
}
