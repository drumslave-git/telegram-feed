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
  List<td.ChatFolderInfo> _folders = const [];
  final _supergroups = <int, td.Supergroup>{};
  final _channelChatIds = <int>{};

  /// (discussion chat id, thread id) of threads a screen has open.
  final _openThreads = <(int, int)>{};
  final _senders = <String, map.Sender>{};

  @override
  Stream<AuthState> get authState async* {
    yield _auth;
    yield* _authCtl.stream;
  }

  @override
  Stream<PostEvent> get postEvents => _postCtl.stream;
  @override
  Stream<ChannelMembershipEvent> get membershipEvents => _memberCtl.stream;

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
          _commentCtl.add(map.comment(message, await _sender(message)));
        } else if (_isChannelChat(message.chatId)) {
          _postCtl.add(PostAdded(map.post(message)));
        }
      case td.UpdateMessageContent(:final chatId, :final messageId):
        if (_isChannelChat(chatId)) await _emitEdited(chatId, messageId);
      case td.UpdateMessageEdited(:final chatId, :final messageId):
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
        if (isPermanent && !fromCache && _isChannelChat(chatId)) {
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
      case td.UpdateChatFolders(:final chatFolders):
        _folders = chatFolders;
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
      _postCtl.add(PostEdited(map.post(m)));
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
    const list = td.ChatListMain();
    await _loadAll(list);
    final ids = (await _client.call(
      const td.GetChats(chatList: list, limit: 1000),
    )).chatIds;
    final out = <Channel>[];
    for (final id in ids) {
      final chat = await _client.call(td.GetChat(chatId: id));
      if (chat.type
          case td.ChatTypeSupergroup(:final supergroupId, :final isChannel)
          when isChannel) {
        final sg =
            _supergroups[supergroupId] ??
            await _client.call(td.GetSupergroup(supergroupId: supergroupId));
        _supergroups[supergroupId] = sg;
        _channelChatIds.add(id);
        out.add(map.channel(chat, sg));
      }
    }
    return out;
  }

  @override
  Future<List<ChatFolder>> chatFolders() async {
    final out = <ChatFolder>[];
    for (final info in _folders) {
      final list = td.ChatListFolder(chatFolderId: info.id);
      await _loadAll(list);
      final ids = (await _client.call(td.GetChats(chatList: list, limit: 1000)))
          .chatIds;
      final channels = <int>[];
      for (final id in ids) {
        if (!_channelChatIds.contains(id)) {
          final chat = await _client.call(td.GetChat(chatId: id));
          if (chat.type case td.ChatTypeSupergroup(:final isChannel)
              when isChannel) {
            _channelChatIds.add(id);
          }
        }
        if (_channelChatIds.contains(id)) channels.add(id);
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
      out.addAll(older.map(map.post));
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
      out.addAll(newer.map(map.post));
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
      out.addAll(r.messages.map(map.post));
      next = r.nextFromMessageId;
      if (next == 0 || r.messages.isEmpty) {
        next = 0;
        break;
      }
    }
    return SearchPage(posts: out, totalCount: total, nextFromMessageId: next);
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
    return ChannelInfo(
      chatId: chatId,
      description: description,
      memberCount: memberCount,
      inviteLink: inviteLink,
      bigPhoto: big == null ? null : map.fileRef(big),
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
  }) async => _progress(
    await _client.call(
      td.DownloadFile(
        fileId: fileId,
        priority: priority,
        offset: offset,
        limit: 0,
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
      final t = Thread(
        chatId: info.chatId,
        threadId: info.messageThreadId,
        postChatId: chatId,
        postMessageId: messageId,
        replyCount: info.replyInfo?.replyCount ?? 0,
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
      out.add(map.comment(m, await _sender(m)));
    }
    return out;
  }

  @override
  Future<void> reply(Thread thread, String text) => _client.call(
    td.SendMessage(
      chatId: thread.chatId,
      replyTo: td.InputMessageReplyToMessage(
        messageId: thread.threadId,
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
  }) => remove
      ? _client.call(
          td.RemoveMessageReaction(
            chatId: chatId,
            messageId: messageId,
            reactionType: td.ReactionTypeEmoji(emoji: emoji),
          ),
        )
      : _client.call(
          td.AddMessageReaction(
            chatId: chatId,
            messageId: messageId,
            reactionType: td.ReactionTypeEmoji(emoji: emoji),
            isBig: false,
            updateRecentReactions: true,
          ),
        );

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
        size: -1,
        ttl: -1,
        count: -1,
        immunityDelay: -1,
        fileTypes: [],
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

  @override
  Future<void> close() async {
    await _sub.cancel();
    await _client.close();
    await _authCtl.close();
    await _postCtl.close();
    await _memberCtl.close();
    await _fileCtl.close();
    await _commentCtl.close();
  }
}
