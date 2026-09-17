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

/// [TelegramGateway] on top of any TDLib JSON transport. `TdlibFfiGateway` and the future
/// `TdwebGateway` differ only in the [TdTransport] they are given.
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
  final _supergroups = <int, td.Supergroup>{};
  final _channelChatIds = <int>{};

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
        if (message != null && _isChannelChat(message.chatId)) {
          _postCtl.add(PostAdded(map.post(message)));
        }
      case td.UpdateMessageContent(:final chatId, :final messageId):
        if (_isChannelChat(chatId)) await _emitEdited(chatId, messageId);
      case td.UpdateMessageEdited(:final chatId, :final messageId):
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
    // loadChats returns 404 once everything is loaded.
    for (var i = 0; i < 20; i++) {
      try {
        await _client.call(const td.LoadChats(chatList: list, limit: 100));
      } on TelegramException catch (e) {
        if (e.code == 404) break;
        rethrow;
      }
    }
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
  Future<List<Post>> history(
    int chatId, {
    int fromMessageId = 0,
    int limit = 30,
    bool onlyLocal = false,
  }) async {
    final r = await _client.call(
      td.GetChatHistory(
        chatId: chatId,
        fromMessageId: fromMessageId,
        offset: 0,
        limit: limit,
        onlyLocal: onlyLocal,
      ),
    );
    return [for (final m in r.messages) map.post(m)];
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
    );
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
  Stream<FileProgress> fileProgress(int fileId) =>
      _fileCtl.stream.where((p) => p.fileId == fileId);

  FileProgress _progress(td.File f) => FileProgress(
    fileId: f.id,
    downloaded: f.local?.downloadedSize ?? 0,
    total: f.size > 0 ? f.size : f.expectedSize,
    localPath: (f.local?.isDownloadingCompleted ?? false)
        ? f.local!.path
        : null,
  );

  @override
  Future<void> close() async {
    await _sub.cancel();
    await _client.close();
    await _authCtl.close();
    await _postCtl.close();
    await _memberCtl.close();
    await _fileCtl.close();
  }
}
