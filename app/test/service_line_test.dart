import 'package:app_db/app_db.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/post_card.dart' show ChatPill, PostCard;
import 'package:telegram_feed/feeds/timeline_screen.dart';
import 'package:telegram_feed/l10n/l10n.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fixtures.dart';

/// A service message is a centred line, as in the official app, and content the app does
/// not show is always named in the interface language.
void main() {
  late AppDatabase db;
  late TimelineGateway gw;
  const one = Channel(chatId: -1, title: 'One');

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    gw = TimelineGateway(
      {
        -1: [
          const Post(
            chatId: -1,
            messageId: 4,
            date: 400,
            text: '',
            media: ServiceNote(ServiceKind.titleChanged, title: 'One'),
          ),
          const Post(
            chatId: -1,
            messageId: 3,
            date: 300,
            text: '',
            media: ServiceNote(ServiceKind.pinned, messageId: 1),
          ),
          const Post(chatId: -1, messageId: 2, date: 200, text: '🔥'),
          const Post(
            chatId: -1,
            messageId: 1,
            date: 100,
            text: 'the pinned one',
          ),
        ],
      },
      channels: const [one],
    );
    gw.readPositions[-1] = 4;
  });

  Future<void> settle(WidgetTester tester) => tester.runAsync(() async {
    for (var i = 0; i < 3; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await tester.pump();
    }
  });

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('service messages are lines, not posts', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(db: db, gateway: gw, channel: one),
      ),
    );
    await settle(tester);
    await tester.pumpAndSettle();

    expect(find.byType(PostCard), findsNWidgets(2));
    expect(find.widgetWithText(ChatPill, 'One pinned a post'), findsOneWidget);
    expect(
      find.widgetWithText(ChatPill, 'Channel name changed to One'),
      findsOneWidget,
    );
    expect(find.text('🔥'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('in a feed a service line names its channel', (tester) async {
    late Feed feed;
    await tester.runAsync(() async {
      feed = await db.createFeed('Mix');
      await db.addSource(feed.id, -1, title: 'One');
    });
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(db: db, gateway: gw, feed: feed),
      ),
    );
    await settle(tester);
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(ChatPill, 'One: Channel name changed to One'),
      findsOneWidget,
    );
    expect(find.widgetWithText(ChatPill, 'One pinned a post'), findsOneWidget);
    await unmount(tester);
  });

  test('unsupported content never shows a TDLib type name', () {
    final en = AppLanguage.englishStrings;
    final uk = AppLanguage.stringsOfLanguage('uk')!;
    expect(en.unsupportedLabel('messagePoll'), 'Poll');
    expect(en.unsupportedLabel('messageChecklist'), 'Checklist');
    expect(en.unsupportedLabel('messagePaidMedia'), 'Paid media');
    expect(en.unsupportedLabel('messageGiveawayWinners'), 'Giveaway');
    expect(en.unsupportedLabel('messageSomethingNew'), 'Unsupported post');
    expect(uk.unsupportedLabel('messagePaidMedia'), 'Платне медіа');
    expect(uk.unsupportedLabel('messageSomethingNew'), 'Непідтримуваний допис');
  });

  test('service lines in both languages', () {
    final en = AppLanguage.englishStrings;
    final uk = AppLanguage.stringsOfLanguage('uk')!;
    const ended = ServiceNote(ServiceKind.liveEnded, seconds: 245);
    expect(en.serviceLabel(ended), 'Live stream ended (4:05)');
    expect(uk.serviceLabel(ended), 'Трансляцію завершено (4:05)');
    expect(
      uk.serviceLabel(const ServiceNote(ServiceKind.pinned), channel: 'Порт'),
      'Порт прикріплює допис',
    );
  });
}
