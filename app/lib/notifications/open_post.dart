import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../feeds/open_links.dart';
import '../feeds/timeline_screen.dart';
import '../host/app_host.dart';
import '../service/notification_plan.dart';

/// Global navigator so notification taps can push screens from outside the tree.
final navigatorKey = GlobalKey<NavigatorState>();

Future<void> openInTelegram(AppDatabase db, PostRef ref) async {
  final username = (await db.allWatched())
      .where((w) => w.chatId == ref.chatId)
      .map((w) => w.username)
      .firstOrNull;
  final uri = telegramPostUri(
    chatId: ref.chatId,
    messageId: ref.messageId,
    username: username,
  );
  final web = telegramPostWebUri(chatId: ref.chatId, messageId: ref.messageId);
  await launchFirst([uri, web]);
}

/// Pushes the timeline of the rule's feed, focused on the post; the first feed containing
/// the post's channel when that feed is gone.
Future<void> openPost(AppHost host, PostRef ref) async {
  final feeds = await host.db.feedsContaining(ref.chatId);
  final nav = navigatorKey.currentState;
  if (feeds.isEmpty || nav == null) return;
  final feed = feeds.firstWhere(
    (f) => f.id == ref.feedId,
    orElse: () => feeds.first,
  );
  await nav.push(
    MaterialPageRoute<void>(
      builder: (_) => TimelineScreen(
        db: host.db,
        gateway: host.gateway,
        feed: feed,
        focusChatId: ref.chatId,
        focusMessageId: ref.messageId,
      ),
    ),
  );
}
