import 'dart:convert';

import 'package:core/core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rules/rules.dart';
import 'package:telegram_gateway/telegram_gateway.dart';
import 'package:test/test.dart';

http.Response _reply(String content) => http.Response.bytes(
  utf8.encode(
    jsonEncode({
      'choices': [
        {
          'message': {'role': 'assistant', 'content': content},
        },
      ],
    }),
  ),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  const config = AiConfig(
    baseUrl: 'https://llm.example/v1/',
    model: 'small',
    apiKey: 'k',
  );

  test('asks once for all descriptions and parses the numbers', () async {
    late http.Request seen;
    final client = SemanticClient(
      client: MockClient((r) async {
        seen = r;
        return _reply('1, 3');
      }),
    );
    final hits = await client.matching(
      config: config,
      postText: 'ЦБ снизил ключевую ставку',
      criteria: ['central bank rate decisions', 'sports', 'Russian economy'],
    );
    expect(hits, {0, 2});
    expect(seen.url.toString(), 'https://llm.example/v1/chat/completions');
    expect(seen.headers['authorization'], 'Bearer k');
    final body = jsonDecode(seen.body) as Map<String, Object?>;
    expect(body['model'], 'small');
    expect(body.keys.toSet(), {
      'model',
      'messages',
    }); // nothing a provider may reject
    final user = ((body['messages'] as List)[1] as Map)['content'] as String;
    expect(user, contains('2. sports'));
    expect(user, contains('ЦБ снизил ключевую ставку'));
  });

  test('NONE, chatter and out-of-range numbers', () {
    expect(SemanticClient.parseAnswer('NONE', 3), isEmpty);
    expect(SemanticClient.parseAnswer('Matches: 2.', 3), {1});
    expect(SemanticClient.parseAnswer('7, 0, 1', 3), {0});
  });

  test('failures become SemanticException with a readable reason', () async {
    final unauthorised = SemanticClient(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {'message': 'Incorrect API key'},
          }),
          401,
        ),
      ),
    );
    await expectLater(
      unauthorised.matching(config: config, postText: 'x', criteria: ['a']),
      throwsA(
        isA<SemanticException>().having(
          (e) => e.message,
          'message',
          allOf(contains('401'), contains('Incorrect API key')),
        ),
      ),
    );
    final offline = SemanticClient(
      client: MockClient((_) async => throw http.ClientException('no route')),
    );
    await expectLater(
      offline.matching(config: config, postText: 'x', criteria: ['a']),
      throwsA(isA<SemanticException>()),
    );
    await expectLater(
      offline.matching(
        config: const AiConfig(baseUrl: '', model: ''),
        postText: 'x',
        criteria: ['a'],
      ),
      throwsA(isA<SemanticException>()),
    );
  });

  test(
    'an empty answer (reasoning model cut off) is a failure, not NONE',
    () async {
      final client = SemanticClient(
        client: MockClient((_) async => _reply('  ')),
      );
      await expectLater(
        client.matching(config: config, postText: 'x', criteria: ['a']),
        throwsA(
          isA<SemanticException>().having(
            (e) => e.message,
            'message',
            contains('empty answer'),
          ),
        ),
      );
    },
  );

  test('long posts are cut before they are sent', () {
    final msg = SemanticClient.userMessage('a' * 10000, ['x']);
    expect(msg.length, lessThan(SemanticClient.maxPostChars + 200));
  });

  group('MatchEvent', () {
    final post = Post(chatId: -1, messageId: 1, date: 1, text: 't');
    const keyword = MatchedRule(
      name: 'kw',
      priority: RulePriority.silent,
      readAloud: false,
    );
    const semantic = MatchedRule(
      name: 'ai',
      priority: RulePriority.urgent,
      readAloud: true,
      semanticPrompt: 'rate decisions',
    );

    test('round-trips over the wire with its prompts', () {
      final e = MatchEvent.decode(
        MatchEvent.of(post, [keyword, semantic]).encode(),
      );
      expect(e.ruleNames, ['kw', 'ai']);
      expect(e.pendingSemantic, [(1, 'rate decisions')]);
      expect(e.priority, RulePriority.urgent);
      expect(e.readAloud, isTrue);
    });

    test('a failed or negative check skips only the semantic rule', () {
      final e = MatchEvent.of(post, [keyword, semantic]);
      final skipped = e.withSemanticVerdicts(const {})!;
      expect(skipped.ruleNames, ['kw']);
      expect(skipped.priority, RulePriority.silent);
      expect(skipped.readAloud, isFalse);

      final confirmed = e.withSemanticVerdicts(const {1})!;
      expect(confirmed.ruleNames, ['kw', 'ai']);
      expect(confirmed.priority, RulePriority.urgent);
      expect(confirmed.pendingSemantic, isEmpty);

      expect(
        MatchEvent.of(post, [semantic]).withSemanticVerdicts(const {}),
        isNull,
      );
    });
  });

  test('engine: a semantic rule without keywords passes every post on', () {
    final engine = RuleEngine()
      ..update(
        rules: const [
          RuleSpec(
            id: 1,
            name: 'ai',
            condition: And([]),
            semanticPrompt: 'anything about rates',
          ),
        ],
        watched: {-1},
      );
    final m = engine.evaluate(
      Post(chatId: -1, messageId: 1, date: 1, text: 'whatever'),
    )!;
    expect(MatchEvent.fromMatch(m).pendingSemantic, [
      (0, 'anything about rates'),
    ]);
  });
}
