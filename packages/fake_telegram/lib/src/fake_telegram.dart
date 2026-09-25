/// A whole Telegram account that answers from memory: what the fake build of the app and
/// the UI tests run against.
library;

import 'dart:async';
import 'dart:io';

import 'package:telegram_gateway/telegram_gateway.dart';

import 'scripted_gateway.dart';

/// The login code the fake accepts.
const fakeLoginCode = '12345';

/// The chat ids of the fake account's channels, negative like TDLib's.
abstract final class FakeChats {
  static const harbourTimes = -1001;
  static const circuitWeekly = -1002;
  static const northfieldGazette = -1003;
  static const wire = -1004;
  static const oldLedger = -1005;
  static const savedMessages = 42;
}

/// A scripted account: a login that takes any phone number and the code [fakeLoginCode],
/// three news channels in the folder "News", a "Wire" channel in the folder "Alerts" where a
/// post arrives every [arrivalEvery], an archived channel, Saved Messages, posts of every
/// kind, a discussion thread, and media served from [mediaDirectory]. The files there are
/// the ones under `app/assets/fake/`; a file that is missing is served as absent.
final class FakeTelegram extends TimelineGateway {
  FakeTelegram({
    required this.mediaDirectory,
    bool loggedIn = false,
    this.arrivalEvery = const Duration(seconds: 30),
    DateTime? now,
  }) : _auth = loggedIn ? const AuthReady() : const AuthWaitPhoneNumber(),
       _now = now ?? DateTime.now(),
       super({}, channels: [], folders: []) {
    _build();
    if (arrivalEvery != null) {
      _arrivals = Timer.periodic(arrivalEvery!, (_) => _arriveOnWire());
    }
  }

  final String mediaDirectory;
  final Duration? arrivalEvery;
  final DateTime _now;
  Timer? _arrivals;
  int _arrived = 0;

  // ---- login ----

  AuthState _auth;
  final _authCtl = StreamController<AuthState>.broadcast();

  @override
  Stream<AuthState> get authState async* {
    yield _auth;
    yield* _authCtl.stream;
  }

  void _setAuth(AuthState s) {
    _auth = s;
    _authCtl.add(s);
  }

  /// The phone number the login entered, for assertions.
  String phoneNumber = '';

  @override
  Future<void> setPhoneNumber(String phone) async {
    phoneNumber = phone;
    _setAuth(AuthWaitCode(phoneNumber: phone, codeLength: 5, viaSms: true));
  }

  @override
  Future<void> checkCode(String code) async {
    if (code != fakeLoginCode) {
      throw const TelegramException(400, 'PHONE_CODE_INVALID');
    }
    _setAuth(const AuthReady());
  }

  @override
  Future<void> checkPassword(String password) async =>
      _setAuth(const AuthReady());

  @override
  Future<void> registerUser({
    required String firstName,
    String lastName = '',
  }) async => _setAuth(const AuthReady());

  @override
  Future<void> requestQrCode() async =>
      _setAuth(const AuthWaitOtherDeviceConfirmation('tg://login?token=fake'));

  @override
  Future<void> logOut() async {
    _setAuth(const AuthLoggingOut());
    _setAuth(const AuthClosed());
  }

  @override
  Future<UserInfo> me() async => UserInfo(
    id: 1,
    firstName: 'Fixture',
    lastName: 'Account',
    username: 'fixture',
    phoneNumber: '+15550100',
    photo: _file('avatar1.png', 128, 128),
    bio: 'The account the fake build logs into.',
  );

  // ---- the world ----

  final _infos = <int, ChannelInfo>{};
  final _similar = <int, List<Channel>>{};

