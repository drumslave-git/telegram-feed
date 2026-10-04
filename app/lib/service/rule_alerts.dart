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
import 'notifier.dart';
import 'read_aloud_keys.dart';
import 'reading_now.dart';
import 'tts_service.dart';

/// What a rule match becomes: its notification, read-aloud, and the actions on both
/// (ARCHITECTURE 6.3 and 7). It lives where the plugins can run, beside the core it
/// listens to: in the service host, or in the app itself while background watching is off.
final class RuleAlerts {
  RuleAlerts({
    required this.db,
    required this.matches,
    required this.postEvents,
    required this.pausedChanges,
    required this.history,
    required this.onReading,
    this.readUpdates = const Stream.empty(),
    this.onAction,
    Notifier? notifier,
    this.speaker,
    this.gate,
    ReadAloudKeys Function(void Function() onStop)? keys,
    void Function(String)? log,
  }) : _notifier = notifier ?? Notifier(),
       _makeKeys = keys ?? ((onStop) => ReadAloudKeys(onStop: onStop)),
       _log = log ?? ((s) => debugPrint('alerts: $s'));

  /// Alerts on what the core at [client] matches.
  RuleAlerts.of(
    CoreClient client, {
    required AppDatabase db,
    required void Function(ReadingNow?) onReading,
    Future<void> Function()? onAction,
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
         log: log,
       );

  final AppDatabase db;
  final Stream<MatchEvent> matches;
  final Stream<PostEvent> postEvents;
  final Stream<bool> pausedChanges;

  /// Every change of a channel's read position, here or in the official app.
  final Stream<ReadState> readUpdates;
  final Future<List<Post>> Function(
    int chatId, {
    required int fromMessageId,
    required int limit,
  })
  history;

  /// The post being read after every change, for the app's banner.
  final void Function(ReadingNow?) onReading;

  /// Runs before a notification's button is acted on.
  final Future<void> Function()? onAction;

  /// The speech engine and the AI check; the app's own unless a test hands them in.
  final Speaker? speaker;
  SemanticGate? gate;

  final Notifier _notifier;
  final ReadAloudKeys Function(void Function() onStop) _makeKeys;
  final void Function(String) _log;
  final _actions = ReceivePort();
  final _subs = <StreamSubscription<void>>[];
  TtsService? _tts;
  ReadAloudKeys? _keys;
  Map<int, String> _titles = const {};
  AppLocalizations _strings = AppLanguage.englishStrings;

  /// Recent matched posts so the Listen action can find their text.
  final _recentTexts = <(int, int), String>{};

  /// Whether the app is on screen: posts that match then do not pop up over it.
  set appOpen(bool open) => _notifier.appOpen = open;

  Future<void> start(AppLocalizations strings) async {
    _strings = strings;
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
    _subs.add(matches.listen(_onMatch));
    _subs.add(
      postEvents.listen((e) {
        if (e is PostsDeleted) {
          unawaited(_notifier.cancel(e.chatId, e.messageIds));
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
            ),
          );
        }
      }),
    );
    // A post that was read needs no notification any more.
    _subs.add(
      readUpdates.listen(
        (r) => unawaited(_notifier.cancelRead(r.chatId, r.lastReadMessageId)),
      ),
    );
    await reloadTitles();
  }

  Future<void> _onMatch(MatchEvent candidate) async {
    // AI semantic rules: the model decides before anything is shown. A check that cannot
    // be done skips those rules for this post; keyword rules on it still fire.
    final check = gate ??= SemanticGate(
      db: db,
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
    if (!_titles.containsKey(m.post.chatId)) await reloadTitles();
    final plan = NotificationPlan.forMatch(
      m,
      channelTitle: _titles[m.post.chatId] ?? '',
      strings: _strings,
    );
    _remember(m.post.chatId, m.post.messageId, m.post.text);
    // Queued first, so the notification offers Stop from the start.
    if (m.readAloud) unawaited(_speakPost(m.post.chatId, m.post.messageId));
    await _notifier.show(plan);
  }

  void _remember(int chatId, int messageId, String text) {
    _recentTexts[(chatId, messageId)] = text;
    if (_recentTexts.length > 200) _recentTexts.remove(_recentTexts.keys.first);
  }

  /// The "Listen" action and auto-read share this path (ARCHITECTURE 7). A post shown
  /// before these alerts last started is asked of the core; a remembered one is queued at
  /// once.
  Future<void> _speakPost(
    int chatId,
    int messageId, {
    bool next = false,
  }) async {
    final tts = _tts;
    if (tts == null) return;
    var text = _recentTexts[(chatId, messageId)];
    if (text == null) {
      text = await _fetchText(chatId, messageId);
      if (text == null) {
        _log('no text for $chatId/$messageId');
        return;
      }
      _remember(chatId, messageId, text);
    }
    tts.enqueue(
      TtsItem(
        text: text,
        channelTitle: _titles[chatId],
        key: (chatId, messageId),
      ),
      next: next,
    );
  }

  Future<String?> _fetchText(int chatId, int messageId) async {
    try {
      final posts = await history(
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

  /// A post's notification offers Stop while the post is read or waits to be, the app's
  /// banner names the post being read, and volume down stops it all.
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
        channelTitle: _titles[chatId] ?? '',
        waiting: tts!.reading.length - 1,
      ),
      _ => null,
    });
  }

  /// The channels the rules watch, by id, read again; returns how many there are.
  Future<int> reloadTitles() async {
    final watched = await db.allWatched();
    _titles = {for (final w in watched) w.chatId: w.title};
    return _titles.length;
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
    final id = NotificationPlan.idFor(ref.chatId, ref.messageId);
    // A post swiped away is not read any more, as with its Stop, and its channel's
    // "N new posts" counts one fewer.
    if (dismissed) {
      unawaited(_tts?.stop((ref.chatId, ref.messageId)));
      unawaited(_notifier.recount(ref.chatId, gone: {id}));
      return;
    }
    // A tap opened the post in the app, and Android took the notification away.
    if (m['type'] == notificationTapped) {
      unawaited(_notifier.recount(ref.chatId, gone: {id}));
      return;
    }
    await onAction?.call();
    if (m['actionId'] == actionListen) {
      unawaited(_speakPost(ref.chatId, ref.messageId, next: true));
    }
    if (m['actionId'] == actionStop) {
      unawaited(_tts?.stop((ref.chatId, ref.messageId)));
    }
    // Taps and "Open in Telegram" are handled by the app (notification_launch.dart).
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
