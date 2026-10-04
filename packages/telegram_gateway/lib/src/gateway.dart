import 'models.dart';

/// The only thing in the app that knows about Telegram. See ARCHITECTURE.md section 4.
abstract interface class TelegramGateway {
  /// Current state first (replayed to late subscribers), then every change.
  Stream<AuthState> get authState;
  Future<void> setPhoneNumber(String phone);
  Future<void> checkCode(String code);

  /// Asks Telegram for the login code again, as the official app's "Resend code" does.
  Future<void> resendCode();

  /// The email address Telegram asks some accounts for; login codes then go there.
  Future<void> setEmailAddress(String email);

  /// The login code Telegram sent to the account's email address.
  Future<void> checkEmailCode(String code);
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

  /// Marks the posts viewed and everything of the channel up to the newest of them read, in
  /// Telegram and so in the official app.
  Future<void> markViewed(int chatId, List<int> messageIds);

  /// Tells Telegram that these posts were on the screen, for their view counters, without
  /// moving the read position: posts read long ago, and posts not read yet.
  Future<void> countViews(int chatId, List<int> messageIds);

  /// Telegram's read state of the chat now.
  Future<ReadState> readState(int chatId);

  /// Every change of a channel's read state: read here, in the official app or on another
  /// device, and every new unread post.
  Stream<ReadState> get readUpdates;

  /// Starts (or joins) a download and completes with the local path.
  Future<FileRef> download(FileRef ref, {int priority = 16});
  Stream<FileProgress> fileProgress(int fileId);

  /// Playing while downloading: aims the download of [fileId] at [offset] (the bytes the
  /// player needs next come first) and answers with the file's state right away. A
  /// [limit] stops it after that many bytes (0 = the whole rest): the first seconds of a
  /// video loaded ahead.
  Future<FileProgress> downloadFrom(
    int fileId, {
    int offset = 0,
    int priority = 32,
    int limit = 0,
  });

  /// Bytes readable from [offset] on in [FileProgress.partialPath].
  Future<int> downloadedPrefix(int fileId, int offset);

  /// Stops a download nobody waits for any more; what is on disk stays.
  Future<void> cancelDownload(int fileId);

  /// Channels Telegram suggests as similar to this one. The app never joins them, so they
  /// are there to look at and to open in the official app.
  Future<List<Channel>> similarChannels(int chatId);

  /// Channels the account archived in Telegram. They stay out of the ordinary lists
  /// (founder decision, round 6) and have a place of their own (H-30).
  Future<List<Channel>> archivedChannels();

  /// The chat with oneself, as a channel the timeline can read: what the post menu saves
  /// into (SPEC 3, "Save to Saved Messages").
  Future<Channel> savedMessages();

  /// Searches the comments of one thread, newest first. [fromMessageId] pages older ones.
  Future<CommentPage> searchThread(
    Thread thread, {
    required String query,
    int fromMessageId = 0,
    int limit = 30,
  });

  /// Searches the posts of every channel the account follows at once (TDLib's own search
  /// over all chats, filtered down to channels). [offset] comes from the previous page.
  /// [minDate] and [maxDate] (unix seconds, 0 for none) keep the posts of a span of time.
  /// TDLib answers nothing when there are neither words nor a kind of post.
  Future<GlobalSearchPage> searchAllChannels({
    required String query,
    HistoryFilter filter = HistoryFilter.any,
    String offset = '',
    int limit = 30,
    int minDate = 0,
    int maxDate = 0,
  });

  /// TDLib's connection, so a screen can say "Connecting..." instead of looking empty.
  /// The first value is what it is now.
  Stream<ConnectionStatus> get connection;

  /// The picture of the map around a place, [width] by [height] logical pixels, as
  /// Telegram draws it for a location: a file to download like any other.
  Future<FileRef> mapThumbnail(
    double latitude,
    double longitude, {
    int width = 600,
    int height = 300,
  });

  /// One post with a photo or a video for every day that has any, newest day first, from
  /// the post [fromMessageId] back (0: from the newest). The days are those of the phone's
  /// clock. Telegram answers in pages; an empty answer is the end. The official app draws
  /// its calendar from this.
  Future<List<Post>> mediaCalendar(int chatId, {int fromMessageId = 0});

  /// The posts pinned in a channel, newest first; empty when it has none. The official app
  /// shows them in a bar over the timeline.
  Future<List<Post>> pinnedPosts(int chatId);

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

  /// Comments of the open threads that are no more: deleted ones, and the temporary ids
  /// of own comments once Telegram has given them their own.
  Stream<CommentsGone> get commentsGone;

  /// Changes the words of an own comment.
  Future<void> editComment(Thread thread, int messageId, String text);

  /// Deletes comments for everyone; also takes back one that could not be sent.
  Future<void> deleteComments(Thread thread, List<int> messageIds);

  /// Sends a comment again that could not be sent.
  Future<void> retryComment(Thread thread, int messageId);

  /// Marks a channel as unread in Telegram, as the official app's "Mark as unread" does,
  /// or takes the mark off. The mark is a flag of its own: no post becomes unread.
  Future<void> markChannelUnread(int chatId, {required bool unread});

  /// Tells Telegram that the comments [messageIds] of [thread] were on the screen, which
  /// moves the thread's read position as the official app does.
  Future<void> markCommentsViewed(Thread thread, List<int> messageIds);

  /// Reports posts of a channel to Telegram's moderators, one step at a time as Telegram
  /// asks: the first call brings the reasons to choose from, the next ones carry the
  /// chosen [optionId] (and the [text] it asked for) until the answer is [ReportDone].
  Future<ReportStep> report(
    int chatId,
    List<int> messageIds, {
    String optionId = '',
    String text = '',
  });

  /// Deletes posts from the account's Saved Messages, as the official app's Delete does
  /// there, on every device of the account. It is the only deletion the app makes:
  /// channels are read, not managed.
  Future<void> deleteFromSavedMessages(List<int> messageIds);

  /// The post's discussion thread, or null when the channel has no discussion group.
  /// Opening a thread makes its new comments arrive on [comments] until [closeThread].
  Future<Thread?> discussion(int chatId, int messageId);

  /// Comments older than [fromMessageId] (0 = newest), newest first.
  Future<List<Comment>> threadHistory(
    Thread thread, {
    int fromMessageId = 0,
    int limit = 30,
  });

  /// The comments around [messageId], newest first: up to [newer] that came after it, the
  /// comment itself and up to [older] before it. This is how the thread lands on a comment
  /// that is far from what it has loaded, and how it pages towards the newest from there.
  Future<List<Comment>> threadAround(
    Thread thread,
    int messageId, {
    int newer = 15,
    int older = 15,
  });

  Future<void> reply(Thread thread, String text, {int replyToId = 0});

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