  void _build() {
    final harbour = Channel(
      chatId: FakeChats.harbourTimes,
      title: 'Harbour Times',
      username: 'harbourtimes',
      memberCount: 48210,
      photo: _file('avatar1.png', 128, 128),
    );
    final circuit = Channel(
      chatId: FakeChats.circuitWeekly,
      title: 'Circuit Weekly',
      username: 'circuitweekly',
      memberCount: 12750,
      photo: _file('avatar2.png', 128, 128),
    );
    final gazette = Channel(
      chatId: FakeChats.northfieldGazette,
      title: 'Northfield Gazette',
      username: 'northfieldgazette',
      memberCount: 3120,
      photo: _file('avatar3.png', 128, 128),
    );
    const wire = Channel(
      chatId: FakeChats.wire,
      title: 'Wire',
      username: 'wirealerts',
      memberCount: 905,
    );
    channels.addAll([harbour, circuit, gazette, wire]);
    archived = const [
      Channel(
        chatId: FakeChats.oldLedger,
        title: 'Old Ledger',
        username: 'oldledger',
        memberCount: 77,
      ),
    ];
    folders.addAll([
      ChatFolder(
        id: 1,
        title: 'News',
        channelIds: [harbour.chatId, circuit.chatId, gazette.chatId],
      ),
      ChatFolder(id: 2, title: 'Alerts', channelIds: [wire.chatId]),
    ]);
    _infos[harbour.chatId] = ChannelInfo(
      chatId: harbour.chatId,
      description:
          'News from the harbour district: shipping, weather and the market.',
      memberCount: harbour.memberCount,
      inviteLink: 'https://t.me/harbourtimes',
      bigPhoto: _file('avatar1.png', 128, 128),
    );
    _infos[circuit.chatId] = ChannelInfo(
      chatId: circuit.chatId,
      description: 'One issue a week about small electronics.',
      memberCount: circuit.memberCount,
      inviteLink: 'https://t.me/circuitweekly',
      bigPhoto: _file('avatar2.png', 128, 128),
    );
    _infos[gazette.chatId] = ChannelInfo(
      chatId: gazette.chatId,
      description: 'The town of Northfield, day by day.',
      memberCount: gazette.memberCount,
      inviteLink: 'https://t.me/northfieldgazette',
      bigPhoto: _file('avatar3.png', 128, 128),
    );
    _infos[wire.chatId] = ChannelInfo(
      chatId: wire.chatId,
      description: 'Short alerts, one every half minute.',
      memberCount: wire.memberCount,
      inviteLink: 'https://t.me/wirealerts',
    );
    _similar[harbour.chatId] = [circuit, gazette];
    _similar[circuit.chatId] = [harbour, gazette];
    _similar[gazette.chatId] = [harbour, circuit];
    _similar[wire.chatId] = [harbour];

    histories[harbour.chatId] = _harbourPosts();
    histories[circuit.chatId] = _circuitPosts();
    histories[gazette.chatId] = _gazettePosts();
    histories[wire.chatId] = [
      _post(
        wire.chatId,
        2,
        hoursAgo: 1,
        text: 'Wire: the bridge is open again.',
      ),
      _post(wire.chatId, 1, hoursAgo: 3, text: 'Wire: the bridge is closed.'),
    ];
    histories[FakeChats.oldLedger] = [
      _post(FakeChats.oldLedger, 1, hoursAgo: 900, text: 'The ledger closes.'),
    ];
    histories[FakeChats.savedMessages] = [
      _post(
        FakeChats.savedMessages,
        1,
        hoursAgo: 50,
        text: 'A note to myself: read the Harbour Times on Sundays.',
      ),
    ];
    // Everything but the newest three posts of each channel is read already, so a
    // fresh feed opens at an "Unread posts" divider and the counts are small.
    for (final c in channels) {
      final h = histories[c.chatId]!;
      readPositions[c.chatId] = h.length > 3 ? h[3].messageId : 0;
    }
    readPositions[FakeChats.savedMessages] = 1;
  }

