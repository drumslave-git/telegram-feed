import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/read_marker.dart';

import 'fixtures.dart';

class ViewedGateway extends ChannelsGateway {
  ViewedGateway() : super(const []);
  final viewed = <String>[];
  @override
  Future<void> markViewed(int chatId, List<int> messageIds) async {
    viewed.add('$chatId:${messageIds.join(',')}');
    await super.markViewed(chatId, messageIds);
  }
}

void main() {
  late ViewedGateway gw;

  setUp(() => gw = ViewedGateway());

  test('reading reaches Telegram once, after the debounce', () async {
    final m = ReadMarker(
      gateway: gw,
      debounce: const Duration(milliseconds: 20),
    );
    m.read(
      {-1: 30, -2: 5},
      viewed: {
        -1: [30, 20],
        -2: [5, 4, 3],
      },
    );
    expect(gw.viewed, isEmpty); // not yet
    await Future<void>.delayed(const Duration(milliseconds: 80));
    // The posts on the screen, for their views; the newest read one moves the position.
    expect(gw.viewed, unorderedEquals(['-1:20,30', '-2:3,4,5']));
    expect(gw.readPositions, {-1: 30, -2: 5});

    // Older posts seen later do not move the position back or report again.
    m.read(
      {-1: 10},
      viewed: {
        -1: [10],
      },
    );
    await m.flush();
    expect(gw.viewed.length, 2);
    expect(gw.readPositions, {-1: 30, -2: 5});
  });

  test(
    'a channel passed over, never on the screen, is read up to there',
    () async {
      final m = ReadMarker(gateway: gw);
      m.read(
        {-1: 30, -2: 12},
        viewed: {
          -1: [30],
        },
      );
      await m.dispose();
      expect(gw.viewed, unorderedEquals(['-1:30', '-2:12']));
      expect(gw.readPositions, {-1: 30, -2: 12});
    },
  );
}
