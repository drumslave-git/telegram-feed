import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../ai/semantic_gate.dart';
import '../l10n/l10n.dart';
import '../settings/app_lock.dart' show AppLock;
import 'notification_pictures.dart';
import 'notifier.dart';
import 'read_aloud_keys.dart';
import 'reading_now.dart';
import 'tts_service.dart';

/// One account whose rule matches become notifications: what its core says, and its own
/// database, where its rules' channels are named.
final class AlertAccount {
  AlertAccount({
    required this.db,
    required this.matches,
    required this.postEvents,
    required this.history,
    this.readUpdates = const Stream.empty(),
    this.id = 0,
    this.name = '',
    this.pictures,
    this.gate,
  });

  /// The account served by the core at [client].
  AlertAccount.of(
    CoreClient client, {
    required AppDatabase db,
    int id = 0,
    String name = '',
  }) : this(
         db: db,
         matches: client.matches,
         postEvents: client.postEvents,
         readUpdates: client.readUpdates,
         history: (chatId, {required fromMessageId, required limit}) =>
             client.history(chatId, fromMessageId: fromMessageId, limit: limit),
         id: id,
         name: name,
         pictures: NotificationPictures(
           channels: client.myChannels,
           download: client.download,
         ),
       );

  /// `AccountInfo.id`; 0 where the alerts know of one account only (tests).
  final int id;

  /// The name of its profile, which stands on its notifications while several accounts
  /// notify.
  final String name;
  final AppDatabase db;
  final Stream<MatchEvent> matches;
  final Stream<PostEvent> postEvents;

  /// Every change of a channel's read position, here or in the official app.
  final Stream<ReadState> readUpdates;
  final Future<List<Post>> Function(
    int chatId, {
    required int fromMessageId,
    required int limit,
  })
  history;

  /// Where the channel's photo and a post's picture come from; none in most tests.
  final NotificationPictures? pictures;

  /// The AI check of its semantic rules; made on the first match unless handed in.
  SemanticGate? gate;

  /// The channels its rules watch, by id.
  Map<int, String> titles = const {};
}

/// What a rule match becomes: its notification, read-aloud, and the actions on both
/// (ARCHITECTURE 6.3 and 7). It lives where the plugins can run, beside the core it
/// listens to: in the service host, or in the app itself while background watching is
/// off. Every logged-in account notifies: the account in use and [others] share the
/// notifier, the speech queue and the settings of the account in use.
final class RuleAlerts {
  RuleAlerts({
    required this.db,
    required Stream<MatchEvent> matches,
    required Stream<PostEvent> postEvents,
    required this.pausedChanges,
    required Future<List<Post>> Function(
      int chatId, {
      required int fromMessageId,
      required int limit,
    })
    history,
    required this.onReading,
    Stream<ReadState> readUpdates = const Stream.empty(),
    this.onAction,
    NotificationPictures? pictures,
    Notifier? notifier,
    this.speaker,
    SemanticGate? gate,
    int account = 0,
    String accountName = '',
    this.others = const [],
    Future<bool> Function()? lockSet,
    ReadAloudKeys Function(void Function() onStop)? keys,
    void Function(String)? log,
  }) : _notifier = notifier ?? Notifier(),
       _lockSet = lockSet ?? (() => const AppLock().enabled),
       _makeKeys = keys ?? ((onStop) => ReadAloudKeys(onStop: onStop)),
       _log = log ?? ((s) => debugPrint('alerts: $s')),
       _main = AlertAccount(
         db: db,
         matches: matches,
         postEvents: postEvents,
         readUpdates: readUpdates,
         history: history,
         id: account,
         name: accountName,
         pictures: pictures,
         gate: gate,
       );

  /// Alerts on what the core at [client] matches, for the account in use, and on what
  /// the cores of [others] match.
  RuleAlerts.of(
    CoreClient client, {
    required AppDatabase db,
    required void Function(ReadingNow?) onReading,
    Future<void> Function()? onAction,
    int account = 0,
    String accountName = '',
    List<AlertAccount> others = const [],
    void Function(String)? log,
  }) : this(
         db: db,
         matches: client.matches,
         postEvents: client.postEvents,
         pausedChanges: client.pausedChanges,
         readUpdates: client.readUpdates,
         history: (chatId, {required fromMessageId, required limit}) =>
             client.history(chatId, fromMessageId: fromMessageId, limit: limit),
         onReading: onReading,
         onAction: onAction,
         pictures: NotificationPictures(
           channels: client.myChannels,
           download: client.download,
         ),
         account: account,
         accountName: accountName,
         others: others,
         log: log,
       );