  /// Eleven posts, one of every kind, newest first: the sample the reading screens show.
  List<Post> _harbourPosts() {
    const chat = FakeChats.harbourTimes;
    return [
      _post(
        chat,
        11,
        hoursAgo: 2,
        text: 'Weekend market: what the stalls bring this Saturday. Tell us what you bought.',
        views: 4010,
        canComment: true,
        replyCount: 2,
        reactions: const [Reaction(emoji: '👍', count: 31)],
      ),
      _post(
        chat,
        10,
        hoursAgo: 7,
        text:
            'The council met on Tuesday and talked for three hours about the pier.\n\n'
            'The pier has stood since 1911. Its planks were replaced in 1978 and again in '
            '2004, and the engineers now say the pilings under the east end have another '
            'ten years in them at most.\n\n'
            'Three plans are on the table: repair the pilings one by one over five summers, '
            'close the east end and build a shorter pier, or replace the whole structure '
            'with a concrete one. The council votes in October.',
        views: 3320,
        reactions: const [
          Reaction(emoji: '🤔', count: 12),
          Reaction(emoji: '❤', count: 4),
        ],
      ),
      _post(
        chat,
        9,
        hoursAgo: 12,
        text: 'Timetable for the winter ferries, as a file.',
        media: DocumentMedia(
          file: _file('notes.txt', 0, 0),
          fileName: 'ferries-winter.txt',
          mimeType: 'text/plain',
        ),
        views: 1200,
      ),
      _post(
        chat,
        8,
        hoursAgo: 17,
        text: 'Circuit Weekly on the harbour lights, worth a read.',
        forwardedFrom: const ForwardOrigin(
          title: 'Circuit Weekly',
          chatId: FakeChats.circuitWeekly,
          messageId: 15,
        ),
        views: 980,
      ),
      _post(
        chat,
        7,
        hoursAgo: 22,
        text: 'Yes, the east end. The one with the benches.',
        replyTo: const ReplyTarget(
          chatId: chat,
          messageId: 1,
          title: 'Harbour Times',
          text: 'Which end of the pier is closed?',
        ),
        views: 870,
      ),
      _post(
        chat,
        6,
        hoursAgo: 27,
        text: 'The tide tables for October are online.',
        linkPreview: const LinkPreview(
          url: 'https://example.com/tides/october',
          displayUrl: 'example.com/tides/october',
          siteName: 'Example Tides',
          title: 'Tide tables: October',
          description: 'High and low water for every day of the month.',
        ),
        views: 2210,
      ),
      _post(
        chat,
        5,
        hoursAgo: 31,
        text: 'Test pattern from the harbour camera, ten seconds.',
        media: VideoMedia(
          file: _file('video.mp4', 640, 360),
          durationSeconds: 10,
          thumbnail: _file('thumb.png', 320, 180),
        ),
        views: 5600,
        reactions: const [Reaction(emoji: '🔥', count: 8)],
      ),
      _post(
        chat,
        4,
        hoursAgo: 36,
        text: 'Three views of the quay this morning.',
        albumId: 7,
        media: PhotoMedia(sizes: [_file('photo2.png', 480, 640)]),
        views: 1500,
      ),
      _post(
        chat,
        3,
        hoursAgo: 36,
        text: '',
        albumId: 7,
        media: PhotoMedia(sizes: [_file('photo3.png', 640, 640)]),
        views: 1500,
      ),
      _post(
        chat,
        2,
        hoursAgo: 36,
        text: '',
        albumId: 7,
        media: PhotoMedia(sizes: [_file('photo4.png', 640, 360)]),
        views: 1500,
      ),
      _post(
        chat,
        1,
        hoursAgo: 40,
        text: 'The new lighthouse lamp is lit tonight. Details on our site.',
        entities: const [
          TextEntity(offset: 4, length: 19, kind: TextEntityKind.bold),
          TextEntity(
            offset: 48,
            length: 8,
            kind: TextEntityKind.link,
            url: 'https://example.com/lighthouse',
          ),
        ],
        media: PhotoMedia(sizes: [_file('photo1.png', 640, 480)]),
        views: 8200,
        reactions: const [
          Reaction(emoji: '❤', count: 120),
          Reaction(emoji: '👍', count: 44),
        ],
      ),
    ];
  }

  /// Sixteen short posts, enough for a second page, plus one picture.
  List<Post> _circuitPosts() {
    const chat = FakeChats.circuitWeekly;
    return [
      for (var n = 16; n >= 1; n--)
        if (n == 15)
          _post(
            chat,
            n,
            hoursAgo: 6 + (16 - n) * 5,
            text: 'Issue $n: the harbour lights, and how they are wired.',
            media: PhotoMedia(sizes: [_file('photo1.png', 640, 480)]),
            views: 700 + n,
          )
        else
          _post(
            chat,
            n,
            hoursAgo: 6 + (16 - n) * 5,
            text: 'Issue $n: ${_circuitTopics[n % _circuitTopics.length]}',
            views: 700 + n,
          ),
    ];
  }

