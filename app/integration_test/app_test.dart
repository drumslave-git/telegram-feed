// Runs the real app on the emulator against the real TDLib build.
//
//   cd app && flutter test integration_test -d emulator-5554 \
//     --dart-define=TG_API_ID=... --dart-define=TG_API_HASH=...
//
// The account must already be logged in on the emulator (the founder types phone and code
// into the app once; the TDLib session persists). If it is not, the test reports that and
// passes without exercising the feed flow.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:telegram_feed/feeds/feed_editor_screen.dart';
import 'package:telegram_feed/feeds/timeline_screen.dart';
import 'package:telegram_feed/main.dart' as app;

Future<bool> _waitFor(
  WidgetTester tester,
  Finder f, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (f.evaluate().isNotEmpty) return true;
  }
  return false;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('core starts; logged-in account can build a feed and read it', (
    tester,
  ) async {
    app.main();
    final feeds = find.text('Feeds');
    final login = find.text('Log in to Telegram');
    final ok = await _waitFor(
      tester,
      find.byWidgetPredicate(
        (w) => feeds.evaluate().isNotEmpty || login.evaluate().isNotEmpty,
      ),
    );
    expect(
      ok,
      isTrue,
      reason:
          'neither the feeds list nor the login screen appeared within 30 s',
    );

    if (login.evaluate().isNotEmpty) {
      // ignore: avoid_print
      print(
        'INTEGRATION: not logged in on this emulator; login screen reached, feed flow skipped',
      );
      return;
    }

    // Create a feed named after the run, add the first joined channel, open the timeline.
    final name = 'it-${DateTime.now().millisecondsSinceEpoch % 100000}';
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), name);
    await tester.tap(find.text('Create'));
    expect(await _waitFor(tester, find.text(name)), isTrue);

    await tester.tap(find.text(name));
    expect(await _waitFor(tester, find.byType(TimelineScreen)), isTrue);
    await tester.tap(find.byIcon(Icons.tune));
    expect(await _waitFor(tester, find.byType(FeedEditorScreen)), isTrue);
    await tester.tap(find.text('Add channel'));
    expect(
      await _waitFor(tester, find.byType(ListTile)),
      isTrue,
      reason: 'no joined channels offered',
    );
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    expect(
      await _waitFor(tester, find.byIcon(Icons.remove_circle_outline)),
      isTrue,
    );

    // Back to the timeline: posts should arrive from TDLib.
    await tester.pageBack();
    expect(
      await _waitFor(
        tester,
        find.byType(PostCard),
        timeout: const Duration(seconds: 60),
      ),
      isTrue,
      reason: 'no posts loaded for the first channel',
    );
    // ignore: avoid_print
    print('INTEGRATION: feed "$name" shows posts');
  });
}
