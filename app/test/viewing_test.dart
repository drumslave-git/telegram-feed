import 'package:app_db/app_db.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/timeline_screen.dart';
import 'package:telegram_feed/host/viewing.dart';
import 'package:telegram_feed/service/notification_plan.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fixtures.dart';

void main() {
  test('the timeline on top is the one on screen; none, and nothing is', () {
    final a = Object();
    final b = Object();
    expect(Viewing.chats.value, isEmpty);
    Viewing.show(a, [-1, -2]);
    expect(Viewing.chats.value, {-1, -2});
    // Another timeline opened over it.
    Viewing.show(b, [-3]);
    expect(Viewing.chats.value, {-3});
    Viewing.hide(b);
    expect(Viewing.chats.value, {-1, -2});
    // Its sources were loaded, or changed.
    Viewing.show(a, [-1]);
    expect(Viewing.chats.value, {-1});
    Viewing.hide(a);
    expect(Viewing.chats.value, isEmpty);
  });

  test('what the service is told: the timeline in front only while the app '
      'is open', () {
    expect(appOpenMessage(true, unlocked: true, viewing: {-1}), {
      'appOpen': true,
      'unlocked': true,
      'viewing': [-1],
    });
    expect(appOpenMessage(false, unlocked: true, viewing: {-1}), {
      'appOpen': false,
      'unlocked': false,
      'viewing': <int>[],
    });
  });

  testWidgets('a timeline says its channel is on screen while it is in front, '
      'and not while another screen covers it', (tester) async {
    const channel = Channel(chatId: -1, title: 'One', lastMessageId: 9);
    final db = AppDatabase(NativeDatabase.memory());
    final gw = TimelineGateway(
      {
        -1: [Post(chatId: -1, messageId: 9, date: 900, text: 'a post')],
      },
      channels: const [channel],
    );
    Future<void> settle() => tester.runAsync(() async {
      for (var i = 0; i < 3; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        await tester.pump();
      }
    });

    await tester.pumpWidget(
      MaterialApp(
        home: TimelineScreen(db: db, gateway: gw, channel: channel),
      ),
    );
    await settle();
    await tester.pumpAndSettle();
    expect(Viewing.chats.value, {-1});

    // Another screen over it: its posts pop up like any other again.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('settings')),
      ),
    );
    await tester.pumpAndSettle();
    expect(Viewing.chats.value, isEmpty);

    navigator.pop();
    await tester.pumpAndSettle();
    expect(Viewing.chats.value, {-1});

    // Gone: nothing is on screen.
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(Viewing.chats.value, isEmpty);
    await tester.runAsync(db.close);
  });
}
