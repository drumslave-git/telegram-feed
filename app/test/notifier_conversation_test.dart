import 'package:core/core.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/app_name.dart';
import 'package:telegram_feed/l10n/l10n.dart';
import 'package:telegram_feed/service/notifier.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'notifier_harness.dart';

/// A channel has one notification, which lists its matched posts as a conversation.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const chatId = -1001;
  final chatNotification = NotificationPlan.idForChat(chatId);

  late FakeShade shade;
  late MemoryStore store;
  late DateTime now;

  /// Minutes pass: the limit on how often a channel sounds does not come in, and
  /// Android has listed what was posted.
  void later() => now = now.add(const Duration(minutes: 5));

  Future<Notifier> start() async {
    final notifier = Notifier(null, () => now, store);
    await notifier.init();
    return notifier;
  }

  setUp(() {
    shade = FakeShade()..install();
    store = MemoryStore();
    now = DateTime(2026, 10, 4, 12);
  });

  tearDown(() => shade.remove());

  test('the matched posts of a channel are the lines of one notification, '
      'oldest first, and a tap opens the oldest', () async {
    final notifier = await start();
    await notifier.show(planFor(10, text: 'first', rule: 'macro'));
    later();
    await notifier.show(planFor(11, text: 'second', rule: 'rates'));
    later();
    await notifier.show(planFor(12, text: 'third', rule: 'macro'));

    expect(shade.shown.map((s) => s.id).toSet(), {chatNotification});
    expect(shade.live, {chatNotification});
    final last = shade.shown.last;
    expect(last.title, 'News');
    expect(last.body, 'third');
    expect(last.texts, ['first', 'second', 'third']);
    expect(last.lines.map((l) => l.sender).toSet(), {'News'});
    // Each line carries the time of its post; the notification that of the newest.
    expect(last.lines.map((l) => l.at), [10000, 11000, 12000]);
    expect(last.when, 12000);
    // The rule of the newest post says why it is here.
    expect(last.rule, 'macro');
    expect(last.header, 'macro');
    expect(last.opens.messageId, 10);
    expect(last.buttons, [actionOpenTelegram, actionListen]);
    expect(notifier.listed(chatId).map((r) => r.messageId), [10, 11, 12]);
  });

  test('every channel has a notification of its own', () async {
    final notifier = await start();
    await notifier.show(planFor(10, text: 'here'));
    await notifier.show(
      planFor(7, chatId: -1002, text: 'there', title: 'Wire'),
    );
    expect(shade.live, {chatNotification, NotificationPlan.idForChat(-1002)});
    expect(shade.of(chatId).texts, ['here']);
    expect(shade.of(-1002).texts, ['there']);
    expect(shade.of(-1002).title, 'Wire');
  });

  test('the same channel in two accounts has a notification in each, named '
      'by its account; only the account in use can have its timeline in '
      'front', () async {
    final notifier = await start();
    notifier
      ..activeAccount = 1
      ..appOpen = true
      ..viewing = {chatId};
    await notifier.show(
      planFor(10, text: 'mine', account: 1, accountName: 'Ann'),
    );
    await notifier.show(
      planFor(10, text: 'theirs', account: 2, accountName: 'Bob'),
    );
    final mine = shade.of(chatId, account: 1);
    final theirs = shade.of(chatId, account: 2);
    expect(mine.id, isNot(theirs.id));
    expect(shade.live, {mine.id, theirs.id});
    expect(mine.header, 'Ann · r');
    expect(mine.texts, ['mine']);
    expect(theirs.header, 'Bob · r');
    expect(theirs.texts, ['theirs']);
    // The tap says which account the post is in.
    expect((mine.opens.account, theirs.opens.account), (1, 2));
    // The timeline on screen is the first account's: its post does not pop up over
    // it, the other account's does.
    expect(mine.channel, 'posts_normal_inapp');
    expect(theirs.channel, 'posts_normal_popup');

    // Each follows its own read position and keeps its own list.
    await notifier.cancelRead(chatId, 10, account: 2);
    expect(shade.cancelled, [theirs.id]);
    expect(notifier.listed(chatId, account: 1), hasLength(1));
    expect(notifier.listed(chatId, account: 2), isEmpty);

    // And both are found again after a restart of the host.
    later();
    final again = await start();
    expect(again.listed(chatId, account: 1).single.messageId, 10);
  });

  test('a new post sounds and pops up again; a silent one is added without, '
      'and leaves the notification on its channel', () async {
    final notifier = await start();
    await notifier.show(planFor(10));
    expect(shade.shown.last.alerts, isTrue);
    expect(shade.shown.last.channel, 'posts_normal_popup');

    later();
    await notifier.show(planFor(11, priority: RulePriority.silent));
    expect(shade.shown.last.alerts, isFalse);
    expect(shade.shown.last.channel, 'posts_normal_popup');
    expect(shade.shown.last.texts, hasLength(2));

    later();
    await notifier.show(planFor(12, priority: RulePriority.urgent));
    expect(shade.shown.last.alerts, isTrue);
    expect(shade.shown.last.channel, 'posts_urgent');

    // A channel whose first post is silent starts among the silent ones.
    await notifier.show(
      planFor(3, chatId: -1002, priority: RulePriority.silent),
    );
    expect(shade.of(-1002).channel, 'posts_silent');
  });

  test('the same post again takes the place of its line, and a post that '
      'matched late goes where it belongs', () async {
    final notifier = await start();
    await notifier.show(planFor(10, text: 'a'));
    await notifier.show(planFor(12, text: 'c'));
    later();
    await notifier.show(planFor(10, text: 'a, corrected'));
    await notifier.show(planFor(11, text: 'b'));
    expect(shade.shown.last.texts, ['a, corrected', 'b', 'c']);
  });

  test('a notification lists the newest posts, no more than Android keeps of '
      'a conversation', () async {
    final notifier = await start();
    for (var i = 1; i <= Notifier.maxListed + 5; i++) {
      await notifier.show(planFor(i, priority: RulePriority.silent));
    }
    final last = shade.shown.last;
    expect(last.lines, hasLength(Notifier.maxListed));
    expect(last.opens.messageId, 6);
  });

  test(
    'a notification that was swiped away or tapped starts a new list',
    () async {
      final notifier = await start();
      await notifier.show(planFor(10));
      await notifier.show(planFor(11));
      shade.swipe(chatId);
      later();
      await notifier.show(planFor(12, text: 'new'));
      expect(shade.shown.last.texts, ['new']);
      expect(shade.shown.last.opens.messageId, 12);

      // Told of the tap, the notifier forgets the list at once.
      await notifier.forget(chatId);
      expect(notifier.listed(chatId), isEmpty);
    },
  );

  test('a notification posted a moment ago counts though Android does not '
      'list it yet', () async {
    final notifier = await start();
    await notifier.show(planFor(10));
    shade.live.clear();
    await notifier.show(planFor(11));
    expect(shade.shown.last.texts, hasLength(2));
  });

  test('what the notifications list outlives a restart of their host; a '
      'notification that went meanwhile does not', () async {
    final first = await start();
    await first.show(planFor(10, text: 'before'));
    await first.show(planFor(11, text: 'before too'));
    later();

    final second = await start();
    expect(second.listed(chatId).map((r) => r.messageId), [10, 11]);
    await second.show(planFor(12, text: 'after'));
    expect(shade.shown.last.texts, ['before', 'before too', 'after']);

    shade.swipe(chatId);
    later();
    final third = await start();
    expect(third.listed(chatId), isEmpty);
  });

  test("the channel's photo is the face of the conversation, and a post's "
      'picture comes with its line', () async {
    final notifier = await start();
    await notifier.show(planFor(10, text: 'no picture'));
    expect(shade.shown.last.avatar, isNull);
    later();
    await notifier.show(
      planFor(
        11,
        text: 'with one',
      ).copyWith(avatar: '/cache/a.png', picture: 'content://files/p.jpg'),
    );
    var last = shade.shown.last;
    expect(last.avatar, '/cache/a.png');
    // The picture stands under the words of its post, as a line of its own.
    expect(last.texts, ['no picture', 'with one', 'with one']);
    expect(last.lines.map((l) => l.picture), [
      null,
      null,
      'content://files/p.jpg',
    ]);
    final person = (last.specifics['styleInformation'] as Map)['person'] as Map;
    expect(person['icon'], '/cache/a.png');
    expect(person['name'], 'News');

    // Only the newest post shows its picture: the older ones stay words.
    later();
    await notifier.show(planFor(12, text: 'newer'));
    last = shade.shown.last;
    expect(last.texts, ['no picture', 'with one', 'newer']);
    expect(last.lines.map((l) => l.picture).toSet(), {null});
    expect(last.avatar, '/cache/a.png');
  });

  test('a post that matched behind the lock is a line that says nothing, and '
      'the notification has no buttons', () async {
    final notifier = await start();
    await notifier.show(planFor(10, text: 'secret', hidden: true));
    var last = shade.shown.last;
    expect(last.title, appName);
    expect(last.texts, ['New post']);
    expect(last.lines.single.sender, appName);
    expect(last.buttons, isEmpty);
    expect(last.rule, isNull);

    // After a post that was shown openly the channel's name is on the screen anyway.
    later();
    await notifier.show(planFor(5, chatId: -1002, text: 'open', title: 'Wire'));
    later();
    await notifier.show(
      planFor(6, chatId: -1002, text: 'secret', hidden: true),
    );
    last = shade.of(-1002);
    expect(last.title, 'Wire');
    expect(last.texts, ['open', 'New post']);
    expect(last.lines.map((l) => l.sender), ['Wire', appName]);
    expect(last.buttons, isEmpty);
  });

  test('the buttons speak the interface language, and every notification '
      'names the status bar icon itself', () async {
    final notifier = Notifier(null, () => now, store);
    await notifier.init(strings: lookupAppLocalizations(const Locale('uk')));
    await notifier.show(planFor(10));
    final last = shade.shown.last;
    expect(
      [for (final a in last.specifics['actions'] as List) (a as Map)['title']],
      ['Відкрити в Telegram', 'Слухати'],
    );
    // The plugin's default icon lives in shared preferences, where the UI isolate's own
    // initialisation would otherwise decide it (the launcher icon, in colour).
    expect(last.icon, notificationIcon);
  });

  test('a caption is marked with what it is the caption of', () {
    const file = FileRef(id: 1, remoteId: 'r', size: 1);
    String body(Media? media, [String text = 'the caption']) =>
        planFor(10, text: text, media: media).body;
    expect(body(const PhotoMedia(sizes: [file])), '🖼 the caption');
    expect(
      body(const VideoMedia(file: file, durationSeconds: 5)),
      '📹 the caption',
    );
    expect(
      body(const VideoMedia(file: file, durationSeconds: 5, isAnimation: true)),
      '🎬 the caption',
    );
    expect(
      body(const DocumentMedia(file: file, fileName: 'a.pdf', mimeType: 'x/y')),
      '📎 the caption',
    );
    expect(body(null), 'the caption');
    // Without a caption the post is named by what it carries, unmarked.
    expect(body(const PhotoMedia(sizes: [file]), ''), 'Photo');
  });

  test('a line survives the file it is kept in', () {
    final line = planFor(
      10,
      text: 'words',
      rule: 'macro',
      priority: RulePriority.urgent,
    ).copyWith(avatar: '/a.png', picture: 'content://p', quiet: true);
    final back = NotificationPlan.fromJson(line.toJson())!;
    expect(back.toJson(), line.toJson());
    expect(back.ref.messageId, 10);
    expect(NotificationPlan.fromJson({'payload': 'nope'}), isNull);
    expect(NotificationPlan.fromJson('x'), isNull);
  });
}
