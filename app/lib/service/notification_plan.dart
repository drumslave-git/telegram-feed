import 'dart:convert';

import 'package:core/core.dart';

/// Notification channels (ARCHITECTURE.md section 6.3), one per rule priority.
const channelSilent = 'posts_silent';
const channelNormal = 'posts_normal';
const channelUrgent = 'posts_urgent';

/// Urgent channel that bypasses Do Not Disturb. Android fixes a channel's DND bypass when
/// the channel is created, and only honours it if the app already has notification policy
/// access, so this second channel is created once access is granted ([Notifier]).
const channelUrgentDnd = 'posts_urgent_dnd';

/// Action ids on post notifications.
const actionListen = 'listen';
const actionOpenTelegram = 'open_tg';

/// Port name under which the service host receives notification actions
/// (the background action isolate has no other way to reach it).
const notifierPortName = 'telegram_feed.notifier';

/// Payload carried by every post notification and its actions.
final class PostRef {
  const PostRef(this.chatId, this.messageId);
  final int chatId;
  final int messageId;

  String encode() => jsonEncode({'chatId': chatId, 'messageId': messageId});

  static PostRef? decode(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final m = jsonDecode(payload) as Map<String, Object?>;
      return PostRef(m['chatId'] as int, m['messageId'] as int);
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
    required this.groupKey,
    required this.summaryId,
    required this.payload,
  });
  final int id;
  final String channelId;
  final String title;
  final String body;
  final String groupKey;
  final int summaryId;
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
  }) {
    final text = m.post.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final body = text.length > 240 ? '${text.substring(0, 240)}…' : text;
    return NotificationPlan(
      id: idFor(m.post.chatId, m.post.messageId),
      channelId: channelFor(m.priority),
      title: channelTitle.isEmpty ? 'New post' : channelTitle,
      body: body,
      groupKey: 'chat-${m.post.chatId}',
      summaryId: summaryIdFor(m.post.chatId),
      payload: PostRef(m.post.chatId, m.post.messageId).encode(),
    );
  }
}
