import 'dart:async';

import 'package:tdlib_bindings/tdlib_bindings.dart' as td;

import 'gateway.dart';
import 'mapping.dart' as map;
import 'models.dart';
import 'td_transport.dart';

/// Parameters for `setTdlibParameters`. `apiId`/`apiHash` come from `--dart-define` in the app.
final class TdlibConfig {
  const TdlibConfig({
    required this.apiId,
    required this.apiHash,
    required this.databaseDirectory,
    required this.filesDirectory,
    this.databaseEncryptionKey = '',
    this.useTestDc = false,
    this.deviceModel = 'telegram-feed',
    this.systemVersion = '',
    this.applicationVersion = '0.1.0',
    this.systemLanguageCode = 'en',
  });
  final int apiId;
  final String apiHash;
  final String databaseDirectory;
  final String filesDirectory;

  /// Base64 of the raw key; empty for an unencrypted database.
  final String databaseEncryptionKey;
  final bool useTestDc;
  final String deviceModel;
  final String systemVersion;
  final String applicationVersion;
  final String systemLanguageCode;
}

/// [TelegramGateway] on top of any TDLib JSON transport (`FfiTransport` on Android).
final class TdlibGateway implements TelegramGateway {
  TdlibGateway(TdTransport transport, this.config, {this.log})
    : _client = TdClient(transport) {
    // asyncMap keeps update handling strictly ordered even when a handler awaits a request
    // (responses are routed through TdClient's pending map, not this stream, so no deadlock).
    _sub = _client.updates.asyncMap(_onUpdate).listen((_) {});
    // Any request wakes TDLib up; it answers with updateAuthorizationState.
    _client
        .call(const td.GetOption(name: 'version'))
        .then(
          (v) => log?.call('TDLib ${(v as td.OptionValueString?)?.value}'),
          onError: (Object e) => log?.call('getOption failed: $e'),
        );
  }

  final TdlibConfig config;
  final void Function(String)? log;
  final TdClient _client;
  late final StreamSubscription<void> _sub;

  AuthState _auth = const AuthStarting();
  final _authCtl = StreamController<AuthState>.broadcast();
  final _postCtl = StreamController<PostEvent>.broadcast();
  final _memberCtl = StreamController<ChannelMembershipEvent>.broadcast();
  final _fileCtl = StreamController<FileProgress>.broadcast();
  final _commentCtl = StreamController<Comment>.broadcast();
  final _goneCtl = StreamController<CommentsGone>.broadcast();
  final _readCtl = StreamController<ReadState>.broadcast();
  List<td.ChatFolderInfo> _folders = const [];
  final _supergroups = <int, td.Supergroup>{};

  /// The account's own user id, which is also the chat id of Saved Messages.
  int? _myId;
  final _channelChatIds = <int>{};

  /// (discussion chat id, thread id) of threads a screen has open.
  final _openThreads = <(int, int)>{};
  final _senders = <String, map.Sender>{};

  /// What TDLib last said about its connection.
  var _connection = ConnectionStatus.connecting;
  final _connectionCtl = StreamController<ConnectionStatus>.broadcast();

  /// Stickers of custom emoji already asked for, by id: they never change.
  final _customEmoji = <String, StickerMedia>{};

  /// Words and thumbnail of posts that other posts answer, by "chat/message".
  final _replied = <String, ({String text, Media? media, PhotoMedia? photo})>{};

  @override
  Stream<AuthState> get authState async* {
    yield _auth;
    yield* _authCtl.stream;
  }

  @override
  Stream<PostEvent> get postEvents => _postCtl.stream;
  @override
  Stream<ChannelMembershipEvent> get membershipEvents => _memberCtl.stream;
  @override
  Stream<ReadState> get readUpdates => _readCtl.stream;

