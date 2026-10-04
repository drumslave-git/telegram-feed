import 'dart:convert';

import 'package:core/core.dart';
import 'package:telegram_gateway/telegram_gateway.dart' show Post;

import '../app_name.dart';
import '../l10n/l10n.dart';

/// Notification channels (ARCHITECTURE.md section 6.3), one per rule priority.
const channelSilent = 'posts_silent';
const channelNormal = 'posts_normal';
const channelUrgent = 'posts_urgent';

/// The Android channel of normal rules, which pops up. Android keeps the importance a
/// channel was created with, and phones may hold a `posts_normal` channel that does not
/// pop up, so that id is not reused; [Notifier] deletes it.
const channelNormalPopup = 'posts_normal_popup';

/// Channels of posts that match while the app is open: the sound and vibration of their
/// priority without the pop-up. Silent posts do not pop up anyway.
const channelNormalInApp = 'posts_normal_inapp';
const channelUrgentInApp = 'posts_urgent_inapp';
const channelUrgentInAppDnd = 'posts_urgent_inapp_dnd';

/// Urgent channel that bypasses Do Not Disturb. Android fixes a channel's DND bypass when
/// the channel is created, and only honours it if the app already has notification policy
/// access, so this second channel is created once access is granted ([Notifier]).
const channelUrgentDnd = 'posts_urgent_dnd';

/// Action ids on post notifications. A post being read, or waiting to be, offers Stop
/// where the others offer Listen.
const actionListen = 'listen';
const actionStop = 'stop';
const actionOpenTelegram = 'open_tg';

/// What the app sends the service host with `FlutterForegroundTask.sendDataToTask` when
/// its screen comes up or goes away ([Notifier.appOpen]), when its lock screen comes up
/// or goes ([unlocked]: on screen and not behind the lock), and when another timeline is
/// in front ([viewing]: the channels it reads, `Viewing`).
Map<String, Object> appOpenMessage(
  bool open, {
  bool unlocked = false,
  Iterable<int> viewing = const [],
}) => {
  'appOpen': open,
  'unlocked': open && unlocked,
  'viewing': open ? [...viewing] : const <int>[],
};

/// Port name under which the service host receives notification actions
/// (the background action isolate has no other way to reach it).
const notifierPortName = 'telegram_feed.notifier';

/// The `type` under which the app tells that port that a notification was tapped: Android
/// takes it out of the shade, and "N new posts" of its channel has to follow.
const notificationTapped = 'tapped';

/// Payload carried by every post notification and its actions.
final class PostRef {
  const PostRef(this.chatId, this.messageId, {this.feedId = 0});
  final int chatId;
  final int messageId;

  /// The feed of the rule that raised the notification; its post opens there. 0 when not
  /// known.
  final int feedId;

  Map<String, Object> toJson() => {
    'chatId': chatId,
    'messageId': messageId,
    'feedId': feedId,
  };

  String encode() => jsonEncode(toJson());

