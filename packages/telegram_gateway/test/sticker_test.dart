import 'package:tdlib_bindings/tdlib_bindings.dart' as td;
import 'package:telegram_gateway/src/mapping.dart' as map;
import 'package:telegram_gateway/telegram_gateway.dart';
import 'package:test/test.dart';

Map<String, Object?> _file(int id) => {
  '@type': 'file',
  'id': id,
  'size': 100,
  'expected_size': 100,
  'remote': {'@type': 'remoteFile', 'id': 'r$id'},
};

td.Message _message(Map<String, Object?> content) => td.Message.fromJson({
  '@type': 'message',
  'id': 7,
  'chat_id': -1001,
  'date': 1700000000,
  'content': content,
});

void main() {
  test('a sticker maps with its format, size and emoji', () {
    for (final (format, kind) in const [
      ('stickerFormatWebp', StickerFormat.webp),
      ('stickerFormatTgs', StickerFormat.tgs),
      ('stickerFormatWebm', StickerFormat.webm),
    ]) {
      final post = map.post(
        _message({
          '@type': 'messageSticker',
          'sticker': {
            '@type': 'sticker',
            'id': '1',
            'set_id': '2',
            'width': 512,
            'height': 384,
            'emoji': 'A',
            'format': {'@type': format},
            'sticker': _file(9),
            'thumbnail': {
              '@type': 'thumbnail',
              'format': {'@type': 'thumbnailFormatWebp'},
              'width': 128,
              'height': 96,
              'file': _file(8),
            },
          },
        }),
      );
      final sticker = post.media! as StickerMedia;
      expect(sticker.format, kind);
      expect(sticker.width, 512);
      expect(sticker.height, 384);
      expect(sticker.emoji, 'A');
      expect(sticker.thumbnail!.id, 8);
      // The emoji stands in for the text, as the official app's preview does.
      expect(post.text, 'A');
    }
  });

  test('a round video message is a video that knows it is round', () {
    final post = map.post(
      _message({
        '@type': 'messageVideoNote',
        'video_note': {
          '@type': 'videoNote',
          'duration': 12,
          'waveform': '',
          'length': 240,
          'video': _file(5),
        },
        'is_viewed': false,
        'is_secret': false,
      }),
    );
    final video = post.media! as VideoMedia;
    expect(video.isVideoNote, isTrue);
    expect(video.durationSeconds, 12);
    expect(video.file.width, 240);
  });

  test('both survive the trip between isolates', () {
    const sticker = Post(
      chatId: -1,
      messageId: 1,
      date: 1,
      text: 'A',
      media: StickerMedia(
        file: FileRef(id: 9, remoteId: 'r9', size: 100),
        format: StickerFormat.tgs,
        width: 512,
        height: 384,
        emoji: 'A',
      ),
    );
    final backSticker = decodePost(encodePost(sticker)).media! as StickerMedia;
    expect(backSticker.format, StickerFormat.tgs);
    expect(backSticker.emoji, 'A');
    expect(backSticker.width, 512);

    const note = Post(
      chatId: -1,
      messageId: 2,
      date: 1,
      text: '',
      media: VideoMedia(
        file: FileRef(id: 5, remoteId: 'r5', size: 100),
        durationSeconds: 12,
        isVideoNote: true,
      ),
    );
    final backNote = decodePost(encodePost(note)).media! as VideoMedia;
    expect(backNote.isVideoNote, isTrue);
    // A build that predates round messages reads them as ordinary videos.
    final old = encodePost(note);
    (old['media']! as Map<String, Object?>).remove('isVideoNote');
    expect((decodePost(old).media! as VideoMedia).isVideoNote, isFalse);
  });
}