  Future<void> _onUpdate(td.Update u) async {
    switch (u) {
      case td.UpdateAuthorizationState(:final authorizationState):
        if (authorizationState is td.AuthorizationStateWaitTdlibParameters) {
          await _setParameters();
          return;
        }
        if (authorizationState != null) {
          _auth = map.authState(authorizationState);
          _authCtl.add(_auth);
        }
      case td.UpdateNewMessage(:final message):
        if (message == null) return;
        if (_openThreads.contains((message.chatId, map.threadIdOf(message)))) {
          _commentCtl.add(await _comment(message));
        } else if (_isChannelChat(message.chatId) ||
            // Saved Messages too, once Telegram has the post: one still being sent
            // changes its id when it arrives.
            (message.chatId == _myId && message.sendingState == null)) {
          _postCtl.add(PostAdded(await _post(message)));
        }
      case td.UpdateMessageSendSucceeded(:final message, :final oldMessageId):
        // A post saved to Saved Messages has arrived there: its timeline shows it.
        if (message != null && message.chatId == _myId) {
          _postCtl.add(PostAdded(await _post(message)));
        }
        // An own comment has its real id now: the temporary one goes.
        if (message != null && _inOpenThread(message)) {
          _goneCtl.add(
            CommentsGone(chatId: message.chatId, messageIds: [oldMessageId]),
          );
          _commentCtl.add(await _comment(message));
        }
      case td.UpdateMessageSendFailed(:final message, :final oldMessageId):
        if (message != null && _inOpenThread(message)) {
          if (oldMessageId != message.id) {
            _goneCtl.add(
              CommentsGone(chatId: message.chatId, messageIds: [oldMessageId]),
            );
          }
          _commentCtl.add(await _comment(message));
        }
      case td.UpdateMessageContent(:final chatId, :final messageId)
          when _threadChat(chatId):
        await _emitComment(chatId, messageId);
      case td.UpdateMessageEdited(:final chatId, :final messageId)
          when _threadChat(chatId):
        await _emitComment(chatId, messageId);
      case td.UpdateMessageInteractionInfo(:final chatId, :final messageId)
          when _threadChat(chatId):
        await _emitComment(chatId, messageId);
      case td.UpdateDeleteMessages(
            :final chatId,
            :final messageIds,
            :final isPermanent,
            :final fromCache,
          )
          when _threadChat(chatId):
        if (isPermanent && !fromCache) {
          _goneCtl.add(CommentsGone(chatId: chatId, messageIds: messageIds));
        }
      case td.UpdateMessageContent(:final chatId, :final messageId):
        if (_isChannelChat(chatId)) await _emitEdited(chatId, messageId);
      case td.UpdateMessageEdited(:final chatId, :final messageId):
        if (_isChannelChat(chatId)) await _emitEdited(chatId, messageId);
      case td.UpdateMessageIsPinned(:final chatId, :final messageId):
        // The pin in the post's footer comes and goes with it.
        if (_isChannelChat(chatId)) await _emitEdited(chatId, messageId);
      case td.UpdateMessageInteractionInfo(:final chatId, :final messageId):
        // Reactions and view counts change often; a re-fetch keeps Post complete.
        if (_isChannelChat(chatId)) await _emitEdited(chatId, messageId);
      case td.UpdateDeleteMessages(
        :final chatId,
        :final messageIds,
        :final isPermanent,
        :final fromCache,
      ):
        // Saved Messages too: its timeline drops what the reader deleted there.
        if (isPermanent &&
            !fromCache &&
            (_isChannelChat(chatId) || chatId == _myId)) {
          _postCtl.add(PostsDeleted(chatId: chatId, messageIds: messageIds));
        }
      case td.UpdateSupergroup(:final supergroup):
        if (supergroup == null) return;
        final before = _supergroups[supergroup.id];
        _supergroups[supergroup.id] = supergroup;
        if (supergroup.isChannel) {
          _channelChatIds.add(map.chatIdOfSupergroup(supergroup.id));
        }
        final wasMember = before == null
            ? null
            : map.isMemberStatus(before.status);
        final isMember = map.isMemberStatus(supergroup.status);
        if (supergroup.isChannel &&
            wasMember != null &&
            wasMember != isMember) {
          _memberCtl.add(
            ChannelMembershipEvent(
              chatId: map.chatIdOfSupergroup(supergroup.id),
              isMember: isMember,
            ),
          );
        }
      case td.UpdateNewChat(:final chat):
        if (chat?.type case td.ChatTypeSupergroup(:final isChannel)
            when isChannel) {
          _channelChatIds.add(chat!.id);
        }
      case td.UpdateChatReadInbox(
        :final chatId,
        :final lastReadInboxMessageId,
        :final unreadCount,
      ):
        if (_isChannelChat(chatId)) {
          _readCtl.add(
            ReadState(
              chatId: chatId,
              lastReadMessageId: lastReadInboxMessageId,
              unreadCount: unreadCount,
            ),
          );
        }
      case td.UpdateChatFolders(:final chatFolders):
        _folders = chatFolders;
      case td.UpdateConnectionState(:final state):
        _connection = switch (state) {
          td.ConnectionStateWaitingForNetwork() =>
            ConnectionStatus.waitingForNetwork,
          td.ConnectionStateConnectingToProxy() =>
            ConnectionStatus.connectingToProxy,
          td.ConnectionStateConnecting() => ConnectionStatus.connecting,
          td.ConnectionStateUpdating() => ConnectionStatus.updating,
          td.ConnectionStateReady() => ConnectionStatus.ready,
          null => _connection,
        };
        _connectionCtl.add(_connection);
      case td.UpdateFile(:final file):
        if (file != null) _fileCtl.add(_progress(file));
      default:
        break;
    }
  }

  /// Before the chat list is loaded TDLib has told us about no chats, so let everything through.
  bool _isChannelChat(int chatId) =>
      _channelChatIds.isEmpty || _channelChatIds.contains(chatId);

  Future<void> _emitEdited(int chatId, int messageId) async {
    try {
      final m = await _client.call(
        td.GetMessage(chatId: chatId, messageId: messageId),
      );
      _postCtl.add(PostEdited(await _post(m)));
    } on TelegramException catch (e) {
      log?.call('getMessage($chatId, $messageId) failed: $e');
    }
  }

  Future<void> _setParameters() => _client.call(
    td.SetTdlibParameters(
      useTestDc: config.useTestDc,
      databaseDirectory: config.databaseDirectory,
      filesDirectory: config.filesDirectory,
      databaseEncryptionKey: config.databaseEncryptionKey,
      useFileDatabase: true,
      useChatInfoDatabase: true,
      useMessageDatabase: true,
      useSecretChats: false,
      apiId: config.apiId,
      apiHash: config.apiHash,
      systemLanguageCode: config.systemLanguageCode,
      deviceModel: config.deviceModel,
      systemVersion: config.systemVersion,
      applicationVersion: config.applicationVersion,
    ),
  );

  @override
  Future<void> setPhoneNumber(String phone) =>
      _client.call(td.SetAuthenticationPhoneNumber(phoneNumber: phone));
  @override
  Future<void> checkCode(String code) =>
      _client.call(td.CheckAuthenticationCode(code: code));
  @override
  Future<void> resendCode() => _client.call(td.ResendAuthenticationCode());
  @override
  Future<void> setEmailAddress(String email) =>
      _client.call(td.SetAuthenticationEmailAddress(emailAddress: email));
  @override
  Future<void> checkEmailCode(String code) => _client.call(
    td.CheckAuthenticationEmailCode(
      code: td.EmailAddressAuthenticationCode(code: code),
    ),
  );
  @override
  Future<void> checkPassword(String password) =>
      _client.call(td.CheckAuthenticationPassword(password: password));
  @override
  Future<void> registerUser({
    required String firstName,
    String lastName = '',
  }) => _client.call(
    td.RegisterUser(
      firstName: firstName,
      lastName: lastName,
      disableNotification: false,
    ),
  );
  @override
  Future<void> requestQrCode() =>
      _client.call(const td.RequestQrCodeAuthentication(otherUserIds: []));
  @override
  Future<void> logOut() => _client.call(const td.LogOut());

  @override
  Future<List<Channel>> myChannels() async {
    final out = <Channel>[];
    final seen = <int>{};
    for (final (name, list) in _chatLists()) {
      var added = 0;
      for (final id in await _chatIdsOf(list)) {
        if (!seen.add(id)) continue;
        final channel = await _channelOf(id);
        if (channel == null) continue;
        out.add(channel);
        added++;
      }
      if (added > 0) log?.call('myChannels: $added channels from $name');
    }
    return out;
  }

