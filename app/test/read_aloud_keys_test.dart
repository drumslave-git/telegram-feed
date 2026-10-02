import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/service/read_aloud_keys.dart';

/// The service holds the media session that takes the volume keys only while something is
/// read, and a key's stop reaches the queue.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('tf/readAloudKeys');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<Object?> watched;

  setUp(() {
    watched = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'watch') watched.add(call.arguments);
      return null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('the session is held while reading and let go after', () async {
    final keys = ReadAloudKeys(onStop: () {});
    await keys.watch(true);
    await keys.watch(true); // the next post: still held, not asked again
    await keys.watch(false);
    await keys.watch(false);
    expect(watched, [true, false]);
  });

  test('volume down stops', () async {
    var stops = 0;
    ReadAloudKeys(onStop: () => stops++);
    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(const MethodCall('stop')),
      (_) {},
    );
    expect(stops, 1);
  });

  test('without the native side the keys keep their meaning', () async {
    messenger.setMockMethodCallHandler(channel, null);
    final keys = ReadAloudKeys(onStop: () {});
    await keys.watch(true);
    await keys.watch(false);
  });
}
