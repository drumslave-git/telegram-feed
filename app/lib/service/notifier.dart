import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../l10n/l10n.dart';
import 'notification_plan.dart';

export 'notification_plan.dart';

/// White glyph on transparency, the way Android wants a status bar icon: the system tints
/// it like every other app's. It is named on every notification, not left to the plugin's
/// default, because that default lives in shared preferences and the isolate that
/// initialises last would decide it.
const notificationIcon = 'ic_stat_feed';

/// Posts notifications for rule matches. Lives in the service host isolate (plugins with
/// platform callbacks cannot run in the core isolate, spike P0-2).
final class Notifier {
  Notifier([FlutterLocalNotificationsPlugin? plugin, DateTime Function()? now])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
      _now = now ?? DateTime.now;

  final FlutterLocalNotificationsPlugin _plugin;
  final DateTime Function() _now;

  /// How often one channel may sound and pop up within [soundWindow], as the official
  /// app's default for a chat: twice in three minutes. Further posts of it are shown
  /// quietly until the window has passed.
  static const soundLimit = 2;
  static const soundWindow = Duration(minutes: 3);

  /// When each chat's notifications last sounded, oldest first.
  final _sounded = <int, List<DateTime>>{};

  /// Whether a post of [chatId] may sound now; counts it when it may.
  bool _maySound(int chatId) {
    final now = _now();
    final times = _sounded.putIfAbsent(chatId, () => [])
      ..removeWhere((t) => now.difference(t) >= soundWindow);
    if (times.length >= soundLimit) return false;
    times.add(now);
    return true;
  }

  /// The last post shown per chat; only its title and channel are reused, to re-post that
  /// chat's group summary after a cancellation.
  final _lastPerChat = <int, NotificationPlan>{};

  /// Post notifications by id and whether each offers Stop, so a change of the button
  /// posts the same notification again. Bounded like the service's remembered texts.
  final _shown = <int, ({NotificationPlan plan, bool reading})>{};

  /// Notification ids whose post is being read or waits to be read.
  Set<int> _reading = const {};