  static const _circuitTopics = [
    'a timer from three parts',
    'reading a resistor',
    'why the LED is dim',
    'a battery that lasts a winter',
    'soldering without a stand',
  ];

  List<Post> _gazettePosts() {
    const chat = FakeChats.northfieldGazette;
    return [
      _post(
        chat,
        5,
        hoursAgo: 4,
        text: 'Northfield: the library opens late on Thursdays.',
      ),
      _post(
        chat,
        4,
        hoursAgo: 28,
        text: 'Northfield: road works on Mill Street until Friday.',
      ),
      _post(
        chat,
        3,
        hoursAgo: 52,
        text: 'Northfield: the school fair raised 2,400.',
      ),
      _post(
        chat,
        2,
        hoursAgo: 76,
        text: 'Northfield: a new bench by the pond.',
      ),
      _post(
        chat,
        1,
        hoursAgo: 100,
        text: 'Northfield: the gazette is now on Telegram.',
      ),
    ];
  }

  /// A post [hoursAgo] hours before [_now]; the id is its place in the channel.
  Post _post(
    int chatId,
    int messageId, {
    required int hoursAgo,
    required String text,
    int albumId = 0,
    Media? media,
    int views = 0,
    List<Reaction> reactions = const [],
    int replyCount = 0,
    bool canComment = false,
    List<TextEntity> entities = const [],
    LinkPreview? linkPreview,
    ForwardOrigin? forwardedFrom,
    ReplyTarget? replyTo,
  }) => Post(
    chatId: chatId,
    messageId: messageId,
    date:
        _now.subtract(Duration(hours: hoursAgo)).millisecondsSinceEpoch ~/ 1000,
    text: text,
    albumId: albumId,
    media: media,
    views: views,
    reactions: reactions,
    replyCount: replyCount,
    canComment: canComment,
    entities: entities,
    linkPreview: linkPreview,
    forwardedFrom: forwardedFrom,
    replyTo: replyTo,
  );

  // ---- media ----

  final _files = <int, String>{};
  int _nextFileId = 100;

  /// A file of the media directory. Its id is stable for the name, so a second post with
  /// the same picture shares its download.
  FileRef _file(String name, int width, int height) {
    var id = _files.entries
        .where((e) => e.value == name)
        .map((e) => e.key)
        .firstOrNull;
    if (id == null) {
      id = _nextFileId++;
      _files[id] = name;
    }
    final f = File('$mediaDirectory/$name');
    return FileRef(
      id: id,
      remoteId: 'fake:$name',
      size: f.existsSync() ? f.lengthSync() : 0,
      width: width,
      height: height,
    );
  }

  String? _pathOf(int fileId) {
    final name = _files[fileId];
    if (name == null) return null;
    final path = '$mediaDirectory/$name';
    return File(path).existsSync() ? path : null;
  }

  @override
  Future<FileRef> download(FileRef ref, {int priority = 16}) async {
    final path = _pathOf(ref.id);
    if (path == null) throw const TelegramException(404, 'FILE_NOT_FOUND');
    return ref.copyWith(localPath: path);
  }

  @override
  Stream<FileProgress> fileProgress(int fileId) async* {
    final path = _pathOf(fileId);
    if (path == null) return;
    final size = File(path).lengthSync();
    yield FileProgress(
      fileId: fileId,
      downloaded: size,
      total: size,
      localPath: path,
      partialPath: path,
    );
  }

  @override
  Future<FileProgress> downloadFrom(
    int fileId, {
    int offset = 0,
    int priority = 32,
    int limit = 0,
  }) async {
    final path = _pathOf(fileId);
    if (path == null) {
      return FileProgress(fileId: fileId, downloaded: 0, total: 0);
    }
    final size = File(path).lengthSync();
    return FileProgress(
      fileId: fileId,
      downloaded: size,
      total: size,
      localPath: path,
      partialPath: path,
    );
  }

  @override
  Future<int> downloadedPrefix(int fileId, int offset) async {
    final path = _pathOf(fileId);
    if (path == null) return 0;
    final size = File(path).lengthSync();
    return offset >= size ? 0 : size - offset;
  }

