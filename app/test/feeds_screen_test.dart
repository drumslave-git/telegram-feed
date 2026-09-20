/// The gateway fake shared by the widget tests.
library;

import 'dart:async';

import 'package:telegram_gateway/telegram_gateway.dart';

class ChannelsGateway implements TelegramGateway {
  ChannelsGateway(this.channels, {this.folders = const []});
  final List<Channel> channels;
  final List<ChatFolder> folders;

  @override
  Future<List<ChatFolder>> chatFolders() async => folders;
  final posts = StreamController<PostEvent>.broadcast();

  @override
  Future<List<Channel>> myChannels() async => channels;
  @override
  Stream<PostEvent> get postEvents => posts.stream;

  @override
  Stream<AuthState> get authState => Stream.value(const AuthReady());
  @override
  Stream<ChannelMembershipEvent> get membershipEvents => const Stream.empty();
  @override
  Stream<FileProgress> fileProgress(int fileId) => const Stream.empty();
  @override
  Future<void> setPhoneNumber(String phone) async {}
  @override
  Future<void> checkCode(String code) async {}
  @override
  Future<void> checkPassword(String password) async {}
  @override
  Future<void> registerUser({
    required String firstName,
    String lastName = '',
  }) async {}
  @override
  Future<void> requestQrCode() async {}
  @override
  Future<void> logOut() async {}
  @override
  Future<List<Post>> history(
    int chatId, {
    int fromMessageId = 0,
    int limit = 30,
    bool onlyLocal = false,
  }) async => const [];
  @override
  Future<List<Post>> historyAfter(
    int chatId, {
    required int afterMessageId,
    int limit = 30,
  }) async => const [];
  @override
  Future<SearchPage> searchHistory(
    int chatId, {
    String query = '',
    HistoryFilter filter = HistoryFilter.any,
    int fromMessageId = 0,
    int limit = 30,
  }) async => const SearchPage();
  @override
  Future<int> messageIdByDate(int chatId, int unixDate) async => 0;
  @override
  Future<ChannelInfo> channelInfo(int chatId) async =>
      ChannelInfo(chatId: chatId);

  /// What the app told Telegram to count as read, per chat.
  final markedViewed = <int, List<int>>{};

  @override
  Future<void> markViewed(int chatId, List<int> messageIds) async =>
      markedViewed[chatId] = messageIds;
  @override
  Future<void> saveToSavedMessages(int chatId, List<int> messageIds) async =>
      saved.add('$chatId:${messageIds.join(",")}');

  /// Records hold lists badly (a record with a list is never equal to another), so the
  /// saved posts are kept as text.
  final saved = <String>[];
  @override
  Future<FileRef> download(FileRef ref, {int priority = 16}) async => ref;
  @override
  Future<FileProgress> downloadFrom(
    int fileId, {
    int offset = 0,
    int priority = 32,
  }) async => FileProgress(fileId: fileId, downloaded: 0, total: 0);
  @override
  Future<int> downloadedPrefix(int fileId, int offset) async => 0;
  @override
  Future<void> cancelDownload(int fileId) async {}
  @override
  Future<void> close() async {}

  @override
  Future<Thread?> discussion(int chatId, int messageId) async => null;
  @override
  Future<List<Comment>> threadHistory(
    Thread thread, {
    int fromMessageId = 0,
    int limit = 30,
  }) async => const [];
  @override
  Future<void> reply(Thread thread, String text) async {}
  @override
  Stream<Comment> get comments => const Stream.empty();
  @override
  Future<void> closeThread(Thread thread) async {}

  @override
  Future<Post?> pinnedPost(int chatId) async => null;
  @override
  Future<Map<String, StickerMedia>> customEmoji(List<String> ids) async =>
      const {};
  @override
  Future<List<String>> availableReactions(int chatId, int messageId) async =>
      const ['👍', '🔥'];
  @override
  Future<void> react(
    int chatId,
    int messageId,
    String emoji, {
    bool remove = false,
  }) async {}
  @override
  Future<UserInfo> me() async =>
      const UserInfo(id: 1, firstName: 'Test', phoneNumber: '+1');
  @override
  Future<StorageStats> storageStats() async =>
      const StorageStats(filesBytes: 0, fileCount: 0, databaseBytes: 0);
  @override
  Future<StorageStats> clearCache() => storageStats();
}

void main() {}
