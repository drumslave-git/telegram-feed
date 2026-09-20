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
  'last_read_inbox_message_id': 55,
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
      expect(channels.single.lastReadMessageId, 55);
      expect(loads, 2);
    },
  );

  test('myChannels also lists a channel that only a folder holds', () async {
    t.update({
      '@type': 'updateChatFolders',
      'chat_folders': [
        {
          '@type': 'chatFolderInfo',
          'id': 2,
          'name': {
            '@type': 'chatFolderName',
            'text': {'@type': 'formattedText', 'text': 'Memes', 'entities': []},
          },
        },
      ],
      'main_chat_list_position': 0,
    });
    await pumpEventQueue();
    t.handlers['loadChats'] = (_) => {
      '@type': 'error',
      'code': 404,
      'message': 'Not Found',
    };
    // The channel of the folder is in no other list, as after joining by folder link.
    t.handlers['getChats'] = (r) => {
      '@type': 'chats',
      'total_count': 1,
      'chat_ids': (r['chat_list'] as Map)['@type'] == 'chatListMain'
          ? [-1001]
          : [-1002, -1001],
    };
    t.handlers['getChat'] = (r) => r['chat_id'] == -1001
        ? chatJson(-1001, 'News', supergroupId: 1)
        : chatJson(-1002, 'Memes', supergroupId: 2);
    t.handlers['getSupergroup'] = (r) =>
        supergroupJson(r['supergroup_id'] as int);

    final channels = await g.myChannels();
    // Each channel once, the main list first.
    expect(channels.map((c) => c.title), ['News', 'Memes']);
  });

  test(
    'chatFolders keeps the channels of each folder, drops empty ones',
    () async {
      Map<String, Object?> folder(int id, String name) => {
        '@type': 'chatFolderInfo',
        'id': id,
        'name': {
          '@type': 'chatFolderName',
          'text': {'@type': 'formattedText', 'text': name, 'entities': []},
        },
      };
      t.update({
        '@type': 'updateChatFolders',
        'chat_folders': [folder(2, 'News'), folder(3, 'Friends')],
        'main_chat_list_position': 0,
      });
      await pumpEventQueue();
      t.handlers['loadChats'] = (_) => {
        '@type': 'error',
        'code': 404,
        'message': 'Not Found',
      };
      t.handlers['getChats'] = (r) => {
        '@type': 'chats',
        'total_count': 2,
        'chat_ids': (r['chat_list'] as Map)['chat_folder_id'] == 2
            ? [-1001, 7]
            : [7],
      };
      t.handlers['getChat'] = (r) => r['chat_id'] == -1001
          ? chatJson(-1001, 'News', supergroupId: 1)
          : chatJson(7, 'Bob');

      final folders = await g.chatFolders();
      expect(folders, hasLength(1));
      expect(folders.single.id, 2);
      expect(folders.single.title, 'News');
      expect(folders.single.channelIds, [-1001]);
    },
  );

  test(
    'me: profile with photo, phone, premium and the bio from the full info',
    () async {
      t.handlers['getMe'] = (_) => {
        '@type': 'user',
        'id': 42,
        'first_name': 'Ann',
        'last_name': 'Lee',
        'usernames': {
          '@type': 'usernames',
          'active_usernames': ['ann'],
          'disabled_usernames': [],
          'editable_username': 'ann',
        },
        'phone_number': '15550100',
        'is_premium': true,
        'profile_photo': {
          '@type': 'profilePhoto',
          'id': '1',
          'small': {
            '@type': 'file',
            'id': 77,
            'size': 900,
            'expected_size': 900,
            'local': {'@type': 'localFile', 'path': ''},
            'remote': {'@type': 'remoteFile', 'id': 'r77'},
          },
        },
      };
      t.handlers['getUserFullInfo'] = (r) => {
        '@type': 'userFullInfo',
        'bio': {
          '@type': 'formattedText',
          'text': 'Reads a lot',
          'entities': [],
        },
      };
      final me = await g.me();
      expect(me.displayName, 'Ann Lee');
      expect(me.username, 'ann');
      expect(me.phoneDisplay, '+15550100');
      expect(me.photo?.id, 77);
      expect(me.bio, 'Reads a lot');
      expect(me.isPremium, isTrue);

      // Without the full info the basic profile still comes back.
      t.handlers['getUserFullInfo'] = (_) => {
        '@type': 'error',
        'code': 500,
        'message': 'later',
      };
      expect((await g.me()).bio, '');
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

  test('reactions map from interaction info; react sends add/remove', () async {
    t.handlers['getChatHistory'] = (r) => {
      '@type': 'messages',
      'total_count': 1,
      'messages': [
        {
          ...messageJson(-1001, 1),
          'interaction_info': {
            '@type': 'messageInteractionInfo',
            'view_count': 5,
            'forward_count': 0,
            'reactions': {
              '@type': 'messageReactions',
              'reactions': [
                {
                  '@type': 'messageReaction',
                  'type': {'@type': 'reactionTypeEmoji', 'emoji': '🔥'},
                  'total_count': 3,
                  'is_chosen': true,
                },
                {
                  '@type': 'messageReaction',
                  'type': {
                    '@type': 'reactionTypeCustomEmoji',
                    'custom_emoji_id': '5',
                  },
                  'total_count': 1,
                  'is_chosen': false,
                },
              ],
              'are_tags': false,
              'can_get_added_reactions': false,
            },
          },
        },
      ],
    };
    final p = (await g.history(-1001)).single;
    expect(p.views, 5);
    expect(p.reactions.length, 1);
    expect(p.reactions.single.emoji, '🔥');
    expect(p.reactions.single.chosen, isTrue);

    t.handlers['addMessageReaction'] = (_) => {'@type': 'ok'};
    t.handlers['removeMessageReaction'] = (_) => {'@type': 'ok'};
    await g.react(-1001, 1, '👍');
    expect(t.sent.last['@type'], 'addMessageReaction');
    expect((t.sent.last['reaction_type'] as Map)['emoji'], '👍');
    await g.react(-1001, 1, '👍', remove: true);
    expect(t.sent.last['@type'], 'removeMessageReaction');

    t.handlers['getMessageAvailableReactions'] = (_) => {
      '@type': 'availableReactions',
      'top_reactions': [
        {
          '@type': 'availableReaction',
          'type': {'@type': 'reactionTypeEmoji', 'emoji': '👍'},
          'needs_premium': false,
        },
      ],
      'recent_reactions': [],
      'popular_reactions': [
        {
          '@type': 'availableReaction',
          'type': {'@type': 'reactionTypeEmoji', 'emoji': '❤'},
          'needs_premium': false,
        },
      ],
      'allow_custom_emoji': false,
      'are_tags': false,
    };
    expect(await g.availableReactions(-1001, 1), ['👍', '❤']);
  });

  test(
    'discussion thread: open, history with author names, live comment, reply',
    () async {
      t.handlers['getMessageThread'] = (_) => {
        '@type': 'messageThreadInfo',
        'chat_id': -2002,
        'message_thread_id': 900,
        'reply_info': {
          '@type': 'messageReplyInfo',
          'reply_count': 2,
          'recent_replier_ids': [],
          'last_read_inbox_message_id': 0,
          'last_read_outbox_message_id': 0,
          'last_message_id': 0,
        },
        'unread_message_count': 0,
        'messages': [],
      };
      t.handlers['getUser'] = (r) => {
        '@type': 'user',
        'id': r['user_id'],
        'first_name': 'Ann',
        'last_name': 'Lee',
        'profile_photo': {
          '@type': 'profilePhoto',
          'id': '1',
          'small': {'@type': 'file', 'id': 31, 'size': 900},
        },
      };
      t.handlers['getMessageThreadHistory'] = (_) => {
        '@type': 'messages',
        'total_count': 2,
        'messages': [
          {
            ...messageJson(-2002, 902, text: 'second'),
            'topic_id': {
              '@type': 'messageTopicThread',
              'message_thread_id': 900,
            },
            'sender_id': {'@type': 'messageSenderUser', 'user_id': 7},
          },
          {
            ...messageJson(-2002, 900, text: 'root'),
            'topic_id': {
              '@type': 'messageTopicThread',
              'message_thread_id': 900,
            },
          },
        ],
      };
      t.handlers['sendMessage'] = (_) => messageJson(-2002, 903, text: 'mine');

      final thread = (await g.discussion(-1001, 5))!;
      expect(thread.chatId, -2002);
      expect(thread.threadId, 900);
      expect(thread.replyCount, 2);

      final history = await g.threadHistory(thread);
      expect(history.map((c) => c.messageId), [902]); // root excluded
      expect(history.single.author, 'Ann Lee');
      // Id and photo for the avatar and the colour of the name.
      expect(history.single.authorId, isPositive);
      expect(history.single.authorPhoto?.id, 31);

      final live = <Comment>[];
      final sub = g.comments.listen(live.add);
      t.update({
        '@type': 'updateNewMessage',
        'message': {
          ...messageJson(-2002, 904, text: 'new'),
          'topic_id': {'@type': 'messageTopicThread', 'message_thread_id': 900},
          'sender_id': {'@type': 'messageSenderUser', 'user_id': 7},
        },
      });
      t.update({
        '@type': 'updateNewMessage',
        'message': {
          ...messageJson(-2002, 905, text: 'other thread'),
          'message_thread_id': 1,
        },
      });
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(live.map((c) => c.text), ['new']);
      expect(live.single.author, 'Ann Lee'); // cached lookup

      await g.reply(thread, 'hello');
      final sent = t.sent.last;
      expect(sent['@type'], 'sendMessage');
      expect(sent['chat_id'], -2002);
      expect((sent['reply_to'] as Map)['message_id'], 900);
      expect(
        ((sent['input_message_content'] as Map)['text'] as Map)['text'],
        'hello',
      );

      await g.closeThread(thread);
      t.update({
        '@type': 'updateNewMessage',
        'message': {
          ...messageJson(-2002, 906, text: 'after close'),
          'topic_id': {'@type': 'messageTopicThread', 'message_thread_id': 900},
        },
      });
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(live.length, 1);
      await sub.cancel();

      t.handlers['getMessageThread'] = (_) => {
        '@type': 'error',
        'code': 400,
        'message': 'Message has no thread',
      };
      expect(await g.discussion(-1001, 6), isNull);
    },
  );

  test('markViewed forces read through viewMessages', () async {
    t.handlers['viewMessages'] = (_) => {'@type': 'ok'};
    await g.markViewed(-1001, [1, 2]);
    final r = t.sent.last;
    expect(r['@type'], 'viewMessages');
    expect(r['force_read'], true);
    expect((r['source'] as Map)['@type'], 'messageSourceChatHistory');
  });

  test(
    'download returns at once when TDLib reports the file complete',
    () async {
      t.handlers['downloadFile'] = (_) => {
        '@type': 'file',
        'id': 9,
        'size': 100,
        'expected_size': 100,
        'local': {
          '@type': 'localFile',
          'path': '/files/9.jpg',
          'is_downloading_completed': true,
          'downloaded_size': 100,
        },
        'remote': {'@type': 'remoteFile', 'id': 'r9'},
      };
      final done = await g.download(
        const FileRef(id: 9, remoteId: 'r9', size: 100),
      );
      expect(done.localPath, '/files/9.jpg');
      // The unused completion future must not surface an error when the gateway closes.
    },
  );

  test(
    'history keeps paging until the limit: TDLib answers with short pages',
    () async {
      final asked = <int>[];
      t.handlers['getChatHistory'] = (r) {
        final from = r['from_message_id'] as int;
        asked.add(from);
        final ids = switch (from) {
          0 => [50], // the single cached message
          50 => [40, 30],
          30 => [20],
          _ => <int>[],
        };
        return {
          '@type': 'messages',
          'total_count': ids.length,
          'messages': [for (final id in ids) messageJson(-1001, id)],
        };
      };
      final posts = await g.history(-1001, limit: 10);
      expect(posts.map((p) => p.messageId), [50, 40, 30, 20]);
      expect(asked, [0, 50, 30, 20]);

      asked.clear();
      final local = await g.history(-1001, limit: 10, onlyLocal: true);
      expect(local.map((p) => p.messageId), [50]);
      expect(asked, [0]);
    },
  );

  test('historyAfter asks TDLib for newer messages and pages up', () async {
    final asked = <Map<String, Object?>>[];
    t.handlers['getChatHistory'] = (r) {
      asked.add(r);
      final from = r['from_message_id'] as int;
      final ids = switch (from) {
        10 => [30, 20], // newest first, as TDLib answers
        30 => [40],
        _ => <int>[],
      };
      return {
        '@type': 'messages',
        'total_count': ids.length,
        'messages': [for (final id in ids) messageJson(-1001, id)],
      };
    };
    final posts = await g.historyAfter(-1001, afterMessageId: 10, limit: 5);
    expect(posts.map((p) => p.messageId), [40, 30, 20]);
    expect(asked.map((r) => r['from_message_id']), [10, 30, 40]);
    expect(asked.first['offset'], -5);
    expect(asked.first['limit'], 5);
  });

  test('searchHistory pages, carries the total and the next offset', () async {
    final asked = <Map<String, Object?>>[];
    t.handlers['searchChatMessages'] = (r) {
      asked.add(r);
      final from = r['from_message_id'] as int;
      final ids = switch (from) {
        0 => [90],
        90 => [80, 70],
        _ => <int>[],
      };
      return {
        '@type': 'foundChatMessages',
        'total_count': 17,
        'messages': [for (final id in ids) messageJson(-1001, id)],
        'next_from_message_id': ids.isEmpty ? 0 : ids.last,
      };
    };
    final page = await g.searchHistory(-1001, query: 'rain', limit: 3);
    expect(page.posts.map((p) => p.messageId), [90, 80, 70]);
    expect(page.totalCount, 17);
    expect(page.nextFromMessageId, 70);
    expect(page.isLast, isFalse);
    expect(asked.first['query'], 'rain');
    expect(asked.first['filter'], isNull);
    expect(asked.map((r) => r['from_message_id']), [0, 90]);

    // A media tab: no query, a filter, and the end of the history.
    asked.clear();
    t.handlers['searchChatMessages'] = (r) {
      asked.add(r);
      return {
        '@type': 'foundChatMessages',
        'total_count': 1,
        'messages': [messageJson(-1001, 12)],
        'next_from_message_id': 0,
      };
    };
    final media = await g.searchHistory(
      -1001,
      filter: HistoryFilter.photoAndVideo,
    );
    expect(media.posts.single.messageId, 12);
    expect(media.isLast, isTrue);
    expect(
      (asked.single['filter']! as Map<String, Object?>)['@type'],
      'searchMessagesFilterPhotoAndVideo',
    );
  });

  test(
    'messageIdByDate answers 0 when nothing was posted that early',
    () async {
      t.handlers['getChatMessageByDate'] = (r) =>
          (r['date'] as int) < 1700000000
          ? {'@type': 'error', 'code': 404, 'message': 'Message not found'}
          : messageJson(-1001, 31);
      expect(await g.messageIdByDate(-1001, 1700000100), 31);
      expect(await g.messageIdByDate(-1001, 1600000000), 0);
    },
  );

  test('channelInfo reads description, members and the big photo', () async {
    t.handlers['getChat'] = (_) => {
      ...chatJson(-1001, 'News', supergroupId: 1),
      'photo': {
        '@type': 'chatPhotoInfo',
        'small': {'@type': 'file', 'id': 4, 'size': 1, 'expected_size': 1},
        'big': {'@type': 'file', 'id': 5, 'size': 2, 'expected_size': 2},
        'has_animation': false,
        'is_personal': false,
      },
    };
    t.handlers['getSupergroupFullInfo'] = (_) => {
      '@type': 'supergroupFullInfo',
      'description': 'All the news',
      'member_count': 1234,
      'invite_link': {
        '@type': 'chatInviteLink',
        'invite_link': 'https://t.me/+abc',
        'name': '',
        'creator_user_id': 1,
        'date': 0,
        'edit_date': 0,
        'expiration_date': 0,
        'member_limit': 0,
        'member_count': 0,
        'pending_join_request_count': 0,
        'creates_join_request': false,
        'is_primary': true,
        'is_revoked': false,
      },
    };
    final info = await g.channelInfo(-1001);
    expect(info.description, 'All the news');
    expect(info.memberCount, 1234);
    expect(info.inviteLink, 'https://t.me/+abc');
    expect(info.bigPhoto?.id, 5);
  });

  test('canComment follows reply_info', () async {
    t.handlers['getChatHistory'] = (r) => {
      '@type': 'messages',
      'total_count': 2,
      'messages': r['from_message_id'] != 0
          ? <Object?>[]
          : [
              {
                ...messageJson(-1001, 2),
                'interaction_info': {
                  '@type': 'messageInteractionInfo',
                  'view_count': 1,
                  'forward_count': 0,
                  'reply_info': {
                    '@type': 'messageReplyInfo',
                    'reply_count': 0,
                    'recent_replier_ids': <Object?>[],
                    'last_read_inbox_message_id': 0,
                    'last_read_outbox_message_id': 0,
                    'last_message_id': 0,
                  },
                },
              },
              messageJson(-1001, 1),
            ],
    };
    final posts = await g.history(-1001);
    expect(posts.map((p) => p.canComment), [true, false]);
  });
}