  /// The main list first, then every folder. A channel joined through a folder invite link
  /// is in its folder's list and in no other, so the main list alone misses it. The archive
  /// is not read: archived channels stay out of the app's lists (founder decision
  /// 2026-09-20), except when a folder of theirs holds one.
  List<(String, td.ChatList)> _chatLists() => [
    ('the main list', const td.ChatListMain()),
    for (final f in _folders)
      (
        'folder "${f.name?.text?.text ?? f.id}"',
        td.ChatListFolder(chatFolderId: f.id),
      ),
  ];

  Future<List<int>> _chatIdsOf(td.ChatList list) async {
    await _loadAll(list);
    return (await _client.call(td.GetChats(chatList: list, limit: 1000)))
        .chatIds;
  }

  /// Whether the chat is a channel, remembering the answer. Cheaper than [_channelOf]: the
  /// folder tabs get their channels from [myChannels], this only sorts the ids.
  Future<bool> _isChannelChatId(int id) async {
    if (_channelChatIds.contains(id)) return true;
    final chat = await _client.call(td.GetChat(chatId: id));
    if (chat.type case td.ChatTypeSupergroup(:final isChannel) when isChannel) {
      _channelChatIds.add(id);
      return true;
    }
    return false;
  }

  /// The channel behind a chat id, or null when the chat is a group, a user or a bot.
  Future<Channel?> _channelOf(int id) async {
    final chat = await _client.call(td.GetChat(chatId: id));
    if (chat.type
        case td.ChatTypeSupergroup(:final supergroupId, :final isChannel)
        when isChannel) {
      final sg =
          _supergroups[supergroupId] ??
          await _client.call(td.GetSupergroup(supergroupId: supergroupId));
      _supergroups[supergroupId] = sg;
      _channelChatIds.add(id);
      final album = await _albumOf(chat);
      return map.channel(
        chat,
        sg,
        album: album?.media,
        albumText: album?.text ?? '',
        muted: await _isMuted(chat),
      );
    }
    return null;
  }

  /// The album a chat's newest message belongs to, by chat, with the id of that message:
  /// asked once per newest message.
  final _albums = <int, (int, ({List<Media> media, String text})?)>{};

  /// The parts of the album the newest message of [chat] closes, oldest first, and the
  /// album's words; null when that message stands alone. The chat list carries one
  /// message, so the parts before it are read from the history.
  Future<({List<Media> media, String text})?> _albumOf(td.Chat chat) async {
    final last = chat.lastMessage;
    if (last == null || last.mediaAlbumId == 0) return null;
    final kept = _albums[chat.id];
    if (kept != null && kept.$1 == last.id) return kept.$2;
    final parts = <td.Message>[last];
    try {
      // An album has ten parts at most.
      final older = await _client.call(
        td.GetChatHistory(
          chatId: chat.id,
          fromMessageId: last.id,
          offset: 0,
          limit: 10,
          onlyLocal: false,
        ),
      );
      for (final m in older.messages) {
        if (m.id == last.id) continue;
        if (m.mediaAlbumId != last.mediaAlbumId) break;
        parts.add(m);
      }
    } on TelegramException {
      // The newest part alone, as the chat list has it.
    }
    final media = <Media>[];
    var text = '';
    for (final m in parts.reversed) {
      final (words, carried) = map.content(m.content);
      if (carried != null) media.add(carried);
      if (text.isEmpty) text = words;
    }
    final album = media.length > 1 ? (media: media, text: text) : null;
    _albums[chat.id] = (last.id, album);
    return album;
  }

  /// Whether channels are muted where a channel has no setting of its own; asked once and
  /// again after Telegram says the setting changed.
  Future<bool>? _channelsMutedByDefault;

  Future<bool> _isMuted(td.Chat chat) async {
    final settings = chat.notificationSettings;
    if (settings == null) return false;
    if (!settings.useDefaultMuteFor) return settings.muteFor > 0;
    try {
      return await (_channelsMutedByDefault ??= _client
          .call(
            const td.GetScopeNotificationSettings(
              scope: td.NotificationSettingsScopeChannelChats(),
            ),
          )
          .then((s) => s.muteFor > 0));
    } on TelegramException {
      _channelsMutedByDefault = null;
      return false;
    }
  }

  @override
  Future<List<ChatFolder>> chatFolders() async {
    final out = <ChatFolder>[];
    for (final info in _folders) {
      final ids = await _chatIdsOf(td.ChatListFolder(chatFolderId: info.id));
      final channels = <int>[];
      for (final id in ids) {
        if (await _isChannelChatId(id)) channels.add(id);
      }
      if (channels.isNotEmpty) {
        out.add(
          ChatFolder(
            id: info.id,
            title: info.name?.text?.text ?? '',
            channelIds: channels,
          ),
        );
      }
    }
    return out;
  }

  /// loadChats answers 404 once the whole list is loaded.
  Future<void> _loadAll(td.ChatList list) async {
    for (var i = 0; i < 20; i++) {
      try {
        await _client.call(td.LoadChats(chatList: list, limit: 100));
      } on TelegramException catch (e) {
        if (e.code == 404) break;
        rethrow;
      }
    }
  }

  @override
  Future<List<Post>> history(
    int chatId, {
    int fromMessageId = 0,
    int limit = 30,
    bool onlyLocal = false,
  }) async {
    // TDLib picks the page size itself and often answers the first request with the single
    // cached message, so keep asking until [limit] posts or the end of the history.
    final out = <Post>[];
    var from = fromMessageId;
    while (out.length < limit) {
      final r = await _client.call(
        td.GetChatHistory(
          chatId: chatId,
          fromMessageId: from,
          offset: 0,
          limit: limit - out.length,
          onlyLocal: onlyLocal,
        ),
      );
      final older = [
        for (final m in r.messages)
          if (from == 0 || m.id < from) m,
      ];
      if (older.isEmpty) break;
      out.addAll(await _posts(older));
      from = older.last.id;
      // Local reads are one cheap probe before the network.
      if (onlyLocal) break;
    }
    return out;
  }

  @override
  Future<List<Post>> historyAfter(
    int chatId, {
    required int afterMessageId,
    int limit = 30,
  }) async {
    // A negative offset is TDLib's way to ask for newer messages: the window starts
    // -offset messages before [fromMessageId]. Pages are short here too.
    final out = <Post>[];
    var from = afterMessageId;
    while (out.length < limit) {
      final n = (limit - out.length).clamp(1, 99);
      final r = await _client.call(
        td.GetChatHistory(
          chatId: chatId,
          fromMessageId: from,
          offset: -n,
          limit: n,
          onlyLocal: false,
        ),
      );
      final newer = [
        for (final m in r.messages)
          if (m.id > from) m,
      ]..sort((a, b) => a.id.compareTo(b.id));
      if (newer.isEmpty) break;
      out.addAll(await _posts(newer));
      from = newer.last.id;
    }
    return out.reversed.toList();
  }

