import 'package:app_db/app_db.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/home/connection_title.dart';
import 'package:telegram_feed/home/home_screen.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fixtures.dart';

void main() {
  late AppDatabase db;
  late TimelineGateway gw;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    gw = TimelineGateway(
      const {},
      channels: const [Channel(chatId: -1, title: 'One')],
    );
  });

  Future<void> settle(WidgetTester tester) => tester.runAsync(() async {
    for (var i = 0; i < 3; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await tester.pump();
    }
  });

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
  }

  test('every state but ready has words of its own', () {
    expect(ConnectionTitle.words(ConnectionStatus.ready), isNull);
    expect(
      ConnectionTitle.words(ConnectionStatus.connecting),
      contains('Connecting'),
    );
    expect(
      ConnectionTitle.words(ConnectionStatus.waitingForNetwork),
      contains('network'),
    );
    expect(
      ConnectionTitle.words(ConnectionStatus.updating),
      contains('Updating'),
    );
    expect(
      ConnectionTitle.words(ConnectionStatus.connectingToProxy),
      contains('proxy'),
    );
  });

  testWidgets('the home bar says what the connection is doing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(db: db, gateway: gw),
      ),
    );
    await settle(tester);
    // Ready: the name of the app alone.
    expect(find.text('Unofficial Telegram Feed'), findsOneWidget);
    expect(find.textContaining('Connecting'), findsNothing);

    gw.connectionStatus.add(ConnectionStatus.connecting);
    await settle(tester);
    expect(find.text('Unofficial Telegram Feed'), findsOneWidget);
    expect(find.textContaining('Connecting'), findsOneWidget);

    gw.connectionStatus.add(ConnectionStatus.ready);
    await settle(tester);
    expect(find.textContaining('Connecting'), findsNothing);
    await unmount(tester);
  });
}
