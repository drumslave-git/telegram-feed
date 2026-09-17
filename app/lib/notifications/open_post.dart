import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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
  for (final u in [uri, web]) {
    if (u != null && await launchUrl(u, mode: LaunchMode.externalApplication)) {
      return;
    }
  }
}

/// Pushes the timeline of the first feed containing the post's channel, focused on the post.
Future<void> openPost(AppHost host, PostRef ref) async {
  final feeds = await host.db.feedsContaining(ref.chatId);
  final nav = navigatorKey.currentState;
  if (feeds.isEmpty || nav == null) return;
  await nav.push(
    MaterialPageRoute<void>(
      builder: (_) => TimelineScreen(
        db: host.db,
        gateway: host.gateway,
        feed: feeds.first,
        focusChatId: ref.chatId,
        focusMessageId: ref.messageId,
      ),
    ),
  );
}