  /// The database of the account in use: the sounds, the speech and the language are
  /// its settings.
  final AppDatabase db;
  final Stream<bool> pausedChanges;

  /// The account in use, and the other logged-in ones.
  final AlertAccount _main;
  final List<AlertAccount> others;
  late final List<AlertAccount> _accounts = [_main, ...others];

  /// The account [id] names; the one in use where it names none that is known.
  AlertAccount _accountOf(int id) =>
      _accounts.firstWhere((a) => a.id == id, orElse: () => _main);

  /// The post being read after every change, for the app's banner.
  final void Function(ReadingNow?) onReading;

  /// Runs before a notification's button is acted on.
  final Future<void> Function()? onAction;

  /// The speech engine; the app's own unless a test hands one in.
  final Speaker? speaker;

  final Notifier _notifier;
  final ReadAloudKeys Function(void Function() onStop) _makeKeys;
  final void Function(String) _log;
  final _actions = ReceivePort();
  final _subs = <StreamSubscription<void>>[];
  TtsService? _tts;
  ReadAloudKeys? _keys;
  AppLocalizations _strings = AppLanguage.englishStrings;

  /// Recent matched posts so the Listen action can find their text.
  final _recentTexts = <(int, int), String>{};

  /// The posts that were read aloud or queued for it: Listen on a notification reads
  /// the posts it lists that are not among them.
  final _spoken = <(int, int)>{};

  /// Whether the app is on screen: posts that match then do not pop up over it.
  set appOpen(bool open) => _notifier.appOpen = open;

  /// The channels of the timeline in front ([Notifier.viewing]).
  set viewing(Set<int> chatIds) => _notifier.viewing = chatIds;

  /// Whether the app has a lock; asked for every match, since the lock is set and
  /// removed in the app while these alerts run.
  final Future<bool> Function() _lockSet;

  /// The app is on screen and not behind its lock. While a lock is set and this does
  /// not hold, a notification says only that there is a new post: the phone may be in
  /// other hands. False until the app says otherwise.
  bool unlocked = false;

  Future<void> start(AppLocalizations strings) async {
    _strings = strings;
    _notifier.activeAccount = _main.id;
    await _notifier.init(sounds: await _sounds(), strings: strings);
    final tts = TtsService(db: db, speaker: speaker ?? FlutterTtsSpeaker());
    try {
      await tts.init();
      _tts = tts;
      _keys = _makeKeys(() {
        _log('read-aloud stopped by a key');
        unawaited(tts.stopAll());
      });
      _subs.add(tts.readingChanges.listen(_onReadingChanged));
    } catch (e) {
      _log('tts unavailable: $e');
    }
    // The pause is a kill switch: what is being read, and what waits, goes too.
    _subs.add(
      pausedChanges.listen((p) {
        if (p) unawaited(_tts?.stopAll());
      }),
    );
    IsolateNameServer.removePortNameMapping(notifierPortName);
    IsolateNameServer.registerPortWithName(_actions.sendPort, notifierPortName);
    _actions.listen(_onNotificationAction);
    for (final a in _accounts) {
      _subs.add(a.matches.listen((m) => _onMatch(a, m)));
      _subs.add(
        a.postEvents.listen((e) {
          if (e is PostsDeleted) {
            unawaited(_notifier.cancel(e.chatId, e.messageIds, account: a.id));
          } else if (e is PostEdited) {
            // The notification of an edited post says what the post says now.
            final post = e.post;
            if (_recentTexts.containsKey((post.chatId, post.messageId))) {
              _remember(post.chatId, post.messageId, post.text);
            }
            unawaited(
              _notifier.updateBody(
                post.chatId,
                post.messageId,
                NotificationPlan.bodyOf(post, _strings),
                account: a.id,
              ),
            );
          }
        }),
      );
      // A post that was read needs no notification any more.
      _subs.add(
        a.readUpdates.listen(
          (r) => unawaited(
            _notifier.cancelRead(r.chatId, r.lastReadMessageId, account: a.id),
          ),
        ),
      );
    }
    await reloadTitles();
  }

