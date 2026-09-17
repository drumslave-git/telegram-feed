import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/service/notifier.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

void main() {
  MatchEvent match(RulePriority p, {String text = 'Breaking: rate cut'}) =>
      MatchEvent(
        post: Post(chatId: -1001, messageId: 5 << 20, date: 1, text: text),
        priority: p,
        readAloud: false,
        ruleNames: const ['macro'],
      );

  test('channel follows priority; ids are stable; payload round-trips', () {
    final plan = NotificationPlan.forMatch(
      match(RulePriority.urgent),
      channelTitle: 'News',
    );
    expect(plan.channelId, channelUrgent);
    expect(plan.title, 'News');
    expect(plan.body, 'Breaking: rate cut');
    expect(plan.groupKey, 'chat--1001');
    expect(plan.id, NotificationPlan.idFor(-1001, 5 << 20));
    expect(plan.summaryId, isNot(plan.id));
    expect(PostRef.decode(plan.payload)!.messageId, 5 << 20);
    expect(
      NotificationPlan.forMatch(
        match(RulePriority.silent),
        channelTitle: '',
      ).channelId,
      channelSilent,
    );
    expect(
      NotificationPlan.forMatch(
        match(RulePriority.normal),
        channelTitle: '',
      ).title,
      'New post',
    );
  });

  test('body is collapsed and truncated', () {
    final long = List.filled(60, 'word').join('\n  ');
    final plan = NotificationPlan.forMatch(
      match(RulePriority.normal, text: long),
      channelTitle: 'x',
    );
    expect(plan.body.contains('\n'), isFalse);
    expect(plan.body.length, 241);
    expect(plan.body.endsWith('…'), isTrue);
  });

  test('bad payloads decode to null', () {
    expect(PostRef.decode(null), isNull);
    expect(PostRef.decode('nope'), isNull);
    expect(PostRef.decode('{"chatId":"x"}'), isNull);
  });
}
