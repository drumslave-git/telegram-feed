import 'package:tdlib_bindings/tdlib_bindings.dart' as td;
import 'package:telegram_gateway/src/mapping.dart' as map;
import 'package:telegram_gateway/telegram_gateway.dart';
import 'package:test/test.dart';

Post _post(Map<String, Object?> content) => map.post(
  td.Message.fromJson({
    '@type': 'message',
    'id': 7,
    'chat_id': -1001,
    'date': 1700000000,
    'content': content,
  }),
);

Map<String, Object?> _text(String text) => {
  '@type': 'formattedText',
  'text': text,
  'entities': const <Object>[],
};

const _location = {
  '@type': 'location',
  'latitude': 50.45,
  'longitude': 30.52,
  'horizontal_accuracy': 0.0,
};

/// The post as it arrives on the other side of the core boundary.
Post _across(Post post) => decodePost(encodePost(post));

void main() {
  test('a location and a venue are places on the map', () {
    for (final post in [
      _post({'@type': 'messageLocation', 'location': _location}),
      _across(_post({'@type': 'messageLocation', 'location': _location})),
    ]) {
      final place = post.media! as LocationMedia;
      expect(place.latitude, 50.45);
      expect(place.longitude, 30.52);
      expect(place.isVenue, isFalse);
    }
    final venue = _across(
      _post({
        '@type': 'messageVenue',
        'venue': {
          '@type': 'venue',
          'location': _location,
          'title': 'The Quay',
          'address': 'Harbour Road 1',
        },
      }),
    );
    final place = venue.media! as LocationMedia;
    expect(place.title, 'The Quay');
    expect(place.address, 'Harbour Road 1');
    expect(place.isVenue, isTrue);
  });

  test('a contact has a name and a number', () {
    final post = _across(
      _post({
        '@type': 'messageContact',
        'contact': {
          '@type': 'contact',
          'phone_number': '+380501112233',
          'first_name': 'Ada',
          'last_name': 'Writer',
          'user_id': 42,
        },
      }),
    );
    final contact = post.media! as ContactMedia;
    expect(contact.name, 'Ada Writer');
    expect(contact.phone, '+380501112233');
    expect(contact.userId, 42);
  });

  test('a dice is the sticker of what it came to, or its emoji', () {
    final rolled = _post({
      '@type': 'messageDice',
      'emoji': '🎲',
      'value': 4,
      'final_state': {
        '@type': 'diceStickersRegular',
        'sticker': {
          '@type': 'sticker',
          'width': 512,
          'height': 512,
          'emoji': '🎲',
          'format': {'@type': 'stickerFormatTgs'},
          'sticker': {
            '@type': 'file',
            'id': 9,
            'size': 10,
            'expected_size': 10,
            'remote': {'@type': 'remoteFile', 'id': 'r9'},
          },
        },
      },
    });
    expect(rolled.media, isA<StickerMedia>());
    expect(rolled.text, isEmpty);

    // No sticker to show (the slot machine has parts instead): the emoji is the post.
    final slots = _post({'@type': 'messageDice', 'emoji': '🎰', 'value': 7});
    expect(slots.media, isNull);
    expect(slots.text, '🎰');
  });

  test('a game has a title, a description and its words', () {
    final post = _across(
      _post({
        '@type': 'messageGame',
        'game': {
          '@type': 'game',
          'id': '1',
          'short_name': 'tides',
          'title': 'Tide Runner',
          'text': _text('Beat my score'),
          'description': 'Run before the water comes.',
        },
      }),
    );
    final game = post.media! as GameMedia;
    expect(game.title, 'Tide Runner');
    expect(game.description, 'Run before the water comes.');
    expect(post.text, 'Beat my score');
  });

  test('a checklist has a title and tasks that are done or not', () {
    final post = _across(
      _post({
        '@type': 'messageChecklist',
        'list': {
          '@type': 'checklist',
          'title': _text('Before the ferry'),
          'tasks': [
            {
              '@type': 'checklistTask',
              'id': 1,
              'text': _text('Tickets'),
              'completion_date': 1700000000,
            },
            {
              '@type': 'checklistTask',
              'id': 2,
              'text': _text('Coffee'),
              'completion_date': 0,
            },
          ],
        },
      }),
    );
    final list = post.media! as ChecklistMedia;
    expect(list.title, 'Before the ferry');
    expect(list.tasks, const [
      ChecklistTask(text: 'Tickets', done: true),
      ChecklistTask(text: 'Coffee'),
    ]);
  });
}
