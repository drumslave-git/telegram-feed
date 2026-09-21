import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/service/notifier.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

void main() {
  MatchEvent match(RulePriority p, {String text = 'Breaking: rate cut'}) =>
      MatchEvent.of(
        Post(chatId: -1001, messageId: 5 << 20, date: 1, text: text),
        [MatchedRule(name: 'macro', priority: p, readAloud: false)],
      );

  test('the payload names the feed of the rule that decides', () {
    final m = MatchEvent.of(
      Post(chatId: -1001, messageId: 7, date: 1, text: 'rates'),
      const [
        MatchedRule(
          name: 'quiet',
          priority: RulePriority.silent,
          readAloud: false,
          feedId: 3,
        ),
        MatchedRule(
          name: 'loud',
          priority: RulePriority.urgent,
          readAloud: false,
          feedId: 4,
        ),
      ],
    );
    final ref = PostRef.decode(
      NotificationPlan.forMatch(m, channelTitle: 'News').payload,
    )!;
    expect((ref.chatId, ref.messageId, ref.feedId), (-1001, 7, 4));
    // An older payload without a feed still opens the post.
    expect(PostRef.decode('{"chatId":-1,"messageId":2}')!.feedId, 0);
  });

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

  test('a post without text shows what it carries', () {
    MatchEvent carrying(Media? media) => MatchEvent.of(
      Post(chatId: -1001, messageId: 5 << 20, date: 1, text: '', media: media),
      [
        const MatchedRule(
          name: 'every post',
          priority: RulePriority.normal,
          readAloud: false,
        ),
      ],
    );
    const file = FileRef(id: 1, remoteId: 'r', size: 1);
    String body(Media? m) =>
        NotificationPlan.forMatch(carrying(m), channelTitle: 'News').body;
    expect(body(const PhotoMedia(sizes: [file])), 'Photo');
    expect(body(const VideoMedia(file: file, durationSeconds: 5)), 'Video');
    expect(
      body(
        const DocumentMedia(
          file: file,
          fileName: 'plan.pdf',
          mimeType: 'application/pdf',
        ),
      ),
      'plan.pdf',
    );
    expect(body(null), 'Post');
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
