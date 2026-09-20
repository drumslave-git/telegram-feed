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

  /// Joined channels (supergroups with `is_channel`) of the main chat list and of every
  /// chat folder, newest chat first, each channel once. Folders are read too because a
  /// channel joined through a folder invite link is in its folder's list only; the archive
  /// is not read.
  Future<List<Channel>> myChannels();
  Stream<ChannelMembershipEvent> get membershipEvents;

  /// The account's chat folders with the joined channels in each; folders without channels
  /// are left out.
  Future<List<ChatFolder>> chatFolders();

  /// Posts older than [fromMessageId] (0 = newest), newest first. With [onlyLocal] TDLib answers
  /// from its database only and may return fewer posts than exist.
  Future<List<Post>> history(
    int chatId, {
    int fromMessageId = 0,
    int limit = 30,
    bool onlyLocal = false,
  });

  /// Posts of [chatId] newer than [afterMessageId], newest first. This is how a timeline
  /// that was opened at an older post (a search result, a date) pages back towards the
  /// newest one.
  Future<List<Post>> historyAfter(
    int chatId, {
    required int afterMessageId,
    int limit = 30,
  });

  /// Posts of [chatId] matching [query] and [filter], newest first. An empty [query] with
  /// a filter is how the shared media tabs list a channel's photos, files, links and audio.
  Future<SearchPage> searchHistory(
    int chatId, {
    String query = '',
    HistoryFilter filter = HistoryFilter.any,
    int fromMessageId = 0,
    int limit = 30,
  });

  /// Newest post of [chatId] sent no later than [unixDate]; 0 when the channel has none.
  Future<int> messageIdByDate(int chatId, int unixDate);

  /// Description, subscriber count and link of a channel, for its info screen.
  Future<ChannelInfo> channelInfo(int chatId);

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

  /// The stickers behind custom (premium) emoji ids, for the text that carries them. Ids
  /// TDLib does not know are simply missing from the answer.
  Future<Map<String, StickerMedia>> customEmoji(List<String> ids);

  /// Emoji this account may react with on the post (phase 3).
  Future<List<String>> availableReactions(int chatId, int messageId);

  /// Adds (or with [remove], removes) an emoji reaction.
  Future<void> react(
    int chatId,
    int messageId,
    String emoji, {
    bool remove = false,
  });

  /// Forwards the post (a whole album at once) into the account's Saved Messages, as the
  /// official app's "Save to Saved Messages" does: with the channel as its source.
  Future<void> saveToSavedMessages(int chatId, List<int> messageIds);

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