  Future<void> _onMatch(AlertAccount a, MatchEvent candidate) async {
    // AI semantic rules: the model decides before anything is shown. A check that cannot
    // be done skips those rules for this post; keyword rules on it still fire.
    final check = a.gate ??= SemanticGate(
      db: a.db,
      secrets: const SecureSecretStore(),
    );
    final m = await check.resolve(candidate);
    if (m == null) {
      _log(
        'no rule left for ${candidate.post.chatId}/${candidate.post.messageId}',
      );
      return;
    }
    _log('match ${m.ruleNames} on ${m.post.chatId}/${m.post.messageId}');
    if (!a.titles.containsKey(m.post.chatId)) await reloadTitles();
    final hidden = !unlocked && await _hasLock();
    var plan = NotificationPlan.forMatch(
      m,
      channelTitle: a.titles[m.post.chatId] ?? '',
      strings: _strings,
      hidden: hidden,
      account: a.id,
      // Said only while it tells accounts apart.
      accountName: others.isEmpty ? '' : a.name,
    );
    _remember(m.post.chatId, m.post.messageId, m.post.text);
    // Queued first, so the notification offers Stop from the start.
    if (m.readAloud) {
      unawaited(_speakPost(a, m.post.chatId, m.post.messageId));
    }
    // A notification that hides its post shows neither the channel's face nor a picture.
    if (a.pictures case final from? when !hidden) {
      final found = await from.of(m.post);
      plan = plan.copyWith(picture: found.picture, avatar: found.avatar);
    }
    await _notifier.show(plan);
  }

  Future<bool> _hasLock() async {
    try {
      return await _lockSet();
    } on Object catch (e) {
      // The keystore cannot be asked: what a post says is not shown on a guess.
      _log('lock state unknown: $e');
      return true;
    }
  }

  void _remember(int chatId, int messageId, String text) {
    _recentTexts[(chatId, messageId)] = text;
    if (_recentTexts.length > 200) _recentTexts.remove(_recentTexts.keys.first);
  }

  /// The "Listen" action and auto-read share this path (ARCHITECTURE 7). A post shown
  /// before these alerts last started is asked of the core; a remembered one is queued at
  /// once.
  Future<void> _speakPost(
    AlertAccount a,
    int chatId,
    int messageId, {
    bool next = false,
  }) async {
    final tts = _tts;
    if (tts == null) return;
    var text = _recentTexts[(chatId, messageId)];
    if (text == null) {
      text = await _fetchText(a, chatId, messageId);
      if (text == null) {
        _log('no text for $chatId/$messageId');
        return;
      }
      _remember(chatId, messageId, text);
    }
    _spoken.add((chatId, messageId));
    if (_spoken.length > 400) _spoken.remove(_spoken.first);
    tts.enqueue(
      TtsItem(
        text: text,
        channelTitle: a.titles[chatId],
        key: (chatId, messageId),
      ),
      next: next,
    );
  }

  Future<String?> _fetchText(AlertAccount a, int chatId, int messageId) async {
    try {
      final posts = await a.history(
        chatId,
        fromMessageId: messageId + 1,
        limit: 1,
      );
      return posts.firstOrNull?.messageId == messageId
          ? posts.first.text
          : null;
    } on Object catch (e) {
      _log('post $chatId/$messageId unavailable: $e');
      return null;
    }
  }

  /// A channel's notification offers Stop while one of its posts is read or waits to be,
  /// the app's banner names the post being read, and volume down stops it all.
  void _onReadingChanged(Set<Object> keys) {
    unawaited(_keys?.watch(keys.isNotEmpty));
    unawaited(
      _notifier.setReading({
        for (final k in keys)
          if (k case (final int chatId, final int messageId))
            NotificationPlan.idFor(chatId, messageId),
      }),
    );
    publishReading();
  }

  /// Tells the app what is being read.
  void publishReading() {
    final tts = _tts;
    onReading(switch (tts?.current) {
      (final int chatId, final int messageId) => ReadingNow(
        chatId: chatId,
        messageId: messageId,
        channelTitle: _titleOf(chatId),
        waiting: tts!.reading.length - 1,
      ),
      _ => null,
    });
  }