  @override
  Future<SearchPage> searchHistory(
    int chatId, {
    String query = '',
    HistoryFilter filter = HistoryFilter.any,
    int fromMessageId = 0,
    int limit = 30,
  }) async {
    // Like getChatHistory, searchChatMessages picks its own page size and often answers
    // with fewer messages than asked; keep asking until [limit] or the end.
    final out = <Post>[];
    var total = 0;
    var next = fromMessageId;
    var first = true;
    while (out.length < limit) {
      final r = await _client.call(
        td.SearchChatMessages(
          chatId: chatId,
          query: query,
          fromMessageId: next,
          offset: 0,
          limit: limit - out.length,
          filter: map.searchFilter(filter),
        ),
      );
      if (first) {
        total = r.totalCount;
        first = false;
      }
      out.addAll(await _posts(r.messages));
      next = r.nextFromMessageId;
      if (next == 0 || r.messages.isEmpty) {
        next = 0;
        break;
      }
    }
    return SearchPage(posts: out, totalCount: total, nextFromMessageId: next);
  }

  @override
  Future<Map<HistoryFilter, int>> mediaCounts(int chatId) async {
    final out = <HistoryFilter, int>{};
    await Future.wait([
      for (final kind in sharedMediaKinds)
        () async {
          try {
            final counted = await _client.call(
              td.GetChatMessageCount(
                chatId: chatId,
                filter: map.searchFilter(kind),
                returnLocal: false,
              ),
            );
            out[kind] = counted.count;
          } on TelegramException {
            out[kind] = -1;
          }
        }(),
    ]);
    return out;
  }

  @override
  Future<int> messageIdByDate(int chatId, int unixDate) async {
    try {
      return (await _client.call(
        td.GetChatMessageByDate(chatId: chatId, date: unixDate),
      )).id;
    } on TelegramException catch (e) {
      // 404: nothing was posted that early.
      if (e.code == 404) return 0;
      rethrow;
    }
  }

  @override
  Future<ChannelInfo> channelInfo(int chatId) async {
    final chat = await _client.call(td.GetChat(chatId: chatId));
    final big = chat.photo?.big;
    var description = '';
    var memberCount = 0;
    var inviteLink = '';
    if (chat.type case td.ChatTypeSupergroup(:final supergroupId)) {
      final full = await _client.call(
        td.GetSupergroupFullInfo(supergroupId: supergroupId),
      );
      description = full.description;
      memberCount = full.memberCount;
      inviteLink = full.inviteLink?.inviteLink ?? '';
    }
    // The description is plain text: TDLib finds what opens in it.
    var entities = const <TextEntity>[];
    if (description.isNotEmpty) {
      try {
        final found = await _client.call(td.GetTextEntities(text: description));
        entities = map.entities(
          td.FormattedText(text: description, entities: found.entities),
        );
      } on TelegramException {
        // The words then stand without links.
      }
    }
    // Every photo the channel has had is a service message of its history.
    final photos = <PhotoMedia>[];
    try {
      final changes = await _client.call(
        td.SearchChatMessages(
          chatId: chatId,
          query: '',
          fromMessageId: 0,
          offset: 0,
          limit: 30,
          filter: const td.SearchMessagesFilterChatPhoto(),
        ),
      );
      for (final m in changes.messages) {
        final content = m.content;
        if (content is td.MessageChatChangePhoto && content.photo != null) {
          final photo = map.chatPhoto(content.photo!);
          if (photo.sizes.isNotEmpty) photos.add(photo);
        }
      }
    } on TelegramException {
      // The current photo alone.
    }
    return ChannelInfo(
      chatId: chatId,
      description: description,
      memberCount: memberCount,
      inviteLink: inviteLink,
      bigPhoto: big == null ? null : map.fileRef(big),
      descriptionEntities: entities,
      photos: photos,
    );
  }

  @override
  Future<void> markViewed(int chatId, List<int> messageIds) => _client.call(
    td.ViewMessages(
      chatId: chatId,
      messageIds: messageIds,
      source: const td.MessageSourceChatHistory(),
      forceRead: true,
    ),
  );

  @override
  Future<void> countViews(int chatId, List<int> messageIds) => _client.call(
    td.ViewMessages(
      chatId: chatId,
      messageIds: messageIds,
      source: const td.MessageSourceChatHistory(),
      forceRead: false,
    ),
  );

  @override
  Future<ReadState> readState(int chatId) async {
    final chat = await _client.call(td.GetChat(chatId: chatId));
    return ReadState(
      chatId: chatId,
      lastReadMessageId: chat.lastReadInboxMessageId,
      unreadCount: chat.unreadCount,
      lastMessageId: chat.lastMessage?.id ?? 0,
    );
  }

  @override
  Future<FileRef> download(FileRef ref, {int priority = 16}) async {
    if (ref.isDownloaded) return ref;
    final done = _fileCtl.stream.firstWhere(
      (p) => p.fileId == ref.id && p.isComplete,
    )..ignore(); // unused when TDLib reports the file complete right away
    final f = await _client.call(
      td.DownloadFile(
        fileId: ref.id,
        priority: priority,
        offset: 0,
        limit: 0,
        synchronous: false,
      ),
    );
    if (f.local?.isDownloadingCompleted ?? false) {
      return ref.copyWith(localPath: f.local!.path);
    }
    final p = await done;
    return ref.copyWith(localPath: p.localPath);
  }

  @override
  Future<FileProgress> downloadFrom(
    int fileId, {
    int offset = 0,
    int priority = 32,
    int limit = 0,
  }) async => _progress(
    await _client.call(
      td.DownloadFile(
        fileId: fileId,
        priority: priority,
        offset: offset,
        limit: limit,
        synchronous: false,
      ),
    ),
  );

  @override
  Future<int> downloadedPrefix(int fileId, int offset) async =>
      (await _client.call(
        td.GetFileDownloadedPrefixSize(fileId: fileId, offset: offset),
      )).size;

