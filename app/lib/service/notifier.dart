import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';

import '../l10n/l10n.dart';
import 'notification_plan.dart';

export 'notification_plan.dart';

/// White glyph on transparency, the way Android wants a status bar icon: the system tints
/// it like every other app's. It is named on every notification, not left to the plugin's
/// default, because that default lives in shared preferences and the isolate that
/// initialises last would decide it.
const notificationIcon = 'ic_stat_feed';

/// Where the notifications' lists of posts are kept, so that a restart of their host
/// does not forget what Android still shows.
abstract interface class ListedStore {
  Future<String?> read();
  Future<void> write(String json);
}

/// A file among the app's own. Where there is none to be had (a test, a platform without
/// the directory) nothing is kept.
class ListedFile implements ListedStore {
  const ListedFile();

  Future<File> _file() async => File(
    '${(await getApplicationSupportDirectory()).path}/notifications_listed.json',
  );

  @override
  Future<String?> read() async {
    try {
      final file = await _file();
      return file.existsSync() ? await file.readAsString() : null;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(String json) async {
    try {
      await (await _file()).writeAsString(json, flush: true);
    } on Object catch (e) {
      debugPrint('notifier: list not kept: $e');
    }
  }
}

/// A channel in an account (`AccountInfo.id`; 0 where a post names none).
typedef _Chat = (int account, int chatId);

/// What one channel's notification holds.
class _Listed {
  /// The matched posts it lists, oldest first.
  final posts = <NotificationPlan>[];

  /// The Android channel it was posted on last.
  String androidChannel = channelSilent;

  /// Whether its button is Stop.
  bool stop = false;

  /// When it was posted last: Android may not list it yet a moment later.
  DateTime? postedAt;
}

/// Posts notifications for rule matches: one per channel, which lists the channel's
/// matched posts as a conversation. Lives in the service host isolate (plugins with
/// platform callbacks cannot run in the core isolate, spike P0-2).
final class Notifier {
  Notifier([
    FlutterLocalNotificationsPlugin? plugin,
    DateTime Function()? now,
    ListedStore? store,
  ]) : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       _now = now ?? DateTime.now,
       _store = store ?? const ListedFile();

  final FlutterLocalNotificationsPlugin _plugin;
  final DateTime Function() _now;
  final ListedStore _store;

  /// How many posts a notification lists; Android keeps no more of a conversation, and
  /// an older post leaves the list.
  static const maxListed = 25;

  /// How often one channel may sound and pop up within [soundWindow], as the official
  /// app's default for a chat: twice in three minutes. Further posts of it are shown
  /// quietly until the window has passed.
  static const soundLimit = 2;
  static const soundWindow = Duration(minutes: 3);

  /// When each channel's notification last sounded, oldest first.
  final _sounded = <_Chat, List<DateTime>>{};

  /// Whether a post of [chat] may sound now; counts it when it may.
  bool _maySound(_Chat chat) {
    final now = _now();
    final times = _sounded.putIfAbsent(chat, () => [])
      ..removeWhere((t) => now.difference(t) >= soundWindow);
    if (times.length >= soundLimit) return false;
    times.add(now);
    return true;
  }

  /// The notifications by account and channel: what each lists, where and with which
  /// button. The same channel in two accounts has a notification in each.
  final _chats = <_Chat, _Listed>{};

  /// The account in use: only its posts can be those of the timeline in front
  /// ([viewing]). 0 matches the posts that name no account.
  int activeAccount = 0;

  /// Ids ([NotificationPlan.idFor]) of the posts being read or waiting to be read.
  Set<int> _reading = const {};

  /// Whatever changes a notification runs one after the other: a post that matches
  /// while another is being shown must find that one in the list.
  Future<void> _turn = Future.value();

  Future<void> _inTurn(Future<void> Function() work) {
    final done = _turn.then((_) => work());
    _turn = done.catchError((Object e) {
      debugPrint('notifier: $e');
    });
    return done;
  }

  /// Sound and vibration the reader chose per priority (H-33). Android fixes a channel's
  /// sound when it is created, so a change means a channel under a new id and the old one
  /// deleted; [_tagOf] turns the choice into that id.
  NotificationSounds _sounds = const NotificationSounds();

  /// Channel ids in use, by the logical priority of the plan.
  final _actual = <String, String>{};

  /// The in-app channel ids in use, by the logical priority of the plan.
  final _actualInApp = <String, String>{};

  /// The interface language of the notifications and of the channels' names.
  AppLocalizations _strings = AppLanguage.englishStrings;

  /// Whether the app is on screen, and the channels of the timeline that is in front
  /// there. A post of one of those channels sounds and vibrates as its priority says but
  /// does not pop up over the timeline it has just appeared in; Android decides the
  /// pop-up by the channel, so it goes on the in-app channels. Any other post pops up
  /// over the app as it does outside it, as in the official app.
  bool appOpen = false;
  Set<int> viewing = const {};

  /// The suffix a choice gives a channel id. The default choice adds nothing, so only a
  /// reader who picks a sound gets channels of their own.
  String _suffixOf(String? sound, bool vibrate) {
    if ((sound ?? '').isEmpty && vibrate) return '';
    final words = '${sound ?? ''}|$vibrate';
    return '_${words.hashCode.toUnsigned(20).toRadixString(36)}';
  }

  Future<void> init({
    NotificationSounds sounds = const NotificationSounds(),
    AppLocalizations? strings,
  }) async {
    _sounds = sounds;
    if (strings != null) _strings = strings;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(notificationIcon),
      ),
      onDidReceiveNotificationResponse: notificationActionEntryPoint,
      onDidReceiveBackgroundNotificationResponse: notificationActionEntryPoint,
    );
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;
    await _createSilentChannel(android);
    _actual[channelSilent] = channelSilent;
    await setSounds(sounds);
    await _inTurn(() async {
      await _load();
      await _dropGone();
    });
  }

