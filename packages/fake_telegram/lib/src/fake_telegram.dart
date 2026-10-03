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

  /// A number that ends so logs in with a code sent to its email address.
  static const emailLoginSuffix = '2222';

  @override
  Future<void> setPhoneNumber(String phone) async {
    phoneNumber = phone;
    _setAuth(
      phone.endsWith(emailLoginSuffix)
          ? const AuthWaitEmailCode(
              emailPattern: 'f***@example.com',
              codeLength: 5,
            )
          : AuthWaitCode(phoneNumber: phone, codeLength: 5, viaSms: true),
    );
  }

  @override
  Future<void> checkCode(String code) async {
    if (code != fakeLoginCode) {
      throw const TelegramException(400, 'PHONE_CODE_INVALID');
    }
    _setAuth(const AuthReady());
  }

  @override
  Future<void> setEmailAddress(String email) async => _setAuth(
    const AuthWaitEmailCode(emailPattern: 'f***@example.com', codeLength: 5),
  );

  @override
  Future<void> checkEmailCode(String code) => checkCode(code);

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
    List<Post> pinnedOf(int chatId, List<int> ids) {
      final history = histories[chatId]!;
      for (var i = 0; i < history.length; i++) {
        final p = history[i];
        if (!ids.contains(p.messageId)) continue;
        history[i] = Post(
          chatId: p.chatId,
          messageId: p.messageId,
          date: p.date,
          text: p.text,
          editDate: p.editDate,
          albumId: p.albumId,
          media: p.media,
          views: p.views,
          reactions: p.reactions,
          replyCount: p.replyCount,
          canComment: p.canComment,
          entities: p.entities,
          linkPreview: p.linkPreview,
          forwardedFrom: p.forwardedFrom,
          replyTo: p.replyTo,
          canBeSaved: p.canBeSaved,
          buttons: p.buttons,
          signature: p.signature,
          isPinned: true,
          recentCommenters: p.recentCommenters,
          hasUnreadComments: p.hasUnreadComments,
          captionAbove: p.captionAbove,
        );
      }
      return [
        for (final p in history)
          if (ids.contains(p.messageId)) p,
      ];
    }

    pins[gazette.chatId] = pinnedOf(gazette.chatId, const [3]);
    pins[harbour.chatId] = pinnedOf(harbour.chatId, const [10, 6, 1]);
    histories[wire.chatId] = [
      _post(
        wire.chatId,
        2,
        hoursAgo: 1,
        text: 'Wire: the bridge is open again.',
      ),
      _post(wire.chatId, 1, hoursAgo: 3, text: 'Wire: the bridge is closed.'),
    ];
    // The archived channel protects its content: nothing of it is copied or saved.
    histories[FakeChats.oldLedger] = [
      _post(
        FakeChats.oldLedger,
        1,
        hoursAgo: 900,
        text: 'The ledger closes.',
        media: PhotoMedia(sizes: [_file('photo3.png', 640, 640)]),
        canBeSaved: false,
      ),
    ];
    // Saved Messages holds what was put aside: a note, and one of each kind of post that
    // is not words, pictures or files.
    histories[FakeChats.savedMessages] = [
      _post(
        FakeChats.savedMessages,
        6,
        hoursAgo: 10,
        text: 'A note to myself: read the Harbour Times on Sundays.',
      ),
      _post(
        FakeChats.savedMessages,
        5,
        hoursAgo: 20,
        text: 'Beat my score',
        media: const GameMedia(
          title: 'Tide Runner',
          description: 'Run along the quay before the water comes in.',
        ),
      ),
      _post(
        FakeChats.savedMessages,
        4,
        hoursAgo: 24,
        text: '',
        media: const ChecklistMedia(
          title: 'Before the ferry',
          tasks: [
            ChecklistTask(text: 'Tickets', done: true),
            ChecklistTask(text: 'Coffee for the crossing'),
            ChecklistTask(text: 'Feed the cat', done: true),
          ],
        ),
      ),
      _post(
        FakeChats.savedMessages,
        3,
        hoursAgo: 30,
        text: '',
        media: const ContactMedia(
          name: 'Mara Lind',
          phone: '+1 555 010 0142',
          userId: 11,
        ),
      ),
      _post(
        FakeChats.savedMessages,
        2,
        hoursAgo: 36,
        text: '',
        media: const LocationMedia(
          latitude: 54.3233,
          longitude: 10.1394,
          title: 'The Quay',
          address: 'Harbour Road 1',
        ),
      ),
      _post(
        FakeChats.savedMessages,
        1,
        hoursAgo: 40,
        text: '',
        media: const LocationMedia(latitude: 54.3233, longitude: 10.1394),
      ),
    ];
    // Everything but the newest three posts of each channel is read already, so a
    // fresh feed opens at an "Unread posts" divider and the counts are small.
    for (final c in channels) {
      final h = histories[c.chatId]!;
      readPositions[c.chatId] = h.length > 3 ? h[3].messageId : 0;
    }
    // What the account saved itself is read, as its own messages are.
    readPositions[FakeChats.savedMessages] =
        histories[FakeChats.savedMessages]!.first.messageId;
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
        // Mara has a photo, Tomas his initial; a comment came since the thread was read.
        recentCommenters: [
          Commenter(
            id: 11,
            name: 'Mara',
            photo: _file('avatar1.png', 160, 160),
          ),
          const Commenter(id: 12, name: 'Tomas'),
        ],
        hasUnreadComments: true,
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
        reactions: [
          const Reaction(emoji: paidReaction, count: 3),
          const Reaction(emoji: '🤔', count: 12),
          const Reaction(emoji: '❤', count: 4),
          Reaction(emoji: customReaction(_harbourEmoji), count: 7),
        ],
      ),
      _post(
        chat,
        9,
        hoursAgo: 12,
        //     0         1         2         3         4         5         6         7
        //     0123456789012345678901234567890123456789012345678901234567890123456789012345
        text: 'Timetable for the winter ferries, as a file. #ferries Office: 555-0199, code F12.',
        entities: const [
          TextEntity(offset: 45, length: 8, kind: TextEntityKind.hashtag),
          TextEntity(
            offset: 62,
            length: 8,
            kind: TextEntityKind.phone,
            url: 'tel:5550199',
          ),
          TextEntity(offset: 77, length: 3, kind: TextEntityKind.code),
        ],
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
        // Telegram keeps an album's reactions and comments on its first message.
        reactions: const [Reaction(emoji: '👍', count: 5)],
        canComment: true,
        replyCount: 2,
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
        if (n == 13)
          // A quote, a quote that opens, and code with its language.
          _post(
            chat,
            n,
            hoursAgo: 6 + (16 - n) * 5,
            text: _issue13,
            entities: [
              TextEntity(
                offset: _issue13.indexOf('A cell'),
                length: 'A cell rests better cold.'.length,
                kind: TextEntityKind.quote,
              ),
              TextEntity(
                offset: _issue13.indexOf('We left'),
                length:
                    _issue13.indexOf('The sketch') -
                    1 -
                    _issue13.indexOf('We left'),
                kind: TextEntityKind.quote,
                expandable: true,
              ),
              TextEntity(
                offset: _issue13.indexOf('void loop'),
                length: _issue13.length - _issue13.indexOf('void loop'),
                kind: TextEntityKind.pre,
                language: 'cpp',
              ),
            ],
            views: 700 + n,
          )
        else if (n == 12 || n == 11)
          // A picture under a spoiler, and one that Telegram covers as content for adults.
          _post(
            chat,
            n,
            hoursAgo: 6 + (16 - n) * 5,
            text: 'Issue $n: ${_circuitTopics[n % _circuitTopics.length]}',
            media: PhotoMedia(
              sizes: [
                n == 12
                    ? _file('photo2.png', 480, 640)
                    : _file('photo3.png', 640, 640),
              ],
              cover: n == 12 ? MediaCover.spoiler : MediaCover.sensitive,
            ),
            views: 700 + n,
          )
        else if (n == 15)
          _post(
            chat,
            n,
            hoursAgo: 6 + (16 - n) * 5,
            text: 'Issue $n: the harbour lights, and how they are wired.',
            media: PhotoMedia(sizes: [_file('photo1.png', 640, 480)]),
            views: 700 + n,
            // The words stand over the picture.
            captionAbove: true,
          )
        else if (n == 14)
          // A link into Telegram: the card says what it opens.
          _post(
            chat,
            n,
            hoursAgo: 6 + (16 - n) * 5,
            text: 'Issue $n: ${_circuitTopics[n % _circuitTopics.length]}',
            views: 700 + n,
            signature: 'Ada',
            linkPreview: const LinkPreview(
              url: 'https://t.me/harbourtimes',
              displayUrl: 't.me/harbourtimes',
              kind: LinkKind.channel,
              siteName: 'Telegram',
              title: 'Harbour Times',
              description: 'News from the quay, every day.',
            ),
          )
        else
          _post(
            chat,
            n,
            hoursAgo: 6 + (16 - n) * 5,
            text: 'Issue $n: ${_circuitTopics[n % _circuitTopics.length]}',
            views: 700 + n,
            // The channel signs its posts.
            signature: n.isEven ? 'Ada' : '',
            // The newest issue carries link buttons: one alone, then two in a row.
            buttons: n != 16
                ? const []
                : const [
                    [
                      UrlButton(
                        text: 'Read issue 16',
                        url: 'https://example.org/issues/16',
                      ),
                    ],
                    [
                      UrlButton(
                        text: 'Subscribe',
                        url: 'https://example.org/subscribe',
                      ),
                      UrlButton(
                        text: 'Harbour Times',
                        url: 'https://t.me/harbourtimes',
                      ),
                    ],
                  ],
          ),
    ];
  }

  static const _issue13 =
      'Issue 13: a battery that lasts a winter\n'
      'A cell rests better cold.\n'
      'We left three boards on the roof from November to March. The one that slept '
      'between readings was still at 2.9 V in spring, the one that polled every second '
      'was flat by Christmas, and the third, which woke once a minute, made it to '
      'February. Sleep is the whole trick.\n'
      'The sketch that slept:\n'
      'void loop() {\n'
      '  read();\n'
      '  sleep(60);\n'
      '}';

  static const _circuitTopics = [
    'a timer from three parts',
    'reading a resistor',
    'why the LED is dim',
    'a battery that lasts a winter',
    'soldering without a stand',
  ];

  /// Five posts, and under them the service lines of a young channel and a post that is
  /// one emoji.
  List<Post> _gazettePosts() {
    const chat = FakeChats.northfieldGazette;
    return [
      _post(
        chat,
        9,
        hoursAgo: 4,
        text: 'Northfield: the library opens late on Thursdays.',
      ),
      _post(
        chat,
        8,
        hoursAgo: 28,
        text: 'Northfield: road works on Mill Street until Friday.',
      ),
      _post(
        chat,
        7,
        hoursAgo: 52,
        text: 'Northfield: the school fair raised 2,400.',
      ),
      _post(
        chat,
        6,
        hoursAgo: 76,
        text: 'Northfield: a new bench by the pond.',
      ),
      _post(chat, 5, hoursAgo: 98, text: '🎉'),
      _post(
        chat,
        4,
        hoursAgo: 99,
        text: '',
        media: const ServiceNote(ServiceKind.pinned, messageId: 3),
      ),
      _post(
        chat,
        3,
        hoursAgo: 100,
        text: 'Northfield: the gazette is now on Telegram.',
      ),
      _post(
        chat,
        2,
        hoursAgo: 119,
        text: '',
        media: const ServiceNote(ServiceKind.photoChanged),
      ),
      _post(
        chat,
        1,
        hoursAgo: 120,
        text: '',
        media: const ServiceNote(ServiceKind.channelCreated),
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
    bool canBeSaved = true,
    List<List<UrlButton>> buttons = const [],
    String signature = '',
    bool isPinned = false,
    List<Commenter> recentCommenters = const [],
    bool hasUnreadComments = false,
    bool captionAbove = false,
  }) => Post(
    captionAbove: captionAbove,
    canBeSaved: canBeSaved,
    buttons: buttons,
    signature: signature,
    isPinned: isPinned,
    recentCommenters: recentCommenters,
    hasUnreadComments: hasUnreadComments,
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

  /// Every place has the same map: the fake has one picture for it.
  @override
  Future<FileRef> mapThumbnail(
    double latitude,
    double longitude, {
    int width = 600,
    int height = 300,
  }) async => _file('photo4.png', 640, 360);

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

  /// The newest id Saved Messages gave out: Telegram never gives one twice, not even
  /// after the post with it was deleted.
  int _lastSavedId = 0;

  @override
  Future<void> saveToSavedMessages(int chatId, List<int> messageIds) async {
    await super.saveToSavedMessages(chatId, messageIds);
    final saved = histories[FakeChats.savedMessages]!;
    for (final p in saved) {
      if (p.messageId > _lastSavedId) _lastSavedId = p.messageId;
    }
    for (final id in messageIds) {
      final source = histories[chatId]
          ?.where((p) => p.messageId == id)
          .firstOrNull;
      if (source == null) continue;
      saved.insert(
        0,
        Post(
          chatId: FakeChats.savedMessages,
          messageId: ++_lastSavedId,
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

  /// The custom emoji Harbour Times lets its readers react with.
  static const _harbourEmoji = '9001';

  @override
  Future<List<String>> availableReactions(int chatId, int messageId) async => [
    '👍',
    '🔥',
    '❤',
    '🤔',
    if (chatId == FakeChats.harbourTimes) customReaction(_harbourEmoji),
  ];

  @override
  Future<Map<String, StickerMedia>> customEmoji(List<String> ids) async => {
    if (ids.contains(_harbourEmoji))
      _harbourEmoji: StickerMedia(
        file: _file('avatar3.png', 64, 64),
        format: StickerFormat.webp,
        width: 64,
        height: 64,
        emoji: '🟢',
      ),
  };

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

      buttons: p.buttons,
      signature: p.signature,
      isPinned: p.isPinned,
      recentCommenters: p.recentCommenters,
      hasUnreadComments: p.hasUnreadComments,
      captionAbove: p.captionAbove,
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
        media: PhotoMedia(sizes: [_file('photo4.png', 640, 480)]),
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
