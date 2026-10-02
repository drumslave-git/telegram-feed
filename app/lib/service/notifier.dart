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
  Notifier([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

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

  /// Whether the app is on screen. Posts that match then sound and vibrate as their
  /// priority says but do not pop up over it; Android decides the pop-up by the channel, so
  /// they go on the in-app channels.
  bool appOpen = false;

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
    final inApp = appOpen && plan.channelId != channelSilent;
    if (plan.channelId == channelUrgent) {
      await _ensureUrgentChannel();
      return _urgentId(inApp: inApp);
    }
    return (inApp ? _actualInApp : _actual)[plan.channelId] ?? plan.channelId;
  }

  /// Shows a post. One already queued for reading aloud offers Stop from the start.
  Future<void> show(NotificationPlan plan) async {
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
          // A readable name: were the channel ever created from here, Android's own
          // settings would otherwise list "posts_normal_k3f9".
          channelNameOf(
            plan.channelId,
            inApp: _isInApp(channelId),
            strings: _strings,
          ),
          icon: notificationIcon,
          subText: plan.rule.isEmpty ? null : plan.rule,
          importance: _importanceOf(plan.channelId, channelId),
          priority: _priorityOf(plan.channelId, channelId),
          groupKey: plan.groupKey,
          when: plan.when,
          onlyAlertOnce: true,
          styleInformation: BigTextStyleInformation(plan.body),
          // The button that changes comes last, so the other one never moves.
          actions: [
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
        payload: n.payload ?? '',
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
  ) => _plugin.show(
    id: plan.summaryId,
    title: plan.title,
    body: _strings.notifyNewPosts(count),
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelId,
        icon: notificationIcon,
        importance: _importanceOf(plan.channelId, channelId),
        priority: _priorityOf(plan.channelId, channelId),
        groupKey: plan.groupKey,
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
    for (final id in messageIds) {
      final notificationId = NotificationPlan.idFor(chatId, id);
      _shown.remove(notificationId);
      await _plugin.cancel(id: notificationId);
    }
    final plan = _lastPerChat[chatId];
    if (plan == null) return;
    final live = await _liveInGroup(plan.groupKey, plan.summaryId);
    if (live.isEmpty) {
      _lastPerChat.remove(chatId);
      await _plugin.cancel(id: plan.summaryId);
      return;
    }
    await _showSummary(
      plan,
      plan.channelId == channelUrgent
          ? _urgentId()
          : _actual[plan.channelId] ?? plan.channelId,
      live.length,
    );
  }
}

/// Entry point for action taps. For background actions Android starts a fresh isolate, so
/// the response is forwarded to whoever registered [notifierPortName] (the service host);
/// for foreground taps the app's own handler also receives it through the plugin.
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
