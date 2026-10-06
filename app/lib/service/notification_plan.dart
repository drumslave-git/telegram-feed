import 'dart:convert';

import 'package:core/core.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

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

/// Port name under which whoever runs the alerts (the app, the service or a push run)
/// receives notification actions: the background action isolate has no other way to
/// reach it.
const notifierPortName = 'telegram_feed.notifier';

/// The `type` under which a run asks that port whether the alerts are still at work
/// (`RuleAlerts.busy`); the answer goes to the `SendPort` under `reply`.
const alertsBusy = 'busy?';

/// The `type` under which the app tells that port that a notification was tapped, or
/// its "Open in Telegram": Android takes it out of the shade, and what it listed is
/// forgotten.
const notificationTapped = 'tapped';

/// Payload carried by every post notification and its actions.
final class PostRef {
  const PostRef(
    this.chatId,
    this.messageId, {
    this.feedId = 0,
    this.account = 0,
  });
  final int chatId;
  final int messageId;

  /// The account the post matched in (`AccountInfo.id`): a tap goes to that account
  /// first. 0 where it is not said, which stands for the account in use.
  final int account;

  /// The feed of the rule that raised the notification; its post opens there. 0 when not
  /// known.
  final int feedId;

  Map<String, Object> toJson() => {
    'chatId': chatId,
    'messageId': messageId,
    'feedId': feedId,
    if (account != 0) 'account': account,
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
        account: m['account'] as int? ?? 0,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}

/// What a match adds to its channel's notification: one line of the conversation the
/// notification lists. Pure, so it can be unit-tested without the plugin.
final class NotificationPlan {
  const NotificationPlan({
    required this.id,
    required this.channelId,
    required this.title,
    required this.body,
    this.rule = '',
    this.when,
    required this.payload,
    this.quiet = false,
    this.hidden = false,
    this.picture,
    this.avatar,
    this.accountName = '',
  });

  /// The name of the account the post matched in, while several accounts notify: it
  /// stands on the notification, as in the official app. Empty with one account.
  final String accountName;

  /// The post's own id among the notifications' lines ([idFor]); the notification that
  /// lists it has the channel's ([idForChat]).
  final int id;
  final String channelId;
  final String title;
  final String body;

  /// The post's picture, as a content uri Android's notification shade may read: shown
  /// under the post's line. Null for a post without one, or one that could not be had.
  final String? picture;

  /// The channel's photo as a round picture in a file: the face of the conversation.
  final String? avatar;

  /// The post this line stands for.
  PostRef get ref => PostRef.decode(payload)!;

  /// The channel has sounded as often as it may for now ([Notifier.soundLimit]): this
  /// post is shown without sound and without a pop-up, whatever its rule's priority.
  final bool quiet;

  /// The app is locked: the notification says that there is a new post and nothing of
  /// it, neither the channel nor the words nor the rule, and has no buttons.
  final bool hidden;

  /// The same line with other words (its post was edited), made [quiet], or with its
  /// pictures.
  NotificationPlan copyWith({
    String? body,
    bool? quiet,
    String? picture,
    String? avatar,
  }) => NotificationPlan(
    id: id,
    channelId: channelId,
    title: title,
    body: body ?? this.body,
    rule: rule,
    when: when,
    payload: payload,
    quiet: quiet ?? this.quiet,
    hidden: hidden,
    picture: picture ?? this.picture,
    avatar: avatar ?? this.avatar,
    accountName: accountName,
  );

  /// As the file that keeps the listed posts across a restart holds it ([Notifier]).
  Map<String, Object?> toJson() => {
    'id': id,
    'channelId': channelId,
    'title': title,
    'body': body,
    'rule': rule,
    'when': when,
    'payload': payload,
    'quiet': quiet,
    'hidden': hidden,
    'picture': picture,
    'avatar': avatar,
    'accountName': accountName,
  };

