// Runs the real app on the emulator against the fake Telegram (`package:fake_telegram`):
// the core, the service, the database and every screen are real; only Telegram is scripted.
//
//   cd app && flutter test integration_test -d emulator-5554 --dart-define=TG_FAKE=true
//
// The fake starts logged out; the test logs in with any number and the fixture code.
import 'package:fake_telegram/fake_telegram.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:telegram_feed/feeds/feed_editor_screen.dart';
import 'package:telegram_feed/feeds/timeline_screen.dart';
import 'package:telegram_feed/home/home_screen.dart';
import 'package:telegram_feed/main.dart' as app;

/// Waits for [f], then lets the screen finish arriving: a sheet or a route whose widgets
/// exist is still sliding in, and a tap at their final place would miss. When [f] never
/// shows, the texts on the screen are printed, since a failed run on an emulator leaves
/// nothing else to look at.
Future<bool> _waitFor(
  WidgetTester tester,
  Finder f, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (f.evaluate().isNotEmpty) {
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
      return true;
    }
  }
  final texts = find
      .byType(Text)
      .evaluate()
      .map((e) => (e.widget as Text).data)
      .whereType<String>()
      .toList();
  // ignore: avoid_print
  print('INTEGRATION: waited in vain for $f; on screen: $texts');
  return false;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('core starts; the account logs in, builds a feed and reads it', (
    tester,
  ) async {
    app.main();
    final home = find.byType(HomeScreen);
    final login = find.text('Log in to Telegram');
    final ok = await _waitFor(
      tester,
      find.byWidgetPredicate(
        (w) => home.evaluate().isNotEmpty || login.evaluate().isNotEmpty,
      ),
    );
    expect(
      ok,
      isTrue,
      reason:
          'neither the home screen nor the login screen appeared within 30 s',
    );

    if (login.evaluate().isNotEmpty) {
      await tester.enterText(find.byType(TextField), '+15550100');
      await tester.tap(find.text('Send code'));
      expect(await _waitFor(tester, find.text('Enter the code')), isTrue);
      await tester.enterText(find.byType(TextField), fakeLoginCode);
      await tester.tap(find.text('Continue'));
      expect(await _waitFor(tester, home), isTrue, reason: 'login failed');
    }

    // The folder tabs are up once the channels have arrived; before that "New feed"
    // has no folders to offer and skips the sheet.
    expect(await _waitFor(tester, find.text('News')), isTrue);

    // An empty feed named after the run, with Harbour Times added from the picker.
    final name = 'it-${DateTime.now().millisecondsSinceEpoch % 100000}';
    await tester.tap(find.text('New feed'));
    expect(await _waitFor(tester, find.text('Empty feed')), isTrue);
    await tester.tap(find.text('Empty feed'));
    expect(await _waitFor(tester, find.byType(TextField)), isTrue);
    await tester.enterText(find.byType(TextField), name);
    // The Create button follows the field's contents; a frame lets it enable.
    await tester.pump();
    await tester.tap(find.text('Create'));
    // A new feed opens its channel editor right away.
    expect(await _waitFor(tester, find.byType(FeedEditorScreen)), isTrue);
    await tester.tap(find.text('Add channel'));
    expect(
      await _waitFor(tester, find.text('Harbour Times')),
      isTrue,
      reason: 'the joined channels were not offered',
    );
    // The sheet is still sliding in when its rows first exist.
    await tester.pumpAndSettle();
    await tester.tap(find.text('Harbour Times'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(
      await _waitFor(tester, find.byIcon(Icons.remove_circle_outline)),
      isTrue,
    );

    // Back to the Feeds tab; open the feed: the fixture posts come through the core.
    await tester.pageBack();
    // Until the editor has slid away its title still carries the name.
    await tester.pumpAndSettle();
    expect(await _waitFor(tester, find.text(name)), isTrue);
    await tester.tap(find.text(name));
    expect(await _waitFor(tester, find.byType(TimelineScreen)), isTrue);
    expect(
      await _waitFor(tester, find.byType(PostCard)),
      isTrue,
      reason: 'no posts loaded for Harbour Times',
    );
    expect(
      await _waitFor(tester, find.textContaining('Weekend market')),
      isTrue,
    );
  });
}
