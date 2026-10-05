import 'dart:async';
import 'dart:ui';

import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/ai/semantic_gate.dart';
import 'package:telegram_feed/l10n/l10n.dart';
import 'package:telegram_feed/service/notification_pictures.dart';
import 'package:telegram_feed/service/notifier.dart';
import 'package:telegram_feed/service/reading_now.dart';
import 'package:telegram_feed/service/rule_alerts.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'notifier_harness.dart';
import 'semantic_gate_test.dart' show MemorySecrets;
import 'tts_service_test.dart' show FakeSpeaker;

/// A match becomes a line of its channel's notification and, when a rule asks, speech,
/// wherever the alerts run: in the app, or in a push run while the app is closed.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const pictureChannel = MethodChannel('tf/notificationPictures');
  const chatId = -1001;

  late AppDatabase db;
  late FakeSpeaker speaker;
  late StreamController<MatchEvent> matches;
  late StreamController<PostEvent> posts;
  late StreamController<bool> paused;
  late StreamController<ReadState> reads;
  late FakeShade shade;
  late List<ReadingNow?> reading;
  late RuleAlerts alerts;
  late DateTime now;

  /// Whether the app has a lock.
  var hasLock = false;

  /// The files the pictures were asked to download.
  late List<int> downloaded;

  MatchEvent match(
    int messageId, {
    bool readAloud = false,
    String text = 'rates cut',
    Media? media,
  }) => MatchEvent.of(
    Post(
      chatId: chatId,
      messageId: messageId,
      date: messageId,
      text: text,
      media: media,
    ),
    [
      MatchedRule(
        name: 'macro',
        priority: RulePriority.normal,
        readAloud: readAloud,
      ),
    ],
  );

  Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 20));

  /// Minutes pass: Android lists what was posted, and the channel may sound again.
  void later() => now = now.add(const Duration(minutes: 5));

  /// A button of the channel's notification, a swipe or a tap, as the alerts hear of it.
  Future<void> respond({String? action, String? type}) async {
    IsolateNameServer.lookupPortByName(notifierPortName)!.send({
      'actionId': action,
      'payload': shade.of(chatId).payload,
      'type': type ?? NotificationResponseType.selectedNotificationAction.name,
    });
    await tick();
  }

  setUp(() async {
    hasLock = false;
    downloaded = [];
    now = DateTime(2026, 10, 4, 12);
    shade = FakeShade()..install();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(pictureChannel, (
      call,
    ) async {
      final path = call.arguments as String;
      return switch (call.method) {
        'avatar' => '$path.round.png',
        'share' => 'content://files$path',
        _ => null,
      };
    });
    db = AppDatabase(NativeDatabase.memory());
    final feed = await db.createFeed('News');
    await db.addSource(feed.id, chatId, title: 'Wire');
    speaker = FakeSpeaker();
    matches = StreamController<MatchEvent>.broadcast();
    posts = StreamController<PostEvent>.broadcast();
    paused = StreamController<bool>.broadcast();
    reads = StreamController<ReadState>.broadcast();
    reading = [];
    alerts = RuleAlerts(
      db: db,
      matches: matches.stream,
      postEvents: posts.stream,
      pausedChanges: paused.stream,
      readUpdates: reads.stream,
      history: (chatId, {required fromMessageId, required limit}) async => [
        Post(
          chatId: chatId,
          messageId: fromMessageId - 1,
          date: 1,
          text: 'asked of the core',
        ),
      ],
      onReading: reading.add,
      speaker: speaker,
      gate: SemanticGate(db: db, secrets: MemorySecrets()),
      lockSet: () async => hasLock,
      notifier: Notifier(null, () => now, MemoryStore()),
      pictures: NotificationPictures(
        channels: () async => const [
          Channel(
            chatId: chatId,
            title: 'Wire',
            photo: FileRef(id: 50, remoteId: 'photo', size: 1),
          ),
        ],
        download: (file) async {
          downloaded.add(file.id);
          return FileRef(
            id: file.id,
            remoteId: file.remoteId,
            size: file.size,
            localPath: '/tdlib/${file.id}',
            width: file.width,
            height: file.height,
          );
        },
      ),
      log: (_) {},
    );
    await alerts.start(AppLanguage.englishStrings);
  });

  tearDown(() async {
    await alerts.dispose();
    await db.close();
    shade.remove();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      pictureChannel,
      null,
    );
  });

  test('with a lock set and the app not open and unlocked, a notification says '
      'only that there is a new post', () async {
    hasLock = true;
    matches.add(match(7));
    await tick();
    final hidden = shade.of(chatId);
    // Neither the channel nor the words nor its face, and no button that would say
    // them aloud.
    expect(
      (hidden.title, hidden.body),
      ('Unofficial Telegram Feed', 'New post'),
    );
    expect(hidden.texts, ['New post']);
    expect(hidden.buttons, isEmpty);
    expect(hidden.avatar, isNull);
    expect(downloaded, isEmpty);
    // The tap still knows which post it is; the rule's name is not in it.
    expect(hidden.opens.messageId, 7);
    expect(hidden.payload, isNot(contains('macro')));

    // An edit of that post does not uncover it.
    final count = shade.shown.length;
    posts.add(
      PostEdited(
        Post(chatId: chatId, messageId: 7, date: 1, text: 'rates cut twice'),
      ),
    );
    await tick();
    expect(shade.shown, hasLength(count));

    // The app on screen and past its lock: a post is shown as it is, in a notification
    // of its own once the hidden one is gone.
    shade.swipe(chatId);
    later();
    alerts.unlocked = true;
    matches.add(match(8));
    await tick();
    final open = shade.of(chatId);
    expect((open.title, open.body), ('Wire', 'rates cut'));
    expect(open.texts, ['rates cut']);
    expect(open.buttons, hasLength(2));

    // Behind the lock again, or gone from the screen: the next line says nothing.
    alerts.unlocked = false;
    later();
    matches.add(match(9));
    await tick();
    expect(shade.of(chatId).texts, ['rates cut', 'New post']);
    expect(shade.of(chatId).buttons, isEmpty);
  });

  test('without a lock a notification shows its post whether the app is open '
      'or not', () async {
    matches.add(match(7));
    await tick();
    expect(shade.of(chatId).body, 'rates cut');
  });

  test('a match is shown under its channel, and not spoken unasked', () async {
    matches.add(match(7));
    await tick();
    final post = shade.of(chatId);
    expect((post.title, post.body), ('Wire', 'rates cut'));
    expect(speaker.spoken, isEmpty);
    expect(reading, isEmpty);
  });

  test("the notification carries the channel's photo, cut round, and the "
      "post's picture in a size that fills it", () async {
    const sizes = [
      FileRef(id: 1, remoteId: 's', size: 1, width: 90, height: 60),
      FileRef(id: 2, remoteId: 'm', size: 1, width: 800, height: 533),
      FileRef(id: 3, remoteId: 'l', size: 1, width: 1280, height: 853),
    ];
    matches.add(
      match(
        7,
        text: 'the bridge',
        media: const PhotoMedia(sizes: sizes),
      ),
    );
    await tick();
    final shown = shade.of(chatId);
    expect(shown.avatar, '/tdlib/50.round.png');
    expect(shown.lines.first.picture, 'content://files/tdlib/2');
    expect(shown.lines.last.text, '🖼 the bridge');
    expect(shown.lines.last.picture, isNull);
    expect(downloaded.toSet(), {50, 2});

    // A picture under a spoiler stays under it: the newest post shows none, and the
    // older one is words now.
    later();
    matches.add(
      match(
        8,
        text: 'covered',
        media: const PhotoMedia(sizes: sizes, cover: MediaCover.spoiler),
      ),
    );
    await tick();
    expect(shade.of(chatId).texts, ['🖼 the bridge', '🖼 covered']);
    expect(shade.of(chatId).lines.map((l) => l.picture).toSet(), {null});
    expect(downloaded.toSet(), {50, 2});
  });

  test('a picture that does not come in time is left out, and the '
      'notification is shown without it', () async {
    final slow = NotificationPictures(
      channels: () async => const [],
      download: (file) => Completer<FileRef>().future,
      patience: const Duration(milliseconds: 30),
    );
    final found = await slow.of(
      Post(
        chatId: chatId,
        messageId: 1,
        date: 1,
        text: '',
        media: const PhotoMedia(
          sizes: [FileRef(id: 1, remoteId: 'r', size: 1, width: 800)],
        ),
      ),
    );
    expect((found.avatar, found.picture), (null, null));
  });

  test('a read-aloud match is spoken, and the banner hears of it', () async {
    matches.add(match(7, readAloud: true));
    await tick();
    expect(speaker.spoken.single, contains('rates cut'));
    expect(reading.last, isA<ReadingNow>());
    expect((reading.last!.chatId, reading.last!.messageId), (chatId, 7));
    expect(reading.last!.channelTitle, 'Wire');
    // Its channel's notification offers Stop meanwhile.
    expect(shade.of(chatId).buttons.last, actionStop);
    speaker.finish();
    await tick();
    expect(reading.last, isNull);
    expect(shade.of(chatId).buttons.last, actionListen);
  });

  test('Listen reads the posts the notification lists that were not read yet, '
      'oldest first; Stop stops them all', () async {
    matches.add(match(7, readAloud: true, text: 'first'));
    await tick();
    speaker.finish();
    await tick();
    later();
    matches.add(match(8, text: 'second'));
    await tick();
    later();
    matches.add(match(9, text: 'third'));
    await tick();
    expect(speaker.spoken, hasLength(1));

    await respond(action: actionListen);
    expect(speaker.spoken.last, contains('second'));
    expect(reading.last!.waiting, 1);
    expect(shade.of(chatId).buttons.last, actionStop);
    speaker.finish();
    await tick();
    expect(speaker.spoken.last, contains('third'));
    expect(speaker.spoken, hasLength(3));

    // Stop: the one being read, and with it whatever of this channel waits.
    await respond(action: actionListen);
    await respond(action: actionStop);
    expect(reading.last, isNull);
    expect(shade.of(chatId).buttons.last, actionListen);
    final spoken = speaker.spoken.length;

    // Every listed post was read: Listen reads them all again.
    await respond(action: actionListen);
    expect(speaker.spoken, hasLength(spoken + 1));
    expect(speaker.spoken.last, contains('first'));
    expect(reading.last!.waiting, 2);
    await alerts.stopAll();
  });

  test('a notification swiped away is not read any more, and what it listed is '
      'forgotten; so is that of a tapped one', () async {
    matches.add(match(7, readAloud: true, text: 'first'));
    await tick();
    shade.swipe(chatId);
    await respond(type: NotificationResponseType.notificationDismissed.name);
    expect(reading.last, isNull);

    matches.add(match(8, text: 'second'));
    await tick();
    expect(shade.of(chatId).texts, ['second']);

    shade.swipe(chatId);
    await respond(type: notificationTapped);
    matches.add(match(9, text: 'third'));
    await tick();
    expect(shade.of(chatId).texts, ['third']);
  });

  test('once listening, the alerts have the core of every account catch up on '
      'what came while nothing ran', () async {
    final asked = <String>[];
    final theirDb = AppDatabase(NativeDatabase.memory());
    addTearDown(theirDb.close);
    final caught = RuleAlerts(
      db: db,
      matches: const Stream.empty(),
      postEvents: const Stream.empty(),
      pausedChanges: const Stream.empty(),
      history: (chatId, {required fromMessageId, required limit}) async => [],
      onReading: (_) {},
      speaker: FakeSpeaker(),
      lockSet: () async => false,
      notifier: Notifier(null, () => now, MemoryStore()),
      account: 1,
      catchUp: () async => asked.add('mine'),
      others: [
        AlertAccount(
          db: theirDb,
          matches: const Stream.empty(),
          postEvents: const Stream.empty(),
          history: (chatId, {required fromMessageId, required limit}) async =>
              [],
          id: 2,
          catchUp: () async => asked.add('theirs'),
        ),
      ],
      log: (_) {},
    );
    await caught.start(AppLanguage.englishStrings);
    addTearDown(caught.dispose);
    await tick();
    expect(asked, ['mine', 'theirs']);
  });

  test('every logged-in account notifies: the same channel has a notification '
      'in each account, named by the account, and Listen asks the core of '
      'that account', () async {
    final theirDb = AppDatabase(NativeDatabase.memory());
    addTearDown(theirDb.close);
    final theirFeed = await theirDb.createFeed('Theirs');
    await theirDb.addSource(theirFeed.id, chatId, title: 'Wire');
    final mine = StreamController<MatchEvent>.broadcast();
    final theirs = StreamController<MatchEvent>.broadcast();
    final theirReads = StreamController<ReadState>.broadcast();
    final voice = FakeSpeaker();
    final both = RuleAlerts(
      db: db,
      matches: mine.stream,
      postEvents: const Stream.empty(),
      pausedChanges: const Stream.empty(),
      history: (chatId, {required fromMessageId, required limit}) async => [],
      onReading: (_) {},
      speaker: voice,
      gate: SemanticGate(db: db, secrets: MemorySecrets()),
      lockSet: () async => false,
      notifier: Notifier(null, () => now, MemoryStore()),
      account: 1,
      accountName: 'Ann',
      others: [
        AlertAccount(
          db: theirDb,
          matches: theirs.stream,
          postEvents: const Stream.empty(),
          readUpdates: theirReads.stream,
          history: (chatId, {required fromMessageId, required limit}) async => [
            Post(
              chatId: chatId,
              messageId: fromMessageId - 1,
              date: 1,
              text: 'asked of their core',
            ),
          ],
          id: 2,
          name: 'Bob',
          gate: SemanticGate(db: theirDb, secrets: MemorySecrets()),
        ),
      ],
      log: (_) {},
    );
    await both.start(AppLanguage.englishStrings);
    addTearDown(both.dispose);

    mine.add(match(7, text: 'in mine'));
    theirs.add(match(8, text: 'in theirs'));
    await tick();
    final a = shade.of(chatId, account: 1);
    final b = shade.of(chatId, account: 2);
    expect(a.header, 'Ann · macro');
    expect(a.texts, ['in mine']);
    expect(b.header, 'Bob · macro');
    expect(b.texts, ['in theirs']);
    expect((a.opens.account, b.opens.account), (1, 2));

    // Listen on the other account's notification, as after a restart of the host,
    // when the words are no longer remembered: they are asked of that account's core.
    later();
    final restarted = RuleAlerts(
      db: db,
      matches: const Stream.empty(),
      postEvents: const Stream.empty(),
      pausedChanges: const Stream.empty(),
      history: (chatId, {required fromMessageId, required limit}) async => [],
      onReading: (_) {},
      speaker: voice,
      lockSet: () async => false,
      notifier: Notifier(null, () => now, MemoryStore()),
      account: 1,
      others: [
        AlertAccount(
          db: theirDb,
          matches: const Stream.empty(),
          postEvents: const Stream.empty(),
          history: (chatId, {required fromMessageId, required limit}) async => [
            Post(
              chatId: chatId,
              messageId: fromMessageId - 1,
              date: 1,
              text: 'asked of their core',
            ),
          ],
          id: 2,
        ),
      ],
      log: (_) {},
    );
    await both.dispose();
    await restarted.start(AppLanguage.englishStrings);
    addTearDown(restarted.dispose);
    IsolateNameServer.lookupPortByName(notifierPortName)!.send({
      'actionId': actionListen,
      'payload': b.payload,
      'type': NotificationResponseType.selectedNotificationAction.name,
    });
    await tick();
    expect(voice.spoken.single, contains('asked of their core'));
    await restarted.stopAll();
  });

  test('a post read in one account leaves that account\'s notification '
      'only', () async {
    final theirDb = AppDatabase(NativeDatabase.memory());
    addTearDown(theirDb.close);
    final mine = StreamController<MatchEvent>.broadcast();
    final theirs = StreamController<MatchEvent>.broadcast();
    final theirReads = StreamController<ReadState>.broadcast();
    final both = RuleAlerts(
      db: db,
      matches: mine.stream,
      postEvents: const Stream.empty(),
      pausedChanges: const Stream.empty(),
      history: (chatId, {required fromMessageId, required limit}) async => [],
      onReading: (_) {},
      speaker: FakeSpeaker(),
      gate: SemanticGate(db: db, secrets: MemorySecrets()),
      lockSet: () async => false,
      notifier: Notifier(null, () => now, MemoryStore()),
      account: 1,
      accountName: 'Ann',
      others: [
        AlertAccount(
          db: theirDb,
          matches: theirs.stream,
          postEvents: const Stream.empty(),
          readUpdates: theirReads.stream,
          history: (chatId, {required fromMessageId, required limit}) async =>
              [],
          id: 2,
          name: 'Bob',
          gate: SemanticGate(db: theirDb, secrets: MemorySecrets()),
        ),
      ],
      log: (_) {},
    );
    await both.start(AppLanguage.englishStrings);
    addTearDown(both.dispose);
    mine.add(match(7));
    theirs.add(match(7));
    await tick();
    later();
    theirReads.add(
      const ReadState(chatId: chatId, lastReadMessageId: 7, unreadCount: 0),
    );
    await tick();
    expect(shade.cancelled, [NotificationPlan.idForChat(chatId, 2)]);
    expect(shade.live, {NotificationPlan.idForChat(chatId, 1)});
  });

  test('Stop on the banner silences the post', () async {
    matches.add(match(7, readAloud: true));
    await tick();
    await alerts.stop(chatId, 7);
    await tick();
    expect(reading.last, isNull);
  });

  test('pausing stops what is read and what waits', () async {
    matches
      ..add(match(7, readAloud: true))
      ..add(match(8, readAloud: true));
    await tick();
    expect(reading.last!.waiting, 1);
    paused.add(true);
    await tick();
    expect(reading.last, isNull);
    expect(speaker.spoken, hasLength(1));
  });

  test('an edited post changes its line', () async {
    matches.add(match(7, text: 'The bridge is closed.'));
    await tick();
    later();
    posts.add(
      PostEdited(
        Post(
          chatId: chatId,
          messageId: 7,
          date: 7,
          text: 'The bridge is open again.',
        ),
      ),
    );
    await tick();
    expect(shade.of(chatId).texts, ['The bridge is open again.']);
    expect(shade.of(chatId).alerts, isFalse);
  });

  test('a post read here or in the official app leaves its notification, '
      'which goes with the last one', () async {
    matches
      ..add(match(7, text: 'first'))
      ..add(match(8, text: 'second'));
    await tick();
    later();
    reads.add(
      const ReadState(chatId: chatId, lastReadMessageId: 7, unreadCount: 1),
    );
    await tick();
    expect(shade.of(chatId).texts, ['second']);
    expect(shade.cancelled, isEmpty);
    reads.add(
      const ReadState(chatId: chatId, lastReadMessageId: 8, unreadCount: 0),
    );
    await tick();
    expect(shade.cancelled, [NotificationPlan.idForChat(chatId)]);
  });

  test('a deleted post takes its line along', () async {
    matches.add(match(7));
    await tick();
    later();
    posts.add(const PostsDeleted(chatId: chatId, messageIds: [7]));
    await tick();
    expect(shade.cancelled, [NotificationPlan.idForChat(chatId)]);
  });
}
