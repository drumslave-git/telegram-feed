/// Fixture helpers that need Flutter or the app database. The channels, posts and the
/// gateway that serves them come from `package:fake_telegram`, re-exported here.
library;

import 'package:app_db/app_db.dart';
import 'package:fake_telegram/fake_telegram.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

export 'package:fake_telegram/fake_telegram.dart';

/// Creates a feed over [titles] (chat id to title) and returns it. [marks] are Telegram's
/// read positions of those channels, set on [gateway], which holds them as TDLib does.
Future<Feed> fixtureFeed(
  AppDatabase db,
  String name,
  Map<int, String> titles, {
  Map<int, int> marks = const {},
  ChannelsGateway? gateway,
}) async {
  assert(marks.isEmpty || gateway != null, 'read positions live in a gateway');
  final feed = await db.createFeed(name);
  for (final entry in titles.entries) {
    await db.addSource(feed.id, entry.key, title: entry.value);
  }
  gateway?.readPositions.addAll(marks);
  return feed;
}

// ---- pumping ----

/// Lets the real asynchronous work of a screen (drift queries, the gateway's futures) run
/// between pumps: the fake clock of a widget test never would.
Future<void> settleFixtures(
  WidgetTester tester, {
  int rounds = 2,
  Duration step = const Duration(milliseconds: 80),
}) => tester.runAsync(() async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(step);
    await tester.pump();
  }
});

/// Takes the screen down and lets its pending timers (the read marker's debounce, drift's
/// last query) finish, so the test does not end with work in flight.
Future<void> unmountFixtures(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
}

/// An animated jump inside a timeline. The list's scroll runs on pumped time and the code
/// that waits for it in real time, so the two take turns until both are through.
Future<void> settleJump(WidgetTester tester) async {
  for (var i = 0; i < 16; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Records the vibrations the app asks for until the test ends: Flutter's haptic feedback
/// by its kind ('vibrate' is Android's long-press feedback) and the activity's own buzz as
/// 'buzz' with its milliseconds.
List<String> recordHaptics(WidgetTester tester) {
  final felt = <String>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'HapticFeedback.vibrate') {
      felt.add((call.arguments as String?)?.split('.').last ?? 'vibrate');
    }
    return null;
  });
  const app = MethodChannel('tf/app');
  messenger.setMockMethodCallHandler(app, (call) async {
    if (call.method == 'buzz') felt.add('buzz ${call.arguments}');
    return null;
  });
  addTearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    messenger.setMockMethodCallHandler(app, null);
  });
  return felt;
}