  @override
  Future<void> cancelDownload(int fileId) =>
      _client.call(td.CancelDownloadFile(fileId: fileId, onlyIfPending: false));

  /// A post with the name of the channel or person it was forwarded from; the lookup is the
  /// sender cache of the comments, so each origin costs one request per session.
  Future<Post> _post(td.Message m) async {
    final origin = map.forwardOrigin(m);
    return map.post(
      m,
      forwardedFrom: origin == null ? null : await _named(origin),
      replyTo: await _reply(m),
      recentCommenters: await _commenters(m),
    );
  }

  /// The people who commented on [m] last, with the names and photos the sender cache
  /// holds: one lookup per person and session.
  Future<List<Commenter>> _commenters(td.Message m) async {
    final ids = m.interactionInfo?.replyInfo?.recentReplierIds ?? const [];
    final out = <Commenter>[];
    for (final id in ids.take(3)) {
      final sender = switch (id) {
        td.MessageSenderUser(:final userId) =>
          _senders['u$userId'] ??= await _userSender(userId),
        td.MessageSenderChat(:final chatId) =>
          _senders['c$chatId'] ??= await _chatSender(chatId),
      };
      out.add(Commenter(id: sender.id, name: sender.name, photo: sender.photo));
    }
    return out;
  }

  /// The post a post answers. TDLib hands over the words only when the answered post is in
  /// another chat; inside the channel it gives the ids alone, so the post itself is fetched
  /// once and kept (its words and its thumbnail never change for this purpose).
  Future<ReplyTarget?> _reply(td.Message m) async {
    var target = map.replyTarget(m);
    if (target == null) return null;
    final origin = map.replyOrigin(m);
    if (origin != null) {
      target = target.withTitle((await _named(origin)).title);
    }
    if (target.text.isNotEmpty ||
        target.media != null ||
        target.messageId == 0) {
      return target;
    }
    final key = '${target.chatId}/${target.messageId}';
    final known = _replied[key];
    if (known != null) {
      return target.withText(
        known.text,
        media: known.media,
        photo: known.photo,
      );
    }
    try {
      final answered = await _client.call(
        td.GetMessage(chatId: target.chatId, messageId: target.messageId),
      );
      final words = map.preview(answered.content);
      final media = map.previewMedia(answered.content);
      final photo = map.replyPhoto(answered.content);
      // A session reads a bounded number of posts, but not an unbounded number of them.
      if (_replied.length > 500) _replied.clear();
      _replied[key] = (text: words, media: media, photo: photo);
      return target.withText(words, media: media, photo: photo);
    } on TelegramException {
      return target; // the answered post is gone or out of reach
    }
  }

  Future<List<Post>> _posts(Iterable<td.Message> messages) async {
    final out = <Post>[];
    for (final m in messages) {
      out.add(await _post(m));
    }
    return out;
  }

  Future<ForwardOrigin> _named(ForwardOrigin o) async {
    if (o.title.isNotEmpty) return o;
    if (o.chatId != 0) {
      final s = _senders['c${o.chatId}'] ??= await _chatSender(o.chatId);
      return o.withTitle(s.name);
    }
    if (o.userId != 0) {
      final s = _senders['u${o.userId}'] ??= await _userSender(o.userId);
      return o.withTitle(s.name);
    }
    return o;
  }

  /// Name and photo of whoever wrote [m], looked up once per session.
  Future<map.Sender> _sender(td.Message m) async {
    switch (m.senderId) {
      case td.MessageSenderUser(:final userId):
        return _senders['u$userId'] ??= await _userSender(userId);
      case td.MessageSenderChat(:final chatId):
        return _senders['c$chatId'] ??= await _chatSender(chatId);
      default:
        return (id: 0, name: '', photo: null);
    }
  }

  Future<map.Sender> _userSender(int userId) async {
    try {
      final u = await _client.call(td.GetUser(userId: userId));
      final small = u.profilePhoto?.small;
      return (
        id: userId,
        name: [u.firstName, u.lastName].where((s) => s.isNotEmpty).join(' '),
        photo: small == null ? null : map.fileRef(small),
      );
    } on TelegramException {
      return (id: userId, name: '', photo: null);
    }
  }

  Future<map.Sender> _chatSender(int chatId) async {
    try {
      final c = await _client.call(td.GetChat(chatId: chatId));
      final small = c.photo?.small;
      return (
        id: chatId,
        name: c.title,
        photo: small == null ? null : map.fileRef(small),
      );
    } on TelegramException {
      return (id: chatId, name: '', photo: null);
    }
  }

  @override
  Future<Thread?> discussion(int chatId, int messageId) async {
    try {
      final info = await _client.call(
        td.GetMessageThread(chatId: chatId, messageId: messageId),
      );
      final (write, wait, delay) = await _threadWrite(info.chatId);
      final t = Thread(
        chatId: info.chatId,
        threadId: info.messageThreadId,
        postChatId: chatId,
        postMessageId: messageId,
        replyCount: info.replyInfo?.replyCount ?? 0,
        lastReadId: info.replyInfo?.lastReadInboxMessageId ?? 0,
        unreadCount: info.unreadMessageCount,
        write: write,
        slowModeWait: wait,
        slowModeDelay: delay,
      );
      _openThreads.add((t.chatId, t.threadId));
      return t;
    } on TelegramException catch (e) {
      // 400 "Message has no thread" / channel without a discussion group.
      if (e.code == 400 || e.code == 404) return null;
      rethrow;
    }
  }

  @override
  Future<void> markChannelUnread(int chatId, {required bool unread}) =>
      _client.call(
        td.ToggleChatIsMarkedAsUnread(chatId: chatId, isMarkedAsUnread: unread),
      );

  @override
  Future<void> markCommentsViewed(Thread thread, List<int> messageIds) async {
    if (messageIds.isEmpty) return;
    await _client.call(
      td.ViewMessages(
        chatId: thread.chatId,
        messageIds: messageIds,
        source: const td.MessageSourceMessageThreadHistory(),
        forceRead: true,
      ),
    );
  }

  @override
  Future<List<Comment>> threadHistory(
    Thread thread, {
    int fromMessageId = 0,
    int limit = 30,
  }) async {
    final r = await _client.call(
      td.GetMessageThreadHistory(
        chatId: thread.postChatId,
        messageId: thread.postMessageId,
        fromMessageId: fromMessageId,
        offset: 0,
        limit: limit,
      ),
    );
    final out = <Comment>[];
    for (final m in r.messages) {
      if (m.id == thread.threadId) continue; // the forwarded post itself
      out.add(await _comment(m));
    }
    return out;
  }

