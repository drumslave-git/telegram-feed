import 'models.dart';

/// The only thing in the app that knows about Telegram. See ARCHITECTURE.md section 4.
abstract interface class TelegramGateway {
  /// Current state first (replayed to late subscribers), then every change.
  Stream<AuthState> get authState;
  Future<void> setPhoneNumber(String phone);
  Future<void> checkCode(String code);
  Future<void> checkPassword(String password);
  Future<void> registerUser({required String firstName, String lastName = ''});
  Future<void> requestQrCode();
  Future<void> logOut();

  /// Joined channels (supergroups with `is_channel`), newest chat first.
  Future<List<Channel>> myChannels();
  Stream<ChannelMembershipEvent> get membershipEvents;

  /// Posts older than [fromMessageId] (0 = newest), newest first. With [onlyLocal] TDLib answers
  /// from its database only and may return fewer posts than exist.
  Future<List<Post>> history(
    int chatId, {
    int fromMessageId = 0,
    int limit = 30,
    bool onlyLocal = false,
  });
  Stream<PostEvent> get postEvents;
  Future<void> markViewed(int chatId, List<int> messageIds);

  /// Starts (or joins) a download and completes with the local path.
  Future<FileRef> download(FileRef ref, {int priority = 16});
  Stream<FileProgress> fileProgress(int fileId);

  /// Playing while downloading: aims the download of [fileId] at [offset] (the bytes the
  /// player needs next come first) and answers with the file's state right away.
  Future<FileProgress> downloadFrom(
    int fileId, {
    int offset = 0,
    int priority = 32,
  });

  /// Bytes readable from [offset] on in [FileProgress.partialPath].
  Future<int> downloadedPrefix(int fileId, int offset);

  /// Stops a download nobody waits for any more; what is on disk stays.
  Future<void> cancelDownload(int fileId);

  /// Emoji this account may react with on the post (phase 3).
  Future<List<String>> availableReactions(int chatId, int messageId);

  /// Adds (or with [remove], removes) an emoji reaction.
  Future<void> react(
    int chatId,
    int messageId,
    String emoji, {
    bool remove = false,
  });

  /// The post's discussion thread, or null when the channel has no discussion group.
  /// Opening a thread makes its new comments arrive on [comments] until [closeThread].
  Future<Thread?> discussion(int chatId, int messageId);

  /// Comments older than [fromMessageId] (0 = newest), newest first.
  Future<List<Comment>> threadHistory(
    Thread thread, {
    int fromMessageId = 0,
    int limit = 30,
  });

  Future<void> reply(Thread thread, String text);

  /// Live comments for open threads.
  Stream<Comment> get comments;

  Future<void> closeThread(Thread thread);

  /// The logged-in account (only valid in [AuthReady]).
  Future<UserInfo> me();

  /// Size of TDLib's file cache and database.
  Future<StorageStats> storageStats();

  /// Deletes cached files not currently in use; returns the stats afterwards.
  Future<StorageStats> clearCache();

  Future<void> close();
}