  /// Button changes run one after the other, each towards the latest [_reading].
  Future<void> _buttons = Future.value();

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
  }

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

  /// The priority Android 7 goes by, which has no channels.
  static Priority _priorityOf(String planChannel, String channelId) =>
      planChannel == channelSilent
      ? Priority.low
      : _isInApp(channelId)
      ? Priority.defaultPriority
      : Priority.high;

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
    final inApp =
        appOpen &&
        plan.channelId != channelSilent &&
        viewing.contains(PostRef.decode(plan.payload)?.chatId);
    if (plan.channelId == channelUrgent) {
      await _ensureUrgentChannel();
      return _urgentId(inApp: inApp);
    }
    return (inApp ? _actualInApp : _actual)[plan.channelId] ?? plan.channelId;
  }

  /// Shows a post. One already queued for reading aloud offers Stop from the start. A
  /// post of a channel that has just sounded [soundLimit] times is shown quietly.
  Future<void> show(NotificationPlan asked) async {
    final chat = PostRef.decode(asked.payload)?.chatId;
    final plan =
        asked.channelId == channelSilent || chat == null || _maySound(chat)
        ? asked
        : asked.copyWith(quiet: true);
    final channelId = await _channelOf(plan);
    await _post(plan, channelId, reading: _reading.contains(plan.id));
    final chatId = PostRef.decode(plan.payload)?.chatId;
    if (chatId != null) _lastPerChat[chatId] = plan;
    final live = await _liveInGroup(plan.groupKey, plan.summaryId);
    // The post just shown counts even when Android has not listed it yet.
    live.add(plan.id);
    await _showSummary(plan, channelId, live.length);
  }

  /// Posts a post's notification, first or again. Posted again it keeps its time and
  /// makes no sound: only the button differs, Stop while the post is read and Listen
  /// otherwise. Neither button takes the notification away.
  Future<void> _post(
    NotificationPlan plan,
    String channelId, {
    required bool reading,
  }) async {
    await _plugin.show(
      id: plan.id,
      title: plan.title,
      body: plan.body,
      payload: plan.payload,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          // What Android gives back of a notification it shows: the tag, not the payload.
          // So the tag says which post this is.
          tag: plan.payload,
          // A readable name: were the channel ever created from here, Android's own
          // settings would otherwise list "posts_normal_k3f9".
          channelNameOf(
            plan.channelId,
            inApp: _isInApp(channelId),
            strings: _strings,
          ),
          icon: notificationIcon,
          subText: plan.rule.isEmpty ? null : plan.rule,
          importance: _importanceOf(
            plan.quiet ? channelSilent : plan.channelId,
            channelId,
          ),
          priority: _priorityOf(
            plan.quiet ? channelSilent : plan.channelId,
            channelId,
          ),
          groupKey: plan.groupKey,
          when: plan.when,
          onlyAlertOnce: true,
          // Swiping it away reaches the service host, which stops reading the post; a
          // tap or a cancellation is not reported.
          dismissIsolate: NotificationDismissedIsolate.background,
          styleInformation: BigTextStyleInformation(plan.body),
          // The button that changes comes last, so the other one never moves. A
          // notification that hides its post has none: Listen would say it aloud.
          actions: plan.hidden
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
    _shown.remove(plan.id);
    _shown[plan.id] = (plan: plan, reading: reading);
    if (_shown.length > 200) _shown.remove(_shown.keys.first);
  }

  /// The post of a notification was edited: the notification says the new words, where
  /// it is still shown. Posted again it makes no sound and keeps its time and place.
  /// Rules are not asked again: an edit neither raises nor takes back a notification.
  Future<void> updateBody(int chatId, int messageId, String body) async {
    final id = NotificationPlan.idFor(chatId, messageId);
    final shown = _shown[id];
    // A notification that hides its post goes on hiding it.
    if (shown == null || shown.plan.hidden || shown.plan.body == body) return;
    final active = await _active();
    // Dismissed or opened meanwhile: it stays gone.
    if (active != null && !active.any((n) => n.id == id)) {
      _shown.remove(id);
      return;
    }
    final plan = shown.plan.copyWith(body: body);
    await _post(plan, await _channelOf(plan), reading: shown.reading);
    if (_lastPerChat[chatId]?.id == id) _lastPerChat[chatId] = plan;
  }

  /// The posts being read or waiting to be read, by notification id: their notifications
  /// offer Stop, the others Listen. A notification the reader dismissed or opened stays
  /// gone.
  Future<void> setReading(Set<int> ids) {
    _reading = ids;
    return _buttons = _buttons.then((_) => _applyReading()).catchError((
      Object e,
    ) {
      debugPrint('notifier: button change failed: $e');
    });
  }

  Future<void> _applyReading() async {
    final active = await _active();
    if (active == null) return;
    final live = {for (final n in active) n.id};
    // Notifications posted before the service last started are known from Android.
    for (final n in active) {
      final id = n.id;
      if (id == null || _shown.containsKey(id) || !_reading.contains(id)) {
        continue;
      }
      final plan = NotificationPlan.restore(
        id: id,
        androidChannelId: n.channelId ?? '',
        title: n.title ?? '',
        body: n.body ?? '',
        groupKey: n.groupKey ?? '',
        payload: _payloadOf(n),
      );
      if (plan != null) _shown[id] = (plan: plan, reading: false);
    }
    for (final MapEntry(key: id, value: s) in [..._shown.entries]) {
      final want = _reading.contains(id);
      if (s.reading == want) continue;
      if (!live.contains(id)) {
        _shown.remove(id);
        continue;
      }
      await _post(s.plan, await _channelOf(s.plan), reading: want);
    }
  }

  /// What Android shows of this app; null where it cannot say (below Android 6.0).
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

  /// Group summary per channel so several posts collapse into one row. Only the posts
  /// alert: the pop-up shows the new post with its buttons, not the whole group, and a
  /// summary posted again after a cancellation makes no sound.
  Future<void> _showSummary(
    NotificationPlan plan,
    String channelId,
    int count,
  ) => _summary(
    summaryId: plan.summaryId,
    title: plan.title,
    groupKey: plan.groupKey,
    planChannel: plan.channelId,
    androidChannel: channelId,
    count: count,
  );

  Future<void> _summary({
    required int summaryId,
    required String title,
    required String groupKey,
    required String planChannel,
    required String androidChannel,
    required int count,
  }) => _plugin.show(
    id: summaryId,
    title: title,
    body: _strings.notifyNewPosts(count),
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        androidChannel,
        androidChannel,
        icon: notificationIcon,
        importance: _importanceOf(planChannel, androidChannel),
        priority: _priorityOf(planChannel, androidChannel),
        groupKey: groupKey,
        setAsGroupSummary: true,
        groupAlertBehavior: GroupAlertBehavior.children,
      ),
    ),
  );

  /// Ids of a group's post notifications that Android still holds, the summary excluded.
  ///
  /// The summary's count is asked of Android rather than tallied: posts the user swiped
  /// away, tapped or had deleted must not keep inflating "N new posts".
  Future<Set<int>> _liveInGroup(String groupKey, int summaryId) async => {
    // Where Android cannot say, the count covers the post being shown alone.
    for (final n in await _active() ?? const <ActiveNotification>[])
      if (n.groupKey == groupKey && n.id != null && n.id != summaryId) n.id!,
  };

  /// Drops notifications for deleted posts (ARCHITECTURE 6.2: cancel on delete), and keeps
  /// the group summary honest: it goes when the last post of its channel does.
  Future<void> cancel(int chatId, List<int> messageIds) async {
    final gone = <int>{};
    // A notification is cancelled under the tag it was posted with.
    final tags = {
      for (final n in await _active() ?? const <ActiveNotification>[])
        if (n.id != null) n.id!: n.tag,
    };
    for (final id in messageIds) {
      final notificationId = NotificationPlan.idFor(chatId, id);
      final tag = _shown[notificationId]?.plan.payload ?? tags[notificationId];
      _shown.remove(notificationId);
      gone.add(notificationId);
      await _plugin.cancel(id: notificationId, tag: tag);
    }
    await recount(chatId, gone: gone);
  }

  /// Takes away the notifications of the posts of [chatId] up to [upToMessageId]: they
  /// were read, here or in the official app. Android is asked which ones it shows, so
  /// notifications from before this notifier started go as well.
  Future<void> cancelRead(int chatId, int upToMessageId) async {
    final active = await _active();
    if (active == null) return;
    final gone = <int>{};
    for (final n in active) {
      final id = n.id;
      if (id == null || n.groupKey != _groupOf(chatId)) continue;
      final ref = PostRef.decode(_payloadOf(n));
      if (ref == null ||
          ref.chatId != chatId ||
          ref.messageId > upToMessageId) {
        continue;
      }
      _shown.remove(id);
      gone.add(id);
      await _plugin.cancel(id: id, tag: n.tag);
    }
    if (gone.isNotEmpty) await recount(chatId, gone: gone);
  }

  static String _groupOf(int chatId) => 'chat-$chatId';

  /// The payload of a notification Android shows: its tag, which carries it; the payload
  /// itself where a platform reports one.
  static String _payloadOf(ActiveNotification n) => n.tag ?? n.payload ?? '';

  /// Sets "N new posts" of a channel's group to what Android still shows of it, after a
  /// post left the shade: deleted, read, swiped away or tapped. [gone] names notifications
  /// that were cancelled a moment ago and Android may still list. The summary goes with
  /// the last post.
  Future<void> recount(int chatId, {Set<int> gone = const {}}) async {
    final active = await _active();
    if (active == null) return;
    final summaryId = NotificationPlan.summaryIdFor(chatId);
    ActiveNotification? summary;
    final live = <ActiveNotification>[];
    for (final n in active) {
      if (n.groupKey != _groupOf(chatId) || n.id == null) continue;
      if (n.id == summaryId) {
        summary = n;
      } else if (!gone.contains(n.id)) {
        live.add(n);
      }
    }
    final last = _lastPerChat[chatId];
    if (live.isEmpty) {
      _lastPerChat.remove(chatId);
      if (summary != null || last != null) await _plugin.cancel(id: summaryId);
      return;
    }
    // The channel the group is on: the summary's, as Android reports it, or that of a
    // post still there.
    final androidChannel =
        summary?.channelId ?? live.first.channelId ?? channelSilent;
    await _summary(
      summaryId: summaryId,
      title: last?.title ?? summary?.title ?? live.first.title ?? '',
      groupKey: _groupOf(chatId),
      planChannel: androidChannel.startsWith(channelUrgent)
          ? channelUrgent
          : androidChannel.startsWith(channelSilent)
          ? channelSilent
          : channelNormal,
      androidChannel: androidChannel,
      count: live.length,
    );
  }
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