  /// A discussion group one of whose threads is open.
  bool _threadChat(int chatId) => _openThreads.any((t) => t.$1 == chatId);

  bool _inOpenThread(td.Message m) =>
      _openThreads.contains((m.chatId, map.threadIdOf(m)));

  /// A comment changed (its words, its reactions): the open thread hears of it.
  Future<void> _emitComment(int chatId, int messageId) async {
    try {
      final m = await _client.call(
        td.GetMessage(chatId: chatId, messageId: messageId),
      );
      if (_inOpenThread(m)) _commentCtl.add(await _comment(m));
    } on TelegramException {
      // Deleted meanwhile: the deletion says so itself.
    }
  }

  /// A comment with its author and, when it answers another comment, with that one's
  /// author and first words (looked up once and kept).
  Future<Comment> _comment(td.Message m) async {
    CommentReply? reply;
    final to = m.replyTo;
    if (to is td.MessageReplyToMessage &&
        to.messageId != 0 &&
        to.messageId != map.threadIdOf(m) &&
        (to.chatId == 0 || to.chatId == m.chatId)) {
      final key = '${m.chatId}/${to.messageId}';
      reply = _commentReplies[key];
      if (reply == null) {
        try {
          final answered = await _client.call(
            td.GetMessage(chatId: m.chatId, messageId: to.messageId),
          );
          reply = CommentReply(
            messageId: to.messageId,
            author: (await _sender(answered)).name,
            text: to.quote?.text?.text ?? map.preview(answered.content),
          );
        } on TelegramException {
          reply = CommentReply(
            messageId: to.messageId,
          ); // gone, or out of reach
        }
        if (_commentReplies.length > 500) _commentReplies.clear();
        _commentReplies[key] = reply;
      }
    }
    return map.comment(m, await _sender(m), replyTo: reply);
  }

  final _commentReplies = <String, CommentReply>{};

  @override
  Stream<CommentsGone> get commentsGone => _goneCtl.stream;

  @override
  Future<void> editComment(Thread thread, int messageId, String text) =>
      _client.call(
        td.EditMessageText(
          chatId: thread.chatId,
          messageId: messageId,
          inputMessageContent: td.InputMessageText(
            text: td.FormattedText(text: text, entities: const []),
            clearDraft: false,
          ),
        ),
      );

  @override
  Future<void> deleteComments(Thread thread, List<int> messageIds) =>
      _client.call(
        td.DeleteMessages(
          chatId: thread.chatId,
          messageIds: messageIds,
          revoke: true,
        ),
      );

  @override
  Future<void> retryComment(Thread thread, int messageId) => _client.call(
    td.ResendMessages(
      chatId: thread.chatId,
      messageIds: [messageId],
      paidMessageStarCount: 0,
    ),
  );

  /// Whether the account may comment in the discussion group [chatId], and how long its
  /// slow mode still makes it wait.
  Future<(ThreadWrite, int, int)> _threadWrite(int chatId) async {
    try {
      final chat = await _client.call(td.GetChat(chatId: chatId));
      final type = chat.type;
      if (type is! td.ChatTypeSupergroup) return (ThreadWrite.allowed, 0, 0);
      final group = await _client.call(
        td.GetSupergroup(supergroupId: type.supergroupId),
      );
      final status = group.status;
      final write = switch (status) {
        td.ChatMemberStatusBanned() => ThreadWrite.restricted,
        td.ChatMemberStatusRestricted(:final permissions) =>
          (permissions?.canSendBasicMessages ?? false)
              ? ThreadWrite.allowed
              : ThreadWrite.restricted,
        td.ChatMemberStatusLeft() =>
          group.joinToSendMessages
              ? ThreadWrite.joinNeeded
              : (chat.permissions?.canSendBasicMessages ?? true)
              ? ThreadWrite.allowed
              : ThreadWrite.restricted,
        td.ChatMemberStatusCreator() ||
        td.ChatMemberStatusAdministrator() => ThreadWrite.allowed,
        _ =>
          (chat.permissions?.canSendBasicMessages ?? true)
              ? ThreadWrite.allowed
              : ThreadWrite.restricted,
      };
      var wait = 0;
      var delay = 0;
      // Slow mode is for members; the group's admins write as they like.
      final exempt =
          status is td.ChatMemberStatusCreator ||
          status is td.ChatMemberStatusAdministrator;
      if (write == ThreadWrite.allowed && group.isSlowModeEnabled && !exempt) {
        final full = await _client.call(
          td.GetSupergroupFullInfo(supergroupId: type.supergroupId),
        );
        wait = full.slowModeDelayExpiresIn.ceil();
        delay = full.slowModeDelay;
      }
      return (write, wait, delay);
    } on TelegramException {
      // Unknown: the field is there, and Telegram says no when it has to.
      return (ThreadWrite.allowed, 0, 0);
    }
  }

  @override
  Future<void> reply(Thread thread, String text, {int replyToId = 0}) =>
      _client.call(
        td.SendMessage(
          chatId: thread.chatId,
          replyTo: td.InputMessageReplyToMessage(
            messageId: replyToId != 0 ? replyToId : thread.threadId,
            checklistTaskId: 0,
            pollOptionId: '',
          ),
          inputMessageContent: td.InputMessageText(
            text: td.FormattedText(text: text, entities: const []),
            clearDraft: true,
          ),
        ),
      );

  @override
  Stream<Comment> get comments => _commentCtl.stream;

  @override
  Future<void> closeThread(Thread thread) async {
    _openThreads.remove((thread.chatId, thread.threadId));
  }

  @override
  Future<void> saveToSavedMessages(int chatId, List<int> messageIds) async {
    // Saved Messages is the chat with oneself; createPrivateChat makes sure TDLib knows it.
    final me = _myId ??= (await _client.call(const td.GetMe())).id;
    final saved = await _client.call(
      td.CreatePrivateChat(userId: me, force: false),
    );
    await _client.call(
      td.ForwardMessages(
        chatId: saved.id,
        fromChatId: chatId,
        // TDLib forwards in strictly increasing order only.
        messageIds: [...messageIds]..sort(),
        sendCopy: false,
        removeCaption: false,
      ),
    );
  }

