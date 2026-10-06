import 'dart:ui';

import 'package:core/core.dart';
import 'package:fake_telegram/fake_telegram.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/service/core_lock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => IsolateNameServer.removePortNameMapping(corePortName));

  test('one engine at a time holds the lock; a second waits, and gets it once '
      'the first lets go', () async {
    final first = await CoreLock.take();
    expect(first, isNotNull);
    expect(CoreLock.held, isTrue);

    // Without force, a wait that runs out gets nothing.
    expect(
      await CoreLock.take(
        wait: const Duration(milliseconds: 300),
        standDownHolder: false,
      ),
      isNull,
    );

    final second = CoreLock.take(
      wait: const Duration(seconds: 5),
      standDownHolder: false,
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    CoreLock.release(first);
    final got = await second;
    expect(got, isNotNull);
    CoreLock.release(got);
    expect(CoreLock.held, isFalse);
  });

  test('a holder that never lets go is taken as gone with force; a cancelled '
      'wait gets nothing', () async {
    final stale = await CoreLock.take();
    var cancel = false;
    final waiting = CoreLock.take(
      wait: const Duration(seconds: 5),
      standDownHolder: false,
      cancelled: () => cancel,
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));
    cancel = true;
    expect(await waiting, isNull);

    final forced = await CoreLock.take(
      wait: const Duration(milliseconds: 300),
      force: true,
      standDownHolder: false,
    );
    expect(forced, isNotNull);
    // The stale holder's release no longer takes the lock from the new one.
    CoreLock.release(stale);
    expect(CoreLock.held, isTrue);
    CoreLock.release(forced);
  });

  test('the core the holder registered is asked to hand TDLib back', () async {
    var handedBack = 0;
    final server = CoreServer(
      ChannelsGateway(const []),
      onShutdown: () async => handedBack++,
    );
    IsolateNameServer.registerPortWithName(server.sendPort, corePortName);
    final holder = await CoreLock.take();

    expect(await CoreLock.standDown(), isTrue);
    expect(handedBack, 1);
    expect(IsolateNameServer.lookupPortByName(corePortName), isNull);
    expect(await CoreLock.standDown(), isFalse);
    CoreLock.release(holder);
  });
}
