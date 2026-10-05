import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:push_runner/push_runner.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  test('the queue holds pushes, buttons and token changes; anything else is '
      'left out', () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      PushRunner.channel,
      (call) async => call.method == 'take'
          ? [
              jsonEncode({'push': '{"p":"x"}'}),
              jsonEncode({
                'action': {'actionId': 'listen', 'payload': 'ref'},
              }),
              jsonEncode({'register': true}),
              'not json',
              jsonEncode({'other': 1}),
            ]
          : null,
    );
    addTearDown(
      () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
        PushRunner.channel,
        null,
      ),
    );
    final items = await PushRunner.take();
    expect(items, hasLength(3));
    expect((items[0] as PushMessage).payload, '{"p":"x"}');
    expect((items[1] as PushAction).response, {
      'actionId': 'listen',
      'payload': 'ref',
    });
    expect(items[2], isA<PushRegister>());
  });

  test('without a platform side there is no token', () async {
    expect(await PushRunner.token(), isNull);
  });

  test('a button pressed while nothing runs is queued as an action', () async {
    Object? queued;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      PushRunner.channel,
      (call) async => queued = call.arguments,
    );
    addTearDown(
      () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
        PushRunner.channel,
        null,
      ),
    );
    await PushRunner.startRun({'actionId': 'listen'});
    expect(jsonDecode(queued! as String), {
      'action': {'actionId': 'listen'},
    });
  });
}