  /// The channels the rules watch, by id, read again for every account; returns how
  /// many there are.
  Future<int> reloadTitles() async {
    var count = 0;
    for (final a in _accounts) {
      try {
        a.titles = {for (final w in await a.db.allWatched()) w.chatId: w.title};
        count += a.titles.length;
      } on Object catch (e) {
        _log('channels of account ${a.id} not read: $e');
      }
    }
    return count;
  }

  /// What a channel is called, in whichever account watches it.
  String _titleOf(int chatId) {
    for (final a in _accounts) {
      if (a.titles[chatId] case final title?) return title;
    }
    return '';
  }

  Future<void> _onNotificationAction(Object? msg) async {
    final m = msg as Map<Object?, Object?>;
    final ref = PostRef.decode(m['payload'] as String?);
    final dismissed =
        m['type'] == NotificationResponseType.notificationDismissed.name;
    _log(
      'notification ${dismissed ? 'dismissed' : 'action ${m['actionId']}'} '
      'on ${ref?.chatId}/${ref?.messageId}',
    );
    if (ref == null) return;
    final account = _accountOf(ref.account);
    // The posts the channel's notification lists, oldest first; the one of the payload
    // for a notification nothing is known of any more.
    final listed = switch (_notifier.listed(ref.chatId, account: ref.account)) {
      final posts when posts.isNotEmpty => posts,
      _ => [ref],
    };
    // A notification swiped away is not read any more, as with its Stop, and what it
    // listed is forgotten.
    if (dismissed) {
      unawaited(_stopPosts(listed));
      unawaited(_notifier.forget(ref.chatId, account: ref.account));
      return;
    }
    // A tap opened the post in the app, and Android took the notification away.
    if (m['type'] == notificationTapped) {
      unawaited(_notifier.forget(ref.chatId, account: ref.account));
      return;
    }
    await onAction?.call();
    if (m['actionId'] == actionListen) {
      // The listed posts that were not read yet, oldest first; all of them when every
      // one was.
      final unheard = [
        for (final p in listed)
          if (!_spoken.contains((p.chatId, p.messageId))) p,
      ];
      final wanted = unheard.isEmpty ? listed : unheard;
      // With nothing being read the first one starts at once. The others are each put
      // at the head of the queue, so the last one first.
      final first = _tts?.current == null ? wanted.first : null;
      if (first != null) {
        await _speakPost(account, first.chatId, first.messageId, next: true);
      }
      for (final p in wanted.reversed) {
        if (identical(p, first)) continue;
        await _speakPost(account, p.chatId, p.messageId, next: true);
      }
    }
    if (m['actionId'] == actionStop) unawaited(_stopPosts(listed));
    // Taps and "Open in Telegram" are handled by the app (notification_launch.dart).
  }

  Future<void> _stopPosts(List<PostRef> posts) async {
    for (final p in posts) {
      await _tts?.stop((p.chatId, p.messageId));
    }
  }

  /// Stops reading one post; the next waiting one follows.
  Future<void> stop(int chatId, int messageId) async =>
      _tts?.stop((chatId, messageId));

  /// Stops the post being read and clears the queue.
  Future<void> stopAll() async => _tts?.stopAll();

  /// A change of the interface language: later notifications and the channels' names in
  /// Android's settings follow.
  Future<void> setStrings(AppLocalizations strings) {
    _strings = strings;
    return _notifier.setStrings(strings);
  }

  /// The rule sounds and vibrations changed in the settings.
  Future<void> reloadSounds() async => _notifier.setSounds(await _sounds());

  Future<NotificationSounds> _sounds() async => NotificationSounds(
    normalSound: await db.setting(SettingKeys.normalSound),
    urgentSound: await db.setting(SettingKeys.urgentSound),
    normalVibrate: (await db.setting(SettingKeys.normalVibrate)) != 'false',
    urgentVibrate: (await db.setting(SettingKeys.urgentVibrate)) != 'false',
  );

  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _keys?.watch(false);
    await _tts?.dispose();
    IsolateNameServer.removePortNameMapping(notifierPortName);
    _actions.close();
  }
}