  /// What the notifications listed when the host last ran.
  Future<void> _load() async {
    final kept = await _store.read();
    if (kept == null) return;
    try {
      final chats = jsonDecode(kept) as Map<String, Object?>;
      for (final v in chats.values) {
        final m = v! as Map<String, Object?>;
        final listed = _Listed()
          ..androidChannel = m['channel'] as String
          ..stop = m['stop'] == true;
        for (final p in m['posts'] as List) {
          if (NotificationPlan.fromJson(p) case final plan?) {
            listed.posts.add(plan);
          }
        }
        if (listed.posts.isNotEmpty) {
          final ref = listed.posts.first.ref;
          _chats[(ref.account, ref.chatId)] = listed;
        }
      }
    } on Object catch (e) {
      debugPrint('notifier: kept list unreadable: $e');
    }
  }

  Future<void> _save() => _store.write(
    jsonEncode({
      for (final MapEntry(key: chat, value: listed) in _chats.entries)
        '${chat.$1}:${chat.$2}': {
          'channel': listed.androidChannel,
          'stop': listed.stop,
          'posts': [for (final p in listed.posts) p.toJson()],
        },
    }),
  );

  /// Forgets the notifications Android no longer shows: swiped away, tapped, or cleared
  /// with the others. One posted a moment ago stays: Android may not list it yet.
  Future<void> _dropGone() async {
    if (_chats.isEmpty) return;
    final active = await _active();
    if (active == null) return;
    final live = {for (final n in active) n.id};
    final now = _now();
    final before = _chats.length;
    _chats.removeWhere((chat, listed) {
      if (live.contains(NotificationPlan.idForChat(chat.$2, chat.$1))) {
        return false;
      }
      final at = listed.postedAt;
      return at == null || now.difference(at).abs() > _listedWithin;
    });
    if (_chats.length != before) await _save();
  }

  static const _listedWithin = Duration(seconds: 2);

  Future<void> _createSilentChannel(
    AndroidFlutterLocalNotificationsPlugin android,
  ) => android.createNotificationChannel(
    AndroidNotificationChannel(
      channelSilent,
      _strings.notifyChannelSilent,
      description: _strings.notifyChannelSilentDescription,
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
    ),
  );

  /// A change of the interface language: Android's settings list the channels under
  /// their new names, and later notifications use the new words.
  Future<void> setStrings(AppLocalizations strings) async {
    if (strings.localeName == _strings.localeName) return;
    _strings = strings;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;
    await _createSilentChannel(android);
    await setSounds(_sounds);
  }

