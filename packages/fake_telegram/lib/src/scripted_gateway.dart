/// The scripted gateways every widget test reads from: channels, folders, histories that
/// page, live posts. No test needs a real Telegram account, real channels or real posts.
library;

import 'dart:async';

import 'package:telegram_gateway/telegram_gateway.dart';

/// The gateway with nothing in it: channels and folders only, every other call answered with
/// an empty result. Screens that never page history use this one.
class ChannelsGateway implements TelegramGateway {
  ChannelsGateway(this.channels, {this.folders = const []});
  final List<Channel> channels;
  final List<ChatFolder> folders;

  @override
  Future<List<ChatFolder>> chatFolders() async => folders;
  final posts = StreamController<PostEvent>.broadcast();

  /// The channels as TDLib hands them out now: with the read position, the unread count
  /// and the newest post of this moment.
  @override
  Future<List<Channel>> myChannels() async => [
    for (final c in channels)
      Channel(
        chatId: c.chatId,
        title: c.title,
        username: c.username,
        memberCount: c.memberCount,
        photo: c.photo,
        isMember: c.isMember,
        lastMessageId: lastMessageOf(c.chatId),
        lastReadMessageId: readPositions[c.chatId] ?? 0,
        unreadCount: unreadOf(c.chatId),
        lastMessageText: c.lastMessageText,
        lastMessageDate: c.lastMessageDate,
      ),
  ];
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
  Future<void> resendCode() async {}
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

  /// What the app told Telegram to count as read, per chat: the ids of the last call.
  final markedViewed = <int, List<int>>{};

  /// Telegram's read position per chat. It starts at the channels' `lastReadMessageId`, a
  /// test may set it, and [markViewed] moves it forward the way TDLib does, telling
  /// [readUpdates] about it.
  late final readPositions = <int, int>{
    for (final c in channels) c.chatId: c.lastReadMessageId,
  };
  final readCtl = StreamController<ReadState>.broadcast();

  @override
  Stream<ReadState> get readUpdates => readCtl.stream;

  /// Newest post of a chat, as the channel list names it.
  int lastMessageOf(int chatId) {
    for (final c in channels) {
      if (c.chatId == chatId) return c.lastMessageId;
    }
    return 0;
  }

  /// Unread posts after the read position, as the channel list counts them.
  int unreadOf(int chatId) {
    for (final c in channels) {
      if (c.chatId == chatId) return c.unreadCount;
    }
    return 0;
  }

  @override
  Future<ReadState> readState(int chatId) async => ReadState(
    chatId: chatId,
    lastReadMessageId: readPositions[chatId] ?? 0,
    unreadCount: unreadOf(chatId),
    lastMessageId: lastMessageOf(chatId),
  );

  @override
  Future<void> markViewed(int chatId, List<int> messageIds) async {
    markedViewed[chatId] = messageIds;
    final newest = messageIds.fold(0, (a, b) => a > b ? a : b);
    if (newest <= (readPositions[chatId] ?? 0)) return;
    readPositions[chatId] = newest;
    readCtl.add(await readState(chatId));
  }

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
    int limit = 0,
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

  /// Ready, unless a test says otherwise.
  final connectionStatus = StreamController<ConnectionStatus>.broadcast();

  @override
  Stream<ConnectionStatus> get connection async* {
    yield ConnectionStatus.ready;
    yield* connectionStatus.stream;
  }

  @override
  Future<List<Channel>> similarChannels(int chatId) async => const [];
  @override
  Future<List<Channel>> archivedChannels() async => const [];
  @override
  Future<Channel> savedMessages() async =>
      const Channel(chatId: 42, title: 'Saved Messages');
  @override
  Future<List<Comment>> searchThread(
    Thread thread, {
    required String query,
    int fromMessageId = 0,
    int limit = 30,
  }) async => const [];
  @override
  Future<GlobalSearchPage> searchAllChannels({
    required String query,
    HistoryFilter filter = HistoryFilter.any,
    String offset = '',
    int limit = 30,
  }) async => const GlobalSearchPage(posts: [], totalCount: 0, nextOffset: '');
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

/// The gateway with histories: it pages [histories] like TDLib does (older posts from a
/// bound, newer posts after one), searches them, and pushes live posts. Timelines use this
/// one.
class TimelineGateway extends ChannelsGateway {
  TimelineGateway(
    this.histories, {
    List<Channel> channels = const [],
    super.folders,
  }) : super(channels);
  final Map<int, List<Post>> histories;
  final reactions = <String>[];

  /// The post a channel timeline finds pinned, and the chats that asked for one.
  Post? pinned;
  final pinnedAsked = <int>[];

  /// Channels the account archived, for the Archive row of H-30.
  List<Channel> archived = const [];

  @override
  Future<List<Channel>> archivedChannels() async => archived;

  /// Queries the search over every channel was asked, with their offsets.
  final globalQueries = <String>[];

  @override
  Future<GlobalSearchPage> searchAllChannels({
    required String query,
    HistoryFilter filter = HistoryFilter.any,
    String offset = '',
    int limit = 30,
  }) async {
    globalQueries.add('$query|$filter|$offset');
    final all = [
      for (final posts in histories.values)
        for (final p in posts)
          if (p.text.toLowerCase().contains(query.toLowerCase())) p,
    ]..sort((a, b) => b.date.compareTo(a.date));
    // One page, then the end.
    return GlobalSearchPage(
      posts: offset.isEmpty ? all : const [],
      totalCount: all.length,
      nextOffset: '',
    );
  }