  @override
  Future<StorageStats> storageStats() async {
    var bytes = 0;
    var count = 0;
    for (final id in _files.keys) {
      final path = _pathOf(id);
      if (path == null) continue;
      bytes += File(path).lengthSync();
      count++;
    }
    return StorageStats(
      filesBytes: bytes,
      fileCount: count,
      databaseBytes: 4096,
    );
  }

  @override
  Future<StorageStats> clearCache() => storageStats();

  // ---- channels ----

  @override
  Future<ChannelInfo> channelInfo(int chatId) async =>
      _infos[chatId] ?? ChannelInfo(chatId: chatId);

  @override
  Future<List<Channel>> similarChannels(int chatId) async =>
      _similar[chatId] ?? const [];

  @override
  Future<Channel> savedMessages() async =>
      const Channel(chatId: FakeChats.savedMessages, title: 'Saved Messages');

  @override
  Future<void> saveToSavedMessages(int chatId, List<int> messageIds) async {
    await super.saveToSavedMessages(chatId, messageIds);
    final saved = histories[FakeChats.savedMessages]!;
    final next = saved.first.messageId + 1;
    for (final id in messageIds) {
      final source = histories[chatId]
          ?.where((p) => p.messageId == id)
          .firstOrNull;
      if (source == null) continue;
      saved.insert(
        0,
        Post(
          chatId: FakeChats.savedMessages,
          messageId: next,
          date: _now.millisecondsSinceEpoch ~/ 1000,
          text: source.text,
          media: source.media,
          forwardedFrom: ForwardOrigin(
            title: channels.where((c) => c.chatId == chatId).first.title,
            chatId: chatId,
            messageId: id,
          ),
        ),
      );
    }
  }

  @override
  Future<SearchPage> searchHistory(
    int chatId, {
    String query = '',
    HistoryFilter filter = HistoryFilter.any,
    int fromMessageId = 0,
    int limit = 30,
  }) async {
    final page = await super.searchHistory(
      chatId,
      query: query,
      filter: filter,
      fromMessageId: fromMessageId,
      limit: 1 << 20,
    );
    final kept = page.posts.where((p) => _passes(p, filter)).toList();
    final shown = kept.take(limit).toList();
    return SearchPage(
      posts: shown,
      totalCount: kept.length,
      nextFromMessageId: shown.length < kept.length ? shown.last.messageId : 0,
    );
  }

  @override
  Future<GlobalSearchPage> searchAllChannels({
    required String query,
    HistoryFilter filter = HistoryFilter.any,
    String offset = '',
    int limit = 30,
  }) async {
    final page = await super.searchAllChannels(
      query: query,
      filter: filter,
      offset: offset,
      limit: limit,
    );
    final kept = page.posts
        .where((p) => p.chatId != FakeChats.savedMessages && _passes(p, filter))
        .toList();
    return GlobalSearchPage(
      posts: kept,
      totalCount: kept.length,
      nextOffset: '',
    );
  }

  static bool _passes(Post p, HistoryFilter f) => switch (f) {
    HistoryFilter.any => true,
    HistoryFilter.photoAndVideo =>
      p.media is PhotoMedia || p.media is VideoMedia,
    HistoryFilter.url =>
      p.linkPreview != null ||
          p.entities.any((e) => e.kind == TextEntityKind.link),
    HistoryFilter.document => p.media is DocumentMedia,
    HistoryFilter.audio =>
      p.media is AudioMedia && !(p.media as AudioMedia).isVoice,
    HistoryFilter.voice =>
      p.media is AudioMedia && (p.media as AudioMedia).isVoice,
  };

  // ---- reactions ----

  @override
  Future<List<String>> availableReactions(int chatId, int messageId) async =>
      const ['👍', '🔥', '❤', '🤔'];