  /// Null for what is not a line of a post.
  static NotificationPlan? fromJson(Object? json) {
    if (json is! Map) return null;
    try {
      final payload = json['payload'] as String;
      final ref = PostRef.decode(payload);
      if (ref == null) return null;
      return NotificationPlan(
        id: idFor(ref.chatId, ref.messageId),
        channelId: json['channelId'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        rule: json['rule'] as String? ?? '',
        when: json['when'] as int?,
        payload: payload,
        quiet: json['quiet'] == true,
        hidden: json['hidden'] == true,
        picture: json['picture'] as String?,
        avatar: json['avatar'] as String?,
        accountName: json['accountName'] as String? ?? '',
      );
    } on TypeError {
      return null;
    }
  }

  /// What a post's line says: its words in one line, cut at 240 letters, or what it
  /// carries when it has no words. A caption is marked with what it is the caption of,
  /// as the official app marks it.
  static String bodyOf(Post post, AppLocalizations s) {
    final captioned = post.text.trim().isNotEmpty;
    final text =
        (post.albumId != 0 && !captioned
                // An album without a caption is named as one, not by its first picture.
                ? s.mediaAlbum
                : postLabel(post, s.mediaWords))
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
    final cut = text.length > 240 ? '${text.substring(0, 240)}…' : text;
    return captioned ? '${markOf(post.media)}$cut' : cut;
  }

  /// The mark before the caption of a picture, a video, a GIF or a file.
  static String markOf(Media? media) => switch (media) {
    PhotoMedia() => '🖼 ',
    VideoMedia(isVideoNote: true) => '',
    VideoMedia(isAnimation: true) => '🎬 ',
    VideoMedia() => '📹 ',
    DocumentMedia() => '📎 ',
    _ => '',
  };

  /// The rule that matched, shown as Android's sub-text beside the app's name: with
  /// several rules on one feed the shade would otherwise not say which one fired.
  final String rule;

  /// The time of the post, in milliseconds: its line shows it, and the notification
  /// shows that of its newest post.
  final int? when;

  /// A [PostRef], with the rule and the time beside it.
  final String payload;

  static String channelFor(RulePriority p) => switch (p) {
    RulePriority.silent => channelSilent,
    RulePriority.normal => channelNormal,
    RulePriority.urgent => channelUrgent,
  };

  /// Stable id for a post (so the same post again replaces its line, and read-aloud
  /// names it). Arithmetic, not `Object.hash`, whose result differs from one run of the
  /// app to the next.
  static int idFor(int chatId, int messageId) =>
      (chatId * 1000003 ^ messageId).hashCode & 0x7fffffff;

  /// The id of the one notification a channel has in an account. The same on every run,
  /// so the notifications Android still shows are found again after a restart.
  static int idForChat(int chatId, [int account = 0]) =>
      ((chatId ^ (account * 0x9E3779B1)).hashCode & 0x3fffffff) | 0x40000000;

  factory NotificationPlan.forMatch(
    MatchEvent m, {
    required String channelTitle,
    AppLocalizations? strings,
    bool hidden = false,
    int account = 0,
    String accountName = '',
  }) {
    final s = strings ?? AppLanguage.englishStrings;
    if (hidden) {
      return NotificationPlan(
        id: idFor(m.post.chatId, m.post.messageId),
        channelId: channelFor(m.priority),
        title: appName,
        body: s.notifyNewPost,
        when: m.post.date * 1000,
        // Which post it is, for the tap that opens it; no rule's name beside it.
        payload: jsonEncode({
          ...PostRef(
            m.post.chatId,
            m.post.messageId,
            feedId: m.feedId,
            account: account,
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
      payload: jsonEncode({
        ...PostRef(
          m.post.chatId,
          m.post.messageId,
          feedId: m.feedId,
          account: account,
        ).toJson(),
        'rule': rule,
        'when': when,
      }),
      accountName: accountName,
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