  /// Applies the sound and vibration choices: channels under new ids where a choice
  /// changed, the channels of earlier choices deleted. Runs at start and whenever the
  /// user changes a choice, so a change needs no restart.
  Future<void> setSounds(NotificationSounds sounds) async {
    _sounds = sounds;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;
    final suffix = _suffixOf(sounds.normalSound, sounds.normalVibrate);
    for (final inApp in const [false, true]) {
      await android.createNotificationChannel(
        AndroidNotificationChannel(
          (inApp ? channelNormalInApp : channelNormalPopup) + suffix,
          channelNameOf(channelNormal, inApp: inApp, strings: _strings),
          description: inApp
              ? _strings.notifyChannelNormalInAppDescription
              : _strings.notifyChannelNormalDescription,
          importance: inApp ? Importance.defaultImportance : Importance.high,
          sound: (sounds.normalSound ?? '').isEmpty
              ? null
              : UriAndroidNotificationSound(sounds.normalSound!),
          enableVibration: sounds.normalVibrate,
        ),
      );
    }
    _actual[channelNormal] = channelNormalPopup + suffix;
    _actualInApp[channelNormal] = channelNormalInApp + suffix;
    // The urgent channel is made again for the new choice.
    _actual.remove(channelUrgent);
    await _ensureUrgentChannel();
    // One row per priority in the system settings: the channels of earlier choices go.
    await _deleteStaleChannels(android);
  }

  /// Channels of sounds the reader has moved on from; the ids in use are kept.
  Future<void> _deleteStaleChannels(
    AndroidFlutterLocalNotificationsPlugin android,
  ) async {
    final keep = {
      ..._actual.values,
      ..._actualInApp.values,
      channelSilent,
      _urgentId(),
      _urgentId(inApp: true),
    };
    final existing = await android.getNotificationChannels() ?? const [];
    for (final channel in existing) {
      final id = channel.id;
      if (keep.contains(id)) continue;
      if (!id.startsWith(channelNormal) && !id.startsWith(channelUrgent)) {
        continue;
      }
      await android.deleteNotificationChannel(channelId: id);
    }
  }