  @override
  Future<void> deleteFromSavedMessages(List<int> messageIds) async {
    final me = _myId ??= (await _client.call(const td.GetMe())).id;
    final saved = await _client.call(
      td.CreatePrivateChat(userId: me, force: false),
    );
    await _client.call(
      td.DeleteMessages(
        chatId: saved.id,
        messageIds: messageIds,
        revoke: false,
      ),
    );
  }

  @override
  Stream<ConnectionStatus> get connection async* {
    yield _connection;
    yield* _connectionCtl.stream;
  }

  @override
  Future<List<Channel>> similarChannels(int chatId) async {
    try {
      final chats = await _client.call(td.GetChatSimilarChats(chatId: chatId));
      final out = <Channel>[];
      for (final id in chats.chatIds) {
        final channel = await _channelOf(id);
        if (channel != null) out.add(channel);
      }
      return out;
    } on TelegramException catch (e) {
      // Telegram answers with an error for channels it has no suggestions for.
      log?.call('getChatSimilarChats($chatId): $e');
      return const [];
    }
  }

  @override
  Future<List<Channel>> archivedChannels() async {
    final out = <Channel>[];
    for (final id in await _chatIdsOf(const td.ChatListArchive())) {
      final channel = await _channelOf(id);
      if (channel != null) out.add(channel);
    }
    log?.call('archivedChannels: ${out.length} channels');
    return out;
  }

  @override
  Future<Channel> savedMessages() async {
    final me = _myId ??= (await _client.call(const td.GetMe())).id;
    final chat = await _client.call(
      td.CreatePrivateChat(userId: me, force: false),
    );
    return Channel(
      chatId: chat.id,
      title: 'Saved Messages',
      photo: chat.photo?.small == null ? null : map.fileRef(chat.photo!.small!),
      lastMessageId: chat.lastMessage?.id ?? 0,
      lastReadMessageId: chat.lastReadInboxMessageId,
      unreadCount: chat.unreadCount,
      lastMessageText: map.preview(chat.lastMessage?.content),
      lastMessageMedia: map.previewMedia(chat.lastMessage?.content),
      lastMessageDate: chat.lastMessage?.date ?? 0,
    );
  }

  @override
  Future<CommentPage> searchThread(
    Thread thread, {
    required String query,
    int fromMessageId = 0,
    int limit = 30,
  }) async {
    final r = await _client.call(
      td.SearchChatMessages(
        chatId: thread.chatId,
        topicId: td.MessageTopicThread(messageThreadId: thread.threadId),
        query: query,
        fromMessageId: fromMessageId,
        offset: 0,
        limit: limit,
      ),
    );
    final out = <Comment>[];
    for (final m in r.messages) {
      if (m.id == thread.threadId) continue; // the forwarded post itself
      out.add(await _comment(m));
    }
    return CommentPage(
      comments: out,
      totalCount: r.totalCount,
      nextFromMessageId: r.nextFromMessageId,
    );
  }

  @override
  Future<List<Comment>> threadAround(
    Thread thread,
    int messageId, {
    int newer = 15,
    int older = 15,
  }) async {
    // TDLib takes an offset of -99 at most, and a limit that reaches past it.
    final ahead = newer.clamp(0, 99);
    final r = await _client.call(
      td.GetMessageThreadHistory(
        chatId: thread.postChatId,
        messageId: thread.postMessageId,
        fromMessageId: messageId,
        offset: -ahead,
        limit: (ahead + older + 1).clamp(1, 100),
      ),
    );
    final out = <Comment>[];
    for (final m in r.messages) {
      if (m.id == thread.threadId) continue; // the forwarded post itself
      out.add(await _comment(m));
    }
    return out;
  }

  @override
  Future<GlobalSearchPage> searchAllChannels({
    required String query,
    HistoryFilter filter = HistoryFilter.any,
    String offset = '',
    int limit = 30,
    int minDate = 0,
    int maxDate = 0,
  }) async {
    final r = await _client.call(
      td.SearchMessages(
        // No chat list: the main list and the archive are both searched.
        chatList: null,
        query: query,
        offset: offset,
        limit: limit,
        filter: map.searchFilter(filter),
        chatTypeFilter: const td.SearchMessagesChatTypeFilterChannel(),
        minDate: minDate,
        maxDate: maxDate,
      ),
    );
    // Channels the account left, or chats that are not channels at all, are not ours.
    final keep = [
      for (final m in r.messages)
        if (_isChannelChat(m.chatId)) m,
    ];
    return GlobalSearchPage(
      posts: await _posts(keep),
      totalCount: r.totalCount,
      nextOffset: r.nextOffset,
    );
  }

  @override
  Future<ReportStep> report(
    int chatId,
    List<int> messageIds, {
    String optionId = '',
    String text = '',
  }) async {
    final answer = await _client.call(
      td.ReportChat(
        chatId: chatId,
        optionId: optionId,
        messageIds: messageIds,
        text: text,
      ),
    );
    return switch (answer) {
      td.ReportChatResultOptionRequired(:final title, :final options) =>
        ReportChoice(
          title: title,
          options: [
            for (final o in options) ReportOption(id: o.id, text: o.text),
          ],
        ),
      td.ReportChatResultTextRequired(:final optionId, :final isOptional) =>
        ReportText(optionId: optionId, optional: isOptional),
      // The posts were named with the first call; nothing else is left to ask.
      _ => const ReportDone(),
    };
  }

  @override
  Future<FileRef> mapThumbnail(
    double latitude,
    double longitude, {
    int width = 600,
    int height = 300,
  }) async {
    // Telegram's limits: 16 to 1024 a side, at one to three times the density.
    final w = width.clamp(16, 1024);
    final h = height.clamp(16, 1024);
    final file = await _client.call(
      td.GetMapThumbnailFile(
        location: td.Location(
          latitude: latitude,
          longitude: longitude,
          horizontalAccuracy: 0,
        ),
        zoom: 15,
        width: w,
        height: h,
        scale: 2,
        chatId: 0,
      ),
    );
    return map.fileRef(file, width: w * 2, height: h * 2);
  }

