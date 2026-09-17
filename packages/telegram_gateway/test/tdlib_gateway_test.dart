import 'dart:async';

import 'package:telegram_gateway/telegram_gateway.dart';
import 'package:test/test.dart';

/// Scripted TDLib: answers requests by `@type` and lets tests push updates.
final class FakeTransport implements TdTransport {
  final _events = StreamController<Map<String, Object?>>.broadcast();
  final sent = <Map<String, Object?>>[];
  final handlers =
      <String, Map<String, Object?> Function(Map<String, Object?> request)>{};

  @override
  Stream<Map<String, Object?>> get events => _events.stream;

  @override
  void send(Map<String, Object?> request) {
    sent.add(request);
    final h = handlers[request['@type']];
    final response = h == null
        ? {
            '@type': 'error',
            'code': 500,
            'message': 'unscripted ${request['@type']}',
          }
        : h(request);
    scheduleMicrotask(
      () => _events.add({...response, '@extra': request['@extra']}),
    );
  }

  void update(Map<String, Object?> u) => _events.add(u);

  @override
  Future<void> close() => _events.close();
}

const cfg = TdlibConfig(
  apiId: 1,
  apiHash: 'h',
  databaseDirectory: '/db',
  filesDirectory: '/files',
);

Map<String, Object?> chatJson(
  int id,
  String title, {
  int supergroupId = 0,
  bool isChannel = true,
}) => {
  '@type': 'chat',
  'id': id,
  'title': title,
  'last_message': messageJson(id, 77),
  'type': supergroupId == 0
      ? {'@type': 'chatTypePrivate', 'user_id': 5}
      : {
          '@type': 'chatTypeSupergroup',
          'supergroup_id': supergroupId,
          'is_channel': isChannel,
        },
};

Map<String, Object?> supergroupJson(
  int id, {
  String username = '',
  bool member = true,
}) => {
  '@type': 'supergroup',
  'id': id,
  'usernames': {
    '@type': 'usernames',
    'active_usernames': <String>[],
    'disabled_usernames': <String>[],
    'editable_username': username,
  },
  'member_count': 42,
  'is_channel': true,
  'status': member
      ? {'@type': 'chatMemberStatusMember'}
      : {'@type': 'chatMemberStatusLeft'},
};

Map<String, Object?> messageJson(
  int chatId,
  int id, {
  String text = 'hi',
  Map<String, Object?>? content,
}) => {
  '@type': 'message',
  'id': id,
  'chat_id': chatId,
  'date': 1700000000 + id,
  'is_outgoing': false,
  'media_album_id': '0',
  'content':
      content ??
      {
        '@type': 'messageText',
        'text': {'@type': 'formattedText', 'text': text, 'entities': []},
      },
};