  @override
  Future<void> react(
    int chatId,
    int messageId,
    String emoji, {
    bool remove = false,
  }) async {
    await super.react(chatId, messageId, emoji, remove: remove);
    final history = histories[chatId];
    if (history == null) return;
    final i = history.indexWhere((p) => p.messageId == messageId);
    if (i < 0) return;
    final p = history[i];
    final reactions = [
      for (final r in p.reactions)
        if (r.emoji != emoji) r,
    ];
    final own = p.reactions.where((r) => r.emoji == emoji).firstOrNull;
    if (!remove) {
      reactions.add(
        Reaction(
          emoji: emoji,
          count: (own?.count ?? 0) + (own?.chosen ?? false ? 0 : 1),
          chosen: true,
        ),
      );
    } else if (own != null && own.count > 1) {
      reactions.add(Reaction(emoji: emoji, count: own.count - 1));
    }
    final edited = Post(
      chatId: p.chatId,
      messageId: p.messageId,
      date: p.date,
      text: p.text,
      editDate: p.editDate,
      albumId: p.albumId,
      media: p.media,
      views: p.views,
      reactions: reactions,
      replyCount: p.replyCount,
      canComment: p.canComment,
      entities: p.entities,
      linkPreview: p.linkPreview,
      forwardedFrom: p.forwardedFrom,
      replyTo: p.replyTo,
    );
    history[i] = edited;
    posts.add(PostEdited(edited));
  }

  // ---- comments ----

  final _threads = <(int, int), List<Comment>>{};
  final _commentsCtl = StreamController<Comment>.broadcast();

  @override
  Stream<Comment> get comments => _commentsCtl.stream;

  @override
  Future<Thread?> discussion(int chatId, int messageId) async {
    final post = histories[chatId]
        ?.where((p) => p.messageId == messageId)
        .firstOrNull;
    if (post == null || !post.canComment) return null;
    final key = (chatId, messageId);
    _threads[key] ??= [
      Comment(
        chatId: chatId - 1000,
        messageId: 2,
        threadId: messageId,
        date: post.date + 1800,
        text: 'Apples from the orchard stall, as every year.',
        author: 'Mara',
        authorId: 11,
      ),
      Comment(
        chatId: chatId - 1000,
        messageId: 1,
        threadId: messageId,
        date: post.date + 600,
        text: 'Is the fish stall back?',
        author: 'Tomas',
        authorId: 12,
      ),
    ];
    return Thread(
      chatId: chatId - 1000,
      threadId: messageId,
      postChatId: chatId,
      postMessageId: messageId,
      replyCount: _threads[key]!.length,
    );
  }

  List<Comment> _threadOf(Thread t) =>
      _threads[(t.postChatId, t.postMessageId)] ?? const [];

  @override
  Future<List<Comment>> threadHistory(
    Thread thread, {
    int fromMessageId = 0,
    int limit = 30,
  }) async => [
    for (final c in _threadOf(thread))
      if (fromMessageId == 0 || c.messageId < fromMessageId) c,
  ].take(limit).toList();

  @override
  Future<List<Comment>> searchThread(
    Thread thread, {
    required String query,
    int fromMessageId = 0,
    int limit = 30,
  }) async => [
    for (final c in _threadOf(thread))
      if (c.text.toLowerCase().contains(query.toLowerCase())) c,
  ];

  /// Every reply sent, for assertions.
  final replies = <String>[];

  @override
  Future<void> reply(Thread thread, String text) async {
    replies.add(text);
    final list = _threads[(thread.postChatId, thread.postMessageId)];
    if (list == null) return;
    final c = Comment(
      chatId: thread.chatId,
      messageId: (list.firstOrNull?.messageId ?? 0) + 1,
      threadId: thread.threadId,
      date: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      text: text,
      author: 'Fixture Account',
      authorId: 1,
      isOutgoing: true,
    );
    list.insert(0, c);
    _commentsCtl.add(c);
  }

  // ---- arrivals ----

  /// A post arrives on the Wire channel now, as the timer does every [arrivalEvery].
  void arriveOnWire() => _arriveOnWire();

  void _arriveOnWire() {
    _arrived++;
    final last = histories[FakeChats.wire]!.first.messageId;
    arrive(
      Post(
        chatId: FakeChats.wire,
        messageId: last + 1,
        date: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        text: 'Breaking: fixture post $_arrived from the wire.',
      ),
    );
  }

  @override
  Future<void> close() async {
    _arrivals?.cancel();
    await _authCtl.close();
    await _commentsCtl.close();
  }
}