  @override
  Future<List<Post>> mediaCalendar(int chatId, {int fromMessageId = 0}) async {
    final r = await _client.call(
      td.GetChatMessageCalendar(
        chatId: chatId,
        filter: const td.SearchMessagesFilterPhotoAndVideo(),
        fromMessageId: fromMessageId,
      ),
    );
    return _posts([
      for (final day in r.days)
        if (day.message != null) day.message!,
    ]);
  }

  @override
  Future<List<Post>> pinnedPosts(int chatId) async {
    // searchChatMessages answers newest first, in pages of its own size.
    final out = <Post>[];
    var next = 0;
    try {
      while (out.length < _maxPinned) {
        final r = await _client.call(
          td.SearchChatMessages(
            chatId: chatId,
            query: '',
            fromMessageId: next,
            offset: 0,
            limit: 100,
            filter: const td.SearchMessagesFilterPinned(),
          ),
        );
        out.addAll(await _posts(r.messages));
        next = r.nextFromMessageId;
        if (next == 0 || r.messages.isEmpty) break;
      }
    } on TelegramException catch (e) {
      // The bar is an extra: a timeline without it is still a timeline.
      log?.call('searchChatMessages($chatId, pinned): $e');
    }
    return out;
  }

  /// More pinned posts than this are not asked for.
  static const _maxPinned = 500;

  @override
  Future<Map<String, StickerMedia>> customEmoji(List<String> ids) async {
    final wanted = [
      for (final id in ids)
        if (!_customEmoji.containsKey(id)) id,
    ];
    if (wanted.isNotEmpty) {
      try {
        final answer = await _client.call(
          td.GetCustomEmojiStickers(
            customEmojiIds: [for (final id in wanted) int.tryParse(id) ?? 0],
          ),
        );
        for (final s in answer.stickers) {
          final sticker = map.sticker(s);
          final id = switch (s.fullType) {
            td.StickerFullTypeCustomEmoji(:final customEmojiId) =>
              '$customEmojiId',
            _ => null,
          };
          if (sticker != null && id != null) _customEmoji[id] = sticker;
        }
      } on TelegramException catch (e) {
        log?.call('getCustomEmojiStickers failed: $e');
      }
    }
    return {for (final id in ids) id: ?_customEmoji[id]};
  }

  @override
  Future<List<String>> availableReactions(int chatId, int messageId) async =>
      map.availableEmoji(
        await _client.call(
          td.GetMessageAvailableReactions(
            chatId: chatId,
            messageId: messageId,
            rowSize: 8,
          ),
        ),
      );

  @override
  Future<void> react(
    int chatId,
    int messageId,
    String emoji, {
    bool remove = false,
  }) async {
    final type = map.reactionType(emoji);
    // The paid reaction costs Stars, which the app does not spend.
    if (type == null) return;
    await (remove
        ? _client.call(
            td.RemoveMessageReaction(
              chatId: chatId,
              messageId: messageId,
              reactionType: type,
            ),
          )
        : _client.call(
            td.AddMessageReaction(
              chatId: chatId,
              messageId: messageId,
              reactionType: type,
              isBig: false,
              updateRecentReactions: true,
            ),
          ));
  }

  @override
  Future<UserInfo> me() async {
    final u = await _client.call(const td.GetMe());
    var bio = '';
    try {
      final full = await _client.call(td.GetUserFullInfo(userId: u.id));
      bio = full.bio?.text ?? '';
    } on TelegramException catch (e) {
      log?.call(
        'getUserFullInfo failed: $e',
      ); // the basic profile is still worth showing
    }
    return map.user(u, bio: bio);
  }

  @override
  Future<StorageStats> storageStats() async =>
      map.storageStats(await _client.call(const td.GetStorageStatisticsFast()));

  @override
  Future<StorageStats> clearCache() async {
    await _client.call(
      const td.OptimizeStorage(
        // Everything goes, whatever its age: TDLib's default limits (-1) keep what was
        // used in the last weeks and remove next to nothing.
        size: 0,
        ttl: 0,
        count: 0,
        immunityDelay: 0,
        // Every kind the statistics count. Left empty, thumbnails, profile photos,
        // stickers and wallpapers would stay, and the cache would not shrink to what
        // the screen promised.
        fileTypes: [
          td.FileTypeAnimation(),
          td.FileTypeAudio(),
          td.FileTypeDocument(),
          td.FileTypeLivePhotoVideo(),
          td.FileTypeNotificationSound(),
          td.FileTypePhoto(),
          td.FileTypePhotoStory(),
          td.FileTypeProfilePhoto(),
          td.FileTypeSticker(),
          td.FileTypeThumbnail(),
          td.FileTypeUnknown(),
          td.FileTypeVideo(),
          td.FileTypeVideoNote(),
          td.FileTypeVideoStory(),
          td.FileTypeVoiceNote(),
          td.FileTypeWallpaper(),
        ],
        chatIds: [],
        excludeChatIds: [],
        returnDeletedFileStatistics: false,
        chatLimit: 0,
      ),
    );
    return storageStats();
  }

  @override
  Stream<FileProgress> fileProgress(int fileId) =>
      _fileCtl.stream.where((p) => p.fileId == fileId);

  FileProgress _progress(td.File f) => FileProgress(
    fileId: f.id,
    downloaded: f.local?.downloadedSize ?? 0,
    total: f.size > 0 ? f.size : f.expectedSize,
    localPath: (f.local?.isDownloadingCompleted ?? false)
        ? f.local!.path
        : null,
    partialPath: f.local?.path ?? '',
  );

  /// Closes TDLib's client and waits until TDLib says it is closed, so the database lock
  /// is free for the next client in this process (core handover, ARCHITECTURE 8). Falls
  /// back to a plain [close] when TDLib stays silent.
  Future<void> closeAndWait({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final closed = authState
        .firstWhere((s) => s is AuthClosed)
        .then<void>((_) {})
        .timeout(
          timeout,
          onTimeout: () => log?.call('close: TDLib did not answer in time'),
        );
    try {
      await _client.call(const td.Close());
    } on TelegramException catch (e) {
      log?.call('close: $e');
    }
    await closed;
    await close();
  }

  @override
  Future<void> close() async {
    await _sub.cancel();
    await _client.close();
    await _authCtl.close();
    await _postCtl.close();
    await _memberCtl.close();
    await _fileCtl.close();
    await _commentCtl.close();
    await _goneCtl.close();
    await _connectionCtl.close();
    await _readCtl.close();
  }
}