void main() {
  late FakeTransport t;
  late TdlibGateway g;

  setUp(() {
    t = FakeTransport();
    t.handlers['getOption'] = (_) => {
      '@type': 'optionValueString',
      'value': '1.8.67',
    };
    g = TdlibGateway(t, cfg);
  });

  tearDown(() => g.close());

  test('auth: sets TDLib parameters, then maps states', () async {
    final states = <AuthState>[];
    final sub = g.authState.listen(states.add);
    t.handlers['setTdlibParameters'] = (_) => {'@type': 'ok'};
    t.update({
      '@type': 'updateAuthorizationState',
      'authorization_state': {'@type': 'authorizationStateWaitTdlibParameters'},
    });
    await Future<void>.delayed(Duration.zero);
    expect(
      t.sent.any(
        (r) => r['@type'] == 'setTdlibParameters' && r['api_hash'] == 'h',
      ),
      isTrue,
    );

    t.update({
      '@type': 'updateAuthorizationState',
      'authorization_state': {'@type': 'authorizationStateWaitPhoneNumber'},
    });
    t.update({
      '@type': 'updateAuthorizationState',
      'authorization_state': {
        '@type': 'authorizationStateWaitCode',
        'code_info': {
          '@type': 'authenticationCodeInfo',
          'phone_number': '+1',
          'type': {'@type': 'authenticationCodeTypeSms', 'length': 5},
          'timeout': 60,
        },
      },
    });
    t.update({
      '@type': 'updateAuthorizationState',
      'authorization_state': {
        '@type': 'authorizationStateWaitPassword',
        'password_hint': 'pet',
      },
    });
    t.update({
      '@type': 'updateAuthorizationState',
      'authorization_state': {'@type': 'authorizationStateReady'},
    });
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(states.first, isA<AuthStarting>()); // replayed current state
    expect(states.whereType<AuthWaitCode>().single.codeLength, 5);
    expect(states.whereType<AuthWaitPassword>().single.hint, 'pet');
    expect(states.last, isA<AuthReady>());
  });

  test('errors become TelegramException', () async {
    t.handlers['checkAuthenticationCode'] = (_) => {
      '@type': 'error',
      'code': 400,
      'message': 'PHONE_CODE_INVALID',
    };
    await expectLater(
      g.checkCode('1'),
      throwsA(
        isA<TelegramException>().having(
          (e) => e.message,
          'message',
          'PHONE_CODE_INVALID',
        ),
      ),
    );
  });

  test(
    'myChannels lists joined channels only, with username and membership',
    () async {
      var loads = 0;
      t.handlers['loadChats'] = (_) => ++loads == 1
          ? {'@type': 'ok'}
          : {'@type': 'error', 'code': 404, 'message': 'Not Found'};
      t.handlers['getChats'] = (_) => {
        '@type': 'chats',
        'total_count': 3,
        'chat_ids': [-1001, -1002, 7],
      };
      t.handlers['getChat'] = (r) => switch (r['chat_id']) {
        -1001 => chatJson(-1001, 'News', supergroupId: 1),
        -1002 => chatJson(-1002, 'Group', supergroupId: 2, isChannel: false),
        _ => chatJson(7, 'Bob'),
      };
      t.handlers['getSupergroup'] = (r) => supergroupJson(
        r['supergroup_id'] as int,
        username: 'newsroom',
        member: false,
      );

      final channels = await g.myChannels();
      expect(channels.map((c) => c.title), ['News']);
      expect(channels.single.username, 'newsroom');
      expect(channels.single.memberCount, 42);
      expect(channels.single.isMember, isFalse);
      expect(channels.single.lastMessageId, 77);
      expect(loads, 2);
    },
  );

  test('history maps text, photo captions and unsupported content', () async {
    t.handlers['getChatHistory'] = (r) => {
      '@type': 'messages',
      'total_count': 3,
      'messages': [
        messageJson(-1001, 30, text: 'plain'),
        messageJson(
          -1001,
          20,
          content: {
            '@type': 'messagePhoto',
            'caption': {
              '@type': 'formattedText',
              'text': 'cap',
              'entities': [],
            },
            'photo': {
              '@type': 'photo',
              'sizes': [
                {
                  '@type': 'photoSize',
                  'type': 'x',
                  'width': 800,
                  'height': 600,
                  'photo': {
                    '@type': 'file',
                    'id': 9,
                    'size': 100,
                    'expected_size': 100,
                    'local': {
                      '@type': 'localFile',
                      'path': '',
                      'is_downloading_completed': false,
                    },
                    'remote': {'@type': 'remoteFile', 'id': 'r9'},
                  },
                },
                {
                  '@type': 'photoSize',
                  'type': 's',
                  'width': 100,
                  'height': 75,
                  'photo': {
                    '@type': 'file',
                    'id': 8,
                    'size': 10,
                    'expected_size': 10,
                    'local': {
                      '@type': 'localFile',
                      'path': '/c/8.jpg',
                      'is_downloading_completed': true,
                    },
                    'remote': {'@type': 'remoteFile', 'id': 'r8'},
                  },
                },
              ],
            },
          },
        ),
        messageJson(
          -1001,
          10,
          content: {
            '@type': 'messagePoll',
            'poll': {
              '@type': 'poll',
              'id': '1',
              'question': {
                '@type': 'formattedText',
                'text': 'q',
                'entities': [],
              },
            },
          },
        ),
      ],
    };
    final posts = await g.history(-1001, limit: 3);
    expect(posts.map((p) => p.messageId), [30, 20, 10]);
    expect(posts[0].text, 'plain');
    expect(posts[1].text, 'cap');
    final photo = posts[1].media as PhotoMedia;
    expect(photo.sizes.map((s) => s.width), [100, 800]);
    expect(photo.sizes.first.localPath, '/c/8.jpg');
    expect(photo.largest.isDownloaded, isFalse);
    expect((posts[2].media as UnsupportedMedia).tdType, 'messagePoll');
    expect(t.sent.last['only_local'], false);
  });

  test('post events: new, edited (re-fetched) and deleted; non-channel chats filtered once known', () async {
    final events = <PostEvent>[];
    final sub = g.postEvents.listen(events.add);
    t.handlers['getMessage'] = (r) => messageJson(-1001, 5, text: 'edited');

    t.update({
      '@type': 'updateNewChat',
      'chat': chatJson(-1001, 'News', supergroupId: 1),
    });
    t.update({'@type': 'updateNewChat', 'chat': chatJson(7, 'Bob')});
    t.update({'@type': 'updateNewMessage', 'message': messageJson(-1001, 5)});
    t.update({
      '@type': 'updateNewMessage',
      'message': messageJson(7, 6),
    }); // private chat: ignored
    t.update({
      '@type': 'updateMessageContent',
      'chat_id': -1001,
      'message_id': 5,
      'new_content': {
        '@type': 'messageText',
        'text': {'@type': 'formattedText', 'text': 'edited', 'entities': []},
      },
    });
    t.update({
      '@type': 'updateDeleteMessages',
      'chat_id': -1001,
      'message_ids': [5],
      'is_permanent': true,
      'from_cache': false,
    });
    t.update({
      '@type': 'updateDeleteMessages',
      'chat_id': -1001,
      'message_ids': [4],
      'is_permanent': false,
      'from_cache': true,
    });
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await sub.cancel();

    expect(events.map((e) => e.runtimeType), [
      PostAdded,
      PostEdited,
      PostsDeleted,
    ]);
    expect((events[1] as PostEdited).post.text, 'edited');
    expect((events[2] as PostsDeleted).messageIds, [5]);
  });

  test('membership events fire on status changes of channels', () async {
    final events = <ChannelMembershipEvent>[];
    final sub = g.membershipEvents.listen(events.add);
    t.update({'@type': 'updateSupergroup', 'supergroup': supergroupJson(1)});
    t.update({
      '@type': 'updateSupergroup',
      'supergroup': supergroupJson(1),
    }); // no change
    t.update({
      '@type': 'updateSupergroup',
      'supergroup': supergroupJson(1, member: false),
    });
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(events.length, 1);
    expect(events.single.chatId, -1000000000001);
    expect(events.single.isMember, isFalse);
  });

  test('download completes from updateFile and reports progress', () async {
    t.handlers['downloadFile'] = (_) => {
      '@type': 'file',
      'id': 9,
      'size': 100,
      'expected_size': 100,
      'local': {
        '@type': 'localFile',
        'path': '',
        'is_downloading_completed': false,
        'downloaded_size': 0,
      },
      'remote': {'@type': 'remoteFile', 'id': 'r9'},
    };
    final progress = <FileProgress>[];
    final sub = g.fileProgress(9).listen(progress.add);
    final future = g.download(const FileRef(id: 9, remoteId: 'r9', size: 100));
    await Future<void>.delayed(Duration.zero);
    t.update({
      '@type': 'updateFile',
      'file': {
        '@type': 'file',
        'id': 9,
        'size': 100,
        'expected_size': 100,
        'local': {
          '@type': 'localFile',
          'path': '',
          'is_downloading_completed': false,
          'downloaded_size': 50,
        },
        'remote': {'@type': 'remoteFile', 'id': 'r9'},
      },
    });
    t.update({
      '@type': 'updateFile',
      'file': {
        '@type': 'file',
        'id': 9,
        'size': 100,
        'expected_size': 100,
        'local': {
          '@type': 'localFile',
          'path': '/c/9.bin',
          'is_downloading_completed': true,
          'downloaded_size': 100,
        },
        'remote': {'@type': 'remoteFile', 'id': 'r9'},
      },
    });
    final ref = await future;
    await sub.cancel();
    expect(ref.localPath, '/c/9.bin');
    expect(progress.map((p) => p.downloaded), [50, 100]);
    expect(t.sent.last['priority'], 16);
  });

  test('markViewed forces read through viewMessages', () async {
    t.handlers['viewMessages'] = (_) => {'@type': 'ok'};
    await g.markViewed(-1001, [1, 2]);
    final r = t.sent.last;
    expect(r['@type'], 'viewMessages');
    expect(r['force_read'], true);
    expect((r['source'] as Map)['@type'], 'messageSourceChatHistory');
  });
}