  /// Makes the urgent channels, the pop-up one and the in-app one, for the current policy
  /// access. Re-checked before every urgent notification so that granting policy access
  /// later takes effect without restarting the service.
  Future<void> _ensureUrgentChannel() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;
    final bypass = await android.hasNotificationPolicyAccess() ?? false;
    if (bypass == _urgentBypassesDnd &&
        _actual[channelUrgent] != null &&
        _urgentNamedIn == _strings.localeName) {
      return;
    }
    _urgentNamedIn = _strings.localeName;
    _urgentBypassesDnd = bypass;
    final suffix = _suffixOf(_sounds.urgentSound, _sounds.urgentVibrate);
    for (final inApp in const [false, true]) {
      await android.createNotificationChannel(
        AndroidNotificationChannel(
          _urgentId(inApp: inApp),
          channelNameOf(channelUrgent, inApp: inApp, strings: _strings),
          description: switch (inApp
              ? _strings.notifyChannelUrgentInAppDescription
              : _strings.notifyChannelUrgentDescription) {
            final d when bypass => _strings.notifyChannelBypassesDnd(d),
            final d => d,
          },
          importance: inApp ? Importance.defaultImportance : Importance.high,
          bypassDnd: bypass,
          sound: (_sounds.urgentSound ?? '').isEmpty
              ? null
              : UriAndroidNotificationSound(_sounds.urgentSound!),
          enableVibration: _sounds.urgentVibrate,
        ),
      );
      // One row per kind in the system settings, not two.
      await android.deleteNotificationChannel(
        channelId: _urgentBase(inApp: inApp, dnd: !bypass) + suffix,
      );
    }
    _actual[channelUrgent] = _urgentId();
  }

  bool? _urgentBypassesDnd;

  /// The language the urgent channels were last named in.
  String? _urgentNamedIn;

  static String _urgentBase({required bool inApp, required bool dnd}) =>
      switch ((inApp, dnd)) {
        (false, false) => channelUrgent,
        (false, true) => channelUrgentDnd,
        (true, false) => channelUrgentInApp,
        (true, true) => channelUrgentInAppDnd,
      };

  /// The urgent channel in use: the Do-Not-Disturb one when policy access was granted, and
  /// the sound the reader chose in its id, since Android fixes it at creation.
  String _urgentId({bool inApp = false}) =>
      _urgentBase(inApp: inApp, dnd: _urgentBypassesDnd ?? false) +
      _suffixOf(_sounds.urgentSound, _sounds.urgentVibrate);

  /// Whether an Android channel is one of the in-app ones, which do not pop up.
  static bool _isInApp(String channelId) =>
      channelId.startsWith(channelNormalInApp) ||
      channelId.startsWith(channelUrgentInApp);

  /// Normal and urgent posts pop up, unless the app is open; urgent ones differ by their
  /// sound and the Do Not Disturb bypass.
  static Importance _importanceOf(String planChannel, String channelId) =>
      planChannel == channelSilent
      ? Importance.low
      : _isInApp(channelId)
      ? Importance.defaultImportance
      : Importance.high;

  /// The name Android's own settings list a kind of rule notification under.
  static String channelNameOf(
    String planChannelId, {
    bool inApp = false,
    AppLocalizations? strings,
  }) {
    final s = strings ?? AppLanguage.englishStrings;
    return switch ((planChannelId, inApp)) {
      (channelSilent, _) => s.notifyChannelSilent,
      (channelUrgent, false) => s.notifyChannelUrgent,
      (channelUrgent, true) => s.notifyChannelUrgentInApp,
      (_, false) => s.notifyChannelNormal,
      (_, true) => s.notifyChannelNormalInApp,
    };
  }

  /// The Android channel a plan's notification goes on: an in-app one while the app is
  /// open. The reader's sound is in the channel's id, so the plan's priority is looked up.
  Future<String> _channelOf(NotificationPlan plan) async {
    if (plan.quiet) return _actual[channelSilent] ?? channelSilent;
    final ref = PostRef.decode(plan.payload);
    final inApp =
        appOpen &&
        plan.channelId != channelSilent &&
        ref != null &&
        (ref.account == 0 || ref.account == activeAccount) &&
        viewing.contains(ref.chatId);
    if (plan.channelId == channelUrgent) {
      await _ensureUrgentChannel();
      return _urgentId(inApp: inApp);
    }
    return (inApp ? _actualInApp : _actual)[plan.channelId] ?? plan.channelId;
  }

  /// The priority an Android channel stands for.
  static String _planChannelOf(String androidChannel) =>
      androidChannel.startsWith(channelUrgent)
      ? channelUrgent
      : androidChannel.startsWith(channelSilent)
      ? channelSilent
      : channelNormal;

  /// Adds a post to its channel's notification, which is shown with it as its newest
  /// line and sounds and pops up as the post's rule says. A post of a channel that has
  /// just sounded [soundLimit] times, and one of a silent rule, is added quietly.
  Future<void> show(NotificationPlan asked) => _inTurn(() async {
    final ref = PostRef.decode(asked.payload);
    if (ref == null) return;
    final chat = (ref.account, ref.chatId);
    final plan = asked.channelId == channelSilent || _maySound(chat)
        ? asked
        : asked.copyWith(quiet: true);
    await _dropGone();
    final shownBefore = _chats.containsKey(chat);
    final listed = _chats.putIfAbsent(chat, _Listed.new);
    listed.posts
      // The same post again takes the place of its line.
      ..removeWhere((p) => p.id == plan.id)
      ..add(plan)
      ..sort((a, b) => a.ref.messageId.compareTo(b.ref.messageId));
    if (listed.posts.length > maxListed) {
      listed.posts.removeRange(0, listed.posts.length - maxListed);
    }
    final alerts = plan.channelId != channelSilent && !plan.quiet;
    // A post that makes no sound leaves the notification on the channel it is on: put
    // on the silent one, a notification that popped up would sink among the silent ones.
    if (alerts || !shownBefore) listed.androidChannel = await _channelOf(plan);
    await _post(chat, alert: alerts);
  });

  /// Posts a channel's notification, first or again: the conversation of its matched
  /// posts under the channel's name and photo, each post with its time and its picture.
  /// Posted again without [alert] it makes no sound and does not pop up: a line was
  /// edited or went, or the button changed, Stop while one of its posts is read and
  /// Listen otherwise. A tap opens the oldest post it lists.
  Future<void> _post(_Chat chat, {required bool alert}) async {
    final listed = _chats[chat];
    if (listed == null || listed.posts.isEmpty) return;
    final (account, chatId) = chat;
    final posts = listed.posts;
    final newest = posts.last;
    // Named by the channel once one of its posts was shown openly.
    final named = posts.lastWhere((p) => !p.hidden, orElse: () => newest);
    final avatar = posts
        .lastWhere((p) => !p.hidden && p.avatar != null, orElse: () => newest)
        .avatar;
    final reading = posts.any((p) => _reading.contains(p.id));
    final channelId = listed.androidChannel;
    final priority = _planChannelOf(channelId);
    final header = [
      named.accountName,
      newest.rule,
    ].where((s) => s.isNotEmpty).join(' · ');
    Person sender(NotificationPlan p) => p.hidden
        ? Person(name: p.title, key: 'hidden')
        : Person(
            name: named.title,
            key: 'chat$account:$chatId',
            icon: avatar == null ? null : BitmapFilePathAndroidIcon(avatar),
          );
    await _plugin.show(
      id: NotificationPlan.idForChat(chatId, account),
      title: named.title,
      body: newest.body,
      payload: posts.first.payload,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          // A readable name: were the channel ever created from here, Android's own
          // settings would otherwise list "posts_normal_k3f9".
          channelNameOf(
            priority,
            inApp: _isInApp(channelId),
            strings: _strings,
          ),
          icon: notificationIcon,
          largeIcon: avatar == null ? null : FilePathAndroidBitmap(avatar),
          // The rule of the newest post, so the shade says why it is here, after the
          // account it matched in while several accounts notify.
          subText: header.isEmpty ? null : header,
          importance: _importanceOf(priority, channelId),
          when: newest.when,
          // A launcher that counts by notifications counts the posts, not the channels.
          number: posts.length,
          onlyAlertOnce: !alert,
          // Swiping it away reaches the service host, which stops reading its posts; a
          // tap or a cancellation is not reported.
          dismissIsolate: NotificationDismissedIsolate.background,
          styleInformation: MessagingStyleInformation(
            sender(named),
            // Android's header has no sub-text for a conversation; its title stands
            // there instead.
            conversationTitle: header.isEmpty ? null : header,
            groupConversation: false,
            messages: [
              for (final p in posts) ...[
                // The picture of the newest post, above its words, as a photo stands
                // above its caption. Android draws a line's picture in place of its
                // words and only the newest lines that fit, so the picture is a line
                // of its own that goes first when there is no room, and the older
                // posts stay words.
                if (identical(p, newest))
                  if (newest.picture case final picture?)
                    Message(
                      newest.body,
                      DateTime.fromMillisecondsSinceEpoch(newest.when ?? 0),
                      sender(newest),
                      dataMimeType: 'image/jpeg',
                      dataUri: picture,
                    ),
                Message(
                  p.body,
                  DateTime.fromMillisecondsSinceEpoch(p.when ?? 0),
                  sender(p),
                ),
              ],
            ],
          ),
          // The button that changes comes last, so the other one never moves. A
          // notification that hides a post has none: Listen would say it aloud.
          actions: posts.any((p) => p.hidden)
              ? const []
              : [
                  AndroidNotificationAction(
                    actionOpenTelegram,
                    _strings.commonOpenInTelegram,
                    showsUserInterface: true,
                    cancelNotification: true,
                  ),
                  reading
                      ? AndroidNotificationAction(
                          actionStop,
                          _strings.notifyStop,
                          cancelNotification: false,
                        )
                      : AndroidNotificationAction(
                          actionListen,
                          _strings.notifyListen,
                          cancelNotification: false,
                        ),
                ],
        ),
      ),
    );
    listed
      ..stop = reading
      ..postedAt = _now();
    await _save();
  }

  /// The posts a channel's notification lists, oldest first: what its Listen reads and
  /// its Stop stops.
  List<PostRef> listed(int chatId, {int account = 0}) => [
    for (final p
        in _chats[(account, chatId)]?.posts ?? const <NotificationPlan>[])
      p.ref,
  ];

  /// A listed post was edited: its line says the new words, where the notification is
  /// still shown. Posted again it makes no sound. Rules are not asked again: an edit
  /// neither raises nor takes back a notification.
  Future<void> updateBody(
    int chatId,
    int messageId,
    String body, {
    int account = 0,
  }) => _inTurn(() async {
    final chat = (account, chatId);
    final id = NotificationPlan.idFor(chatId, messageId);
    bool changes() {
      final at = _chats[chat]?.posts.indexWhere((p) => p.id == id) ?? -1;
      if (at < 0) return false;
      final line = _chats[chat]!.posts[at];
      // A line that hides its post goes on hiding it.
      return !line.hidden && line.body != body;
    }

    if (!changes()) return;
    // Dismissed or opened meanwhile: it stays gone.
    await _dropGone();
    if (!changes()) return;
    final posts = _chats[chat]!.posts;
    final at = posts.indexWhere((p) => p.id == id);
    posts[at] = posts[at].copyWith(body: body);
    await _post(chat, alert: false);
  });

  /// The posts being read or waiting to be read ([NotificationPlan.idFor]): the
  /// notifications that list one of them offer Stop, the others Listen. A notification
  /// the reader dismissed or opened stays gone.
  Future<void> setReading(Set<int> ids) {
    _reading = ids;
    return _inTurn(() async {
      bool wants(_Listed l) => l.posts.any((p) => _reading.contains(p.id));
      if (_chats.values.every((l) => l.stop == wants(l))) return;
      await _dropGone();
      for (final MapEntry(key: chat, value: l) in [..._chats.entries]) {
        if (l.stop != wants(l)) await _post(chat, alert: false);
      }
    }).catchError((Object e) {
      debugPrint('notifier: button change failed: $e');
    });
  }

  /// What Android shows of this app; null where it cannot say.
  Future<List<ActiveNotification>?> _active() async {
    try {
      return await _plugin.getActiveNotifications();
    } on PlatformException catch (e) {
      debugPrint('notifier: active notifications unavailable: $e');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Takes deleted posts out of their channel's notification (ARCHITECTURE 6.2); the
  /// notification goes with its last post.
  Future<void> cancel(int chatId, List<int> messageIds, {int account = 0}) =>
      _unlist((account, chatId), (ref) => messageIds.contains(ref.messageId));

  /// Takes the posts of [chatId] up to [upToMessageId] out of its notification: they
  /// were read, here or in the official app.
  Future<void> cancelRead(int chatId, int upToMessageId, {int account = 0}) =>
      _unlist((account, chatId), (ref) => ref.messageId <= upToMessageId);

  Future<void> _unlist(_Chat chat, bool Function(PostRef) gone) =>
      _inTurn(() async {
        if (!(_chats[chat]?.posts.any((p) => gone(p.ref)) ?? false)) return;
        await _dropGone();
        final listed = _chats[chat];
        if (listed == null) return;
        listed.posts.removeWhere((p) => gone(p.ref));
        if (listed.posts.isNotEmpty) return _post(chat, alert: false);
        _chats.remove(chat);
        await _plugin.cancel(id: NotificationPlan.idForChat(chat.$2, chat.$1));
        await _save();
      });

  /// The notification of [chatId] left the shade: swiped away, tapped, or opened in
  /// Telegram. What it listed is forgotten, so the next post starts a new list.
  Future<void> forget(int chatId, {int account = 0}) => _inTurn(() async {
    if (_chats.remove((account, chatId)) != null) await _save();
  });
}

/// Entry point for action taps and swipes. For background actions and swipes Android starts
/// a fresh isolate, so the response is forwarded to whoever registered [notifierPortName]
/// (the service host); for foreground taps the app's own handler also receives it through
/// the plugin.
@pragma('vm:entry-point')
void notificationActionEntryPoint(NotificationResponse response) {
  final port = IsolateNameServer.lookupPortByName(notifierPortName);
  if (port == null) {
    debugPrint('notifier: no host port for action ${response.actionId}');
    return;
  }
  port.send({
    'actionId': response.actionId,
    'payload': response.payload,
    'type': response.notificationResponseType.name,
  });
}