  static PostRef? decode(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final m = jsonDecode(payload) as Map<String, Object?>;
      return PostRef(
        m['chatId'] as int,
        m['messageId'] as int,
        feedId: m['feedId'] as int? ?? 0,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}

/// What to post for a match: pure, so it can be unit-tested without the plugin.
final class NotificationPlan {
  const NotificationPlan({
    required this.id,
    required this.channelId,
    required this.title,
    required this.body,
    this.rule = '',
    this.when,
    required this.groupKey,
    required this.summaryId,
    required this.payload,
    this.quiet = false,
    this.hidden = false,
  });
  final int id;
  final String channelId;
  final String title;
  final String body;

  /// The channel has sounded as often as it may for now ([Notifier.soundLimit]): this
  /// post is shown without sound and without a pop-up, whatever its rule's priority.
  final bool quiet;

  /// The app is locked: the notification says that there is a new post and nothing of
  /// it, neither the channel nor the words nor the rule, and has no buttons.
  final bool hidden;

  /// The same notification with other words (its post was edited), or made [quiet].
  NotificationPlan copyWith({String? body, bool? quiet}) => NotificationPlan(
    id: id,
    channelId: channelId,
    title: title,
    body: body ?? this.body,
    rule: rule,
    when: when,
    groupKey: groupKey,
    summaryId: summaryId,
    payload: payload,
    quiet: quiet ?? this.quiet,
    hidden: hidden,
  );

  /// What a post's notification says: its words in one line, cut at 240 letters, or
  /// what it carries when it has no words.
  static String bodyOf(Post post, AppLocalizations s) {
    final text =
        (post.albumId != 0 && post.text.trim().isEmpty
                // An album without a caption is named as one, not by its first picture.
                ? s.mediaAlbum
                : postLabel(post, s.mediaWords))
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
    return text.length > 240 ? '${text.substring(0, 240)}…' : text;
  }

  /// The rule that matched, shown as Android's sub-text beside the app's name: with
  /// several rules on one feed the shade would otherwise not say which one fired.
  final String rule;

  /// The time the notification shows, in milliseconds: the post's own, so posting it
  /// again with another button keeps its time and its place in the shade.
  final int? when;
  final String groupKey;
  final int summaryId;

  /// A [PostRef], with the rule and the time beside it for [restore].
  final String payload;

  static String channelFor(RulePriority p) => switch (p) {
    RulePriority.silent => channelSilent,
    RulePriority.normal => channelNormal,
    RulePriority.urgent => channelUrgent,
  };

  /// Stable notification id for a post (so a repeat show replaces, and cancel finds it).
  static int idFor(int chatId, int messageId) =>
      Object.hash(chatId, messageId) & 0x7fffffff;

  /// Ids for group summaries live in a separate range keyed by chat.
  static int summaryIdFor(int chatId) =>
      (chatId.hashCode & 0x3fffffff) | 0x40000000;

  factory NotificationPlan.forMatch(
    MatchEvent m, {
    required String channelTitle,
    AppLocalizations? strings,
    bool hidden = false,
  }) {
    final s = strings ?? AppLanguage.englishStrings;
    if (hidden) {
      return NotificationPlan(
        id: idFor(m.post.chatId, m.post.messageId),
        channelId: channelFor(m.priority),
        title: appName,
        body: s.notifyNewPost,
        when: m.post.date * 1000,
        groupKey: 'chat-${m.post.chatId}',
        summaryId: summaryIdFor(m.post.chatId),
        // Which post it is, for the tap that opens it; no rule's name beside it.
        payload: jsonEncode({
          ...PostRef(
            m.post.chatId,
            m.post.messageId,
            feedId: m.feedId,
          ).toJson(),
          'when': m.post.date * 1000,
        }),
        hidden: true,
      );
    }
    // A rule with no condition also notifies about posts without text; those show what
    // they carry ("Photo", "Video", the file's name).
    final body = bodyOf(m.post, s);
    // The rules that matched, so the shade says why this post is here.
    final rule = m.ruleNames.join(', ');
    final when = m.post.date * 1000;
    return NotificationPlan(
      id: idFor(m.post.chatId, m.post.messageId),
      channelId: channelFor(m.priority),
      title: channelTitle.isEmpty ? s.notifyNewPost : channelTitle,
      body: body,
      rule: rule,
      when: when,
      groupKey: 'chat-${m.post.chatId}',
      summaryId: summaryIdFor(m.post.chatId),
      payload: jsonEncode({
        ...PostRef(m.post.chatId, m.post.messageId, feedId: m.feedId).toJson(),
        'rule': rule,
        'when': when,
      }),
    );
  }

  /// The plan of a notification Android still shows, from what Android reports of it: for
  /// one posted before the service last started, so its button can change like any other
  /// one's. [androidChannelId] is the channel it was posted on. Null when the payload is
  /// not a post's.
  static NotificationPlan? restore({
    required int id,
    required String androidChannelId,
    required String title,
    required String body,
    required String groupKey,
    required String payload,
  }) {
    final ref = PostRef.decode(payload);
    if (ref == null) return null;
    final extra = jsonDecode(payload) as Map<String, Object?>;
    return NotificationPlan(
      id: id,
      channelId: androidChannelId.startsWith(channelUrgent)
          ? channelUrgent
          : androidChannelId.startsWith(channelSilent)
          ? channelSilent
          : channelNormal,
      title: title,
      body: body,
      rule: extra['rule'] as String? ?? '',
      when: extra['when'] as int?,
      groupKey: groupKey,
      summaryId: summaryIdFor(ref.chatId),
      payload: payload,
    );
  }
}

/// What the notifications of normal and urgent rules sound like (H-33): a sound uri from
/// Android's own picker (empty or null for the system default) and whether they vibrate.
/// Silent rules stay silent, so they have no choice of their own.
class NotificationSounds {
  const NotificationSounds({
    this.normalSound,
    this.urgentSound,
    this.normalVibrate = true,
    this.urgentVibrate = true,
  });
  final String? normalSound;
  final String? urgentSound;
  final bool normalVibrate;
  final bool urgentVibrate;

  @override
  bool operator ==(Object other) =>
      other is NotificationSounds &&
      other.normalSound == normalSound &&
      other.urgentSound == urgentSound &&
      other.normalVibrate == normalVibrate &&
      other.urgentVibrate == urgentVibrate;

  @override
  int get hashCode =>
      Object.hash(normalSound, urgentSound, normalVibrate, urgentVibrate);
}
