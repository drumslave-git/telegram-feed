import 'package:tdlib_bindings/tdlib_bindings.dart' as td;
import 'package:telegram_gateway/src/mapping.dart' as map;
import 'package:telegram_gateway/telegram_gateway.dart';
import 'package:test/test.dart';

Map<String, Object?> _reaction(
  Map<String, Object?> type,
  int count, {
  bool chosen = false,
}) => {
  '@type': 'messageReaction',
  'type': type,
  'total_count': count,
  'is_chosen': chosen,
  'recent_sender_ids': const <Object?>[],
};

Map<String, Object?> _available(
  Map<String, Object?> type, {
  bool premium = false,
}) => {'@type': 'availableReaction', 'type': type, 'needs_premium': premium};

const _emoji = {'@type': 'reactionTypeEmoji', 'emoji': '👍'};
const _custom = {'@type': 'reactionTypeCustomEmoji', 'custom_emoji_id': '77'};
const _paid = {'@type': 'reactionTypePaid'};

void main() {
  test('custom-emoji and paid reactions of a post are kept', () {
    final reactions = map.reactions(
      td.MessageReactions.fromJson({
        '@type': 'messageReactions',
        'reactions': [
          _reaction(_paid, 3),
          _reaction(_emoji, 12),
          _reaction(_custom, 7, chosen: true),
        ],
        'are_tags': false,
        'paid_reactors': const <Object?>[],
        'can_get_added_reactions': false,
      }),
    );
    expect(
      [for (final r in reactions) (r.emoji, r.count, r.chosen)],
      [(paidReaction, 3, false), ('👍', 12, false), ('custom:77', 7, true)],
    );
    expect(customReactionId(reactions[2].emoji), '77');
    expect(customReactionId('👍'), isNull);
  });

  test('the picker offers plain and custom emoji, once each, without the paid '
      'one and without those only Premium may send', () {
    final offered = map.availableEmoji(
      td.AvailableReactions.fromJson({
        '@type': 'availableReactions',
        'top_reactions': [
          _available(_paid),
          _available(_custom),
          _available(_emoji),
        ],
        'recent_reactions': const <Object?>[],
        'popular_reactions': [
          _available(_emoji),
          _available({
            '@type': 'reactionTypeCustomEmoji',
            'custom_emoji_id': '88',
          }, premium: true),
        ],
        'allow_custom_emoji': false,
        'are_tags': false,
        'unavailability_reason': null,
      }),
    );
    expect(offered, ['custom:77', '👍']);
  });

  test('a reaction is sent as the type Telegram knows it by', () {
    expect((map.reactionType('👍')! as td.ReactionTypeEmoji).emoji, '👍');
    expect(
      (map.reactionType('custom:77')! as td.ReactionTypeCustomEmoji)
          .customEmojiId,
      77,
    );
    expect(map.reactionType(paidReaction), isNull);
  });
}