  @override
  Future<Post?> pinnedPost(int chatId) async {
    pinnedAsked.add(chatId);
    return pinned;
  }

  @override
  Future<void> react(
    int chatId,
    int messageId,
    String emoji, {
    bool remove = false,
  }) async => reactions.add('$chatId/$messageId ${remove ? '-' : '+'}$emoji');

  /// Every search of one channel: "query|filter".
  final searches = <String>[];

  @override
  Future<SearchPage> searchHistory(
    int chatId, {
    String query = '',
    HistoryFilter filter = HistoryFilter.any,
    int fromMessageId = 0,
    int limit = 30,
  }) async {
    searches.add('$query|$filter');
    final all = [
      for (final p in histories[chatId] ?? const <Post>[])
        if (query.isEmpty || p.text.toLowerCase().contains(query.toLowerCase()))
          p,
    ];
    final older = fromMessageId == 0
        ? all
        : all.where((p) => p.messageId < fromMessageId).toList();
    final page = older.take(limit).toList();
    return SearchPage(
      posts: page,
      totalCount: all.length,
      nextFromMessageId: page.length < older.length ? page.last.messageId : 0,
    );
  }

  @override
  Future<int> messageIdByDate(int chatId, int unixDate) async {
    for (final p in histories[chatId] ?? const <Post>[]) {
      if (p.date <= unixDate) return p.messageId;
    }
    return 0;
  }

  /// How often the posts after a mark were asked for: what counting unread posts costs.
  var historyAfterCalls = 0;

  @override
  Future<List<Post>> historyAfter(
    int chatId, {
    required int afterMessageId,
    int limit = 30,
  }) async {
    historyAfterCalls++;
    final newer = [
      for (final p in histories[chatId] ?? const <Post>[])
        if (p.messageId > afterMessageId) p,
    ];
    return newer.sublist(newer.length > limit ? newer.length - limit : 0);
  }

  /// How often a page of older posts was asked for.
  var historyCalls = 0;

  @override
  Future<List<Post>> history(
    int chatId, {
    int fromMessageId = 0,
    int limit = 30,
    bool onlyLocal = false,
  }) async {
    historyCalls++;
    final all = histories[chatId] ?? const <Post>[];
    return (fromMessageId == 0
            ? all
            : all.where((p) => p.messageId < fromMessageId))
        .take(limit)
        .toList();
  }

  @override
  int lastMessageOf(int chatId) {
    final history = histories[chatId];
    return history == null || history.isEmpty
        ? super.lastMessageOf(chatId)
        : history.first.messageId;
  }

  @override
  int unreadOf(int chatId) {
    final history = histories[chatId];
    if (history == null) return super.unreadOf(chatId);
    final read = readPositions[chatId] ?? 0;
    return history.where((p) => p.messageId > read).length;
  }

  /// A post that arrives now: it joins the channel's history, so paging and a later
  /// reopening of the feed find it, and it is pushed to the app as TDLib pushes it, with
  /// the channel's new unread count.
  void arrive(Post post) {
    (histories[post.chatId] ??= <Post>[]).insert(0, post);
    posts.add(PostAdded(post));
    unawaited(readState(post.chatId).then(readCtl.add));
  }

  /// A post that arrived while the app was not listening: the channel's history has it,
  /// but nothing was pushed, as when the process was down or the watcher detached.
  void arrivedUnseen(Post post) =>
      (histories[post.chatId] ??= <Post>[]).insert(0, post);
}

// ---- fixture data ----

/// A fixture post. The message id is also its place in the channel, and the date follows
/// from it unless a test wants its own, so a fixture feed reads the same in every test.
Post fixturePost(
  int chatId,
  int messageId, {
  int? date,
  String? text,
  int albumId = 0,
  Media? media,
}) => Post(
  chatId: chatId,
  messageId: messageId,
  date: date ?? messageId * 100,
  text: text ?? 'post-$messageId',
  albumId: albumId,
  media: media,
);

/// A channel's history as the gateway hands it out: newest first, ids [from] up to [to].
/// The text of each post is `post-<id>`, or `<label>-<id>` where a test mixes channels and
/// needs to tell them apart.
List<Post> fixtureHistory(
  int chatId, {
  int from = 1,
  required int to,
  String? label,
  int step = 100,
  int dateOffset = 0,
}) => [
  for (var id = to; id >= from; id--)
    fixturePost(
      chatId,
      id,
      date: id * step + dateOffset,
      text: label == null ? 'post-$id' : '$label-$id',
    ),
];

/// A channel the account is a member of, as [TelegramGateway.myChannels] reports it.
Channel fixtureChannel(
  int chatId,
  String title, {
  String? username,
  int memberCount = 100,
  int lastReadMessageId = 0,
  bool isMember = true,
}) => Channel(
  chatId: chatId,
  title: title,
  username: username,
  memberCount: memberCount,
  lastReadMessageId: lastReadMessageId,
  isMember: isMember,
);
