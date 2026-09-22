import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/post_card.dart';
import 'package:telegram_feed/feeds/text_scale.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'media_view_test.dart' show DownloadGateway;

void main() {
  late AppDatabase db;
  late DownloadGateway gw;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    gw = DownloadGateway('/nonexistent.png');
  });

  tearDown(() => db.close());

  Widget app() => MaterialApp(
    home: PostTextScale(
      db: db,
      child: Scaffold(
        body: Builder(
          builder: (context) => PostCard(
            item: TimelineItem(
              const Post(
                chatId: -1001,
                messageId: 5,
                date: 1700000000,
                text: 'measure me',
              ),
            ),
            channelTitle: 'Alpha News',
            gateway: gw,
          ),
        ),
      ),
    ),
  );

  /// Drift does real I/O: let its stream deliver, then rebuild.
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
    // Drift arms a zero-duration timer when its stream is cancelled.
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('the chosen factor makes the post text bigger', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);
    final plain = tester.getSize(find.text('measure me'));

    await tester.runAsync(
      () => db.setSetting(SettingKeys.postTextScale, '1.60'),
    );
    await settle(tester);
    expect(
      tester.getSize(find.text('measure me')).width,
      greaterThan(plain.width),
    );

    await tester.runAsync(
      () => db.setSetting(SettingKeys.postTextScale, '0.80'),
    );
    await settle(tester);
    expect(
      tester.getSize(find.text('measure me')).width,
      lessThan(plain.width),
    );
    await unmount(tester);
  });

  testWidgets("the factor goes on top of the phone's own text size", (
    tester,
  ) async {
    // The phone draws text at 1.3; a post factor of 1.1 must not make posts smaller.
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(app());
    await settle(tester);
    final system = tester.getSize(find.text('measure me'));
    await tester.runAsync(
      () => db.setSetting(SettingKeys.postTextScale, '1.10'),
    );
    await settle(tester);
    expect(
      tester.getSize(find.text('measure me')).width,
      greaterThan(system.width),
    );
    await unmount(tester);
  });

  test('the factor is read, clamped and defaulted', () {
    expect(PostTextScale.parse(null), 1.0);
    expect(PostTextScale.parse('junk'), 1.0);
    expect(PostTextScale.parse('1.25'), 1.25);
    expect(PostTextScale.parse('9'), PostTextScale.max);
    expect(PostTextScale.parse('0.1'), PostTextScale.min);
  });
}
