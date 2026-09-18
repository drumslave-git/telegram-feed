import 'dart:convert';

import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:telegram_feed/ai/semantic_gate.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

final class MemorySecrets implements SecretStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null || value.isEmpty) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}

void main() {
  late AppDatabase db;
  late MemorySecrets secrets;
  var answer = '2';
  var status = 200;
  final requests = <http.Request>[];

  SemanticGate gate() => SemanticGate(
    db: db,
    secrets: secrets,
    clock: () => DateTime.fromMillisecondsSinceEpoch(1000),
    client: SemanticClient(
      client: MockClient((r) async {
        requests.add(r);
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': answer},
              },
            ],
            'error': {'message': 'bad key'},
          }),
          status,
        );
      }),
    ),
  );

  final post = Post(chatId: -1, messageId: 1, date: 1, text: 'rates cut');
  const keyword = MatchedRule(
    name: 'kw',
    priority: RulePriority.silent,
    readAloud: false,
  );
  const sports = MatchedRule(
    name: 'sports',
    priority: RulePriority.normal,
    readAloud: false,
    semanticPrompt: 'sports news',
  );
  const rates = MatchedRule(
    name: 'rates',
    priority: RulePriority.urgent,
    readAloud: true,
    semanticPrompt: 'rate decisions',
  );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    secrets = MemorySecrets()..values[AiKeys.apiKeySecret] = 'sk-test';
    await db.setSetting(AiKeys.baseUrl, 'https://llm.example/v1');
    await db.setSetting(AiKeys.model, 'small');
    answer = '2';
    status = 200;
    requests.clear();
  });
  tearDown(() => db.close());

  test('keyword-only matches pass through without a request', () async {
    final m = MatchEvent.of(post, const [keyword]);
    expect(await gate().resolve(m), same(m));
    expect(requests, isEmpty);
  });

  test('one request decides all semantic rules of the post', () async {
    final m = await gate().resolve(
      MatchEvent.of(post, const [keyword, sports, rates]),
    );
    expect(requests, hasLength(1));
    expect(requests.single.headers['authorization'], 'Bearer sk-test');
    expect(m!.ruleNames, ['kw', 'rates']);
    expect(m.priority, RulePriority.urgent);
    expect(await db.setting(AiKeys.lastError), isNull);
  });

  test(
    'a failing check skips the semantic rules only and records why',
    () async {
      status = 401;
      final g = gate();
      final m = await g.resolve(MatchEvent.of(post, const [keyword, rates]));
      expect(m!.ruleNames, ['kw']);
      expect(await g.resolve(MatchEvent.of(post, const [rates])), isNull);
      final failure = AiFailure.decode(await db.setting(AiKeys.lastError))!;
      expect(failure.message, contains('401'));
      expect(failure.at.millisecondsSinceEpoch, 1000);

      // The next successful check clears the warning.
      status = 200;
      await g.resolve(MatchEvent.of(post, const [rates]));
      expect(await db.setting(AiKeys.lastError), isNull);
    },
  );

  test('without an endpoint the rule is skipped and nothing is sent', () async {
    await db.setSetting(AiKeys.baseUrl, '');
    expect(await gate().resolve(MatchEvent.of(post, const [rates])), isNull);
    expect(requests, isEmpty);
    expect(await db.setting(AiKeys.lastError), contains('not set up'));
  });
}
