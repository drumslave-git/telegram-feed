import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/l10n/l10n.dart';
import 'package:telegram_feed/service/notifier.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'notifier_harness.dart';

/// A channel sounds at most twice in three minutes; an edited post's line says the new
/// words.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const chatId = -1001;

  late FakeShade shade;
  late DateTime now;
  late Notifier notifier;

  setUp(() async {
    shade = FakeShade()..install();
    now = DateTime(2026, 10, 4, 12);
    notifier = Notifier(null, () => now, MemoryStore());
    await notifier.init(strings: AppLanguage.englishStrings);
  });

  tearDown(() => shade.remove());

  test('the third post of a channel within three minutes is added quietly, '
      'and the channel sounds again when the three minutes are over', () async {
    await notifier.show(planFor(1));
    now = now.add(const Duration(seconds: 30));
    await notifier.show(planFor(2));
    expect(shade.shown.map((s) => s.alerts), [true, true]);

    now = now.add(const Duration(seconds: 30));
    await notifier.show(planFor(3));
    now = now.add(const Duration(seconds: 30));
    await notifier.show(planFor(4, priority: RulePriority.urgent));
    // Listed, every one of them, but without sound and pop-up, on the channel the
    // notification was on.
    expect(shade.shown.last.lines, hasLength(4));
    expect(shade.shown.skip(2).map((s) => s.alerts), [false, false]);
    expect(shade.shown.last.channel, 'posts_normal_popup');

    // Three minutes after the first sound one more may sound, then the second's
    // three minutes have to pass too.
    now = DateTime(2026, 10, 4, 12, 3, 1);
    await notifier.show(planFor(5));
    expect(shade.shown.last.alerts, isTrue);
    await notifier.show(planFor(6));
    expect(shade.shown.last.alerts, isFalse);
    now = DateTime(2026, 10, 4, 12, 3, 31);
    await notifier.show(planFor(7));
    expect(shade.shown.last.alerts, isTrue);
  });

  test('a channel whose first post comes after two sounds is shown among '
      'the silent ones', () async {
    await notifier.show(planFor(1));
    await notifier.show(planFor(2));
    await notifier.cancelRead(chatId, 2);
    now = now.add(const Duration(seconds: 30));
    await notifier.show(planFor(3));
    expect(shade.shown.last.channel, 'posts_silent');
    expect(shade.shown.last.importance, lessThan(3));
  });

  test(
    'each channel counts for itself, and silent rules count for nothing',
    () async {
      await notifier.show(planFor(1));
      await notifier.show(planFor(2));
      // Another channel is not held back by this one.
      await notifier.show(planFor(1, chatId: -1002));
      expect(shade.shown.last.alerts, isTrue);

      // Posts of silent rules never sounded: they use up nothing.
      for (var i = 1; i <= 3; i++) {
        await notifier.show(
          planFor(i, chatId: -1003, priority: RulePriority.silent),
        );
      }
      await notifier.show(planFor(4, chatId: -1003));
      await notifier.show(planFor(5, chatId: -1003));
      expect(shade.shown.reversed.take(2).map((s) => s.alerts), [true, true]);
    },
  );

  test('an edited post changes the words of its line without sounding '
      'again', () async {
    await notifier.show(planFor(1, text: 'The bridge is closed.'));
    final before = shade.shown.single;

    await notifier.updateBody(chatId, 1, 'The bridge is open again.');
    expect(shade.shown, hasLength(2));
    expect(shade.shown.last.id, before.id);
    expect(shade.shown.last.texts, ['The bridge is open again.']);
    expect(shade.shown.last.alerts, isFalse);
    expect(shade.shown.last.channel, before.channel);

    // The same words again: nothing is posted.
    await notifier.updateBody(chatId, 1, 'The bridge is open again.');
    expect(shade.shown, hasLength(2));
    // The edit did not use up one of the channel's two sounds.
    await notifier.show(planFor(2));
    expect(shade.shown.last.alerts, isTrue);
  });

  test('an edit brings back neither a dismissed notification nor one that '
      'was never shown', () async {
    await notifier.updateBody(chatId, 9, 'never matched');
    expect(shade.shown, isEmpty);

    await notifier.show(planFor(1));
    now = now.add(const Duration(minutes: 1));
    shade.swipe(chatId);
    await notifier.updateBody(chatId, 1, 'edited');
    expect(shade.shown, hasLength(1));
  });

  test('the words of a line: one line, cut, or what the post carries', () {
    final s = AppLanguage.englishStrings;
    expect(
      NotificationPlan.bodyOf(
        Post(chatId: -1, messageId: 1, date: 1, text: 'a\n\n b'),
        s,
      ),
      'a b',
    );
    expect(
      NotificationPlan.bodyOf(
        Post(chatId: -1, messageId: 1, date: 1, text: 'x' * 300),
        s,
      ),
      hasLength(241),
    );
  });
}
