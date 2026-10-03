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

    // An older post seen later counts its view and leaves the position where it is.
    m.read(
      {-1: 10},
      viewed: {
        -1: [10],
      },
    );
    await m.flush();
    expect(gw.viewed.length, 2);
    expect(gw.viewsCounted, ['-1:10']);
    expect(gw.readPositions, {-1: 30, -2: 5});
  });

  test('a post on the screen counts a view once, read or not', () async {
    final m = ReadMarker(gateway: gw);
    // 40 is on the screen but not far enough in to be read; 30 is read.
    m.read(
      {-1: 30},
      viewed: {
        -1: [40, 30, 20],
      },
    );
    await m.flush();
    expect(gw.viewed, ['-1:20,30']);
    expect(gw.viewsCounted, ['-1:40']);
    expect(gw.readPositions, {-1: 30});

    // Still on the screen at the next scroll event: nothing is sent again.
    m.read(
      const {},
      viewed: {
        -1: [40, 30, 20],
      },
    );
    await m.flush();
    expect(gw.viewed, ['-1:20,30']);
    expect(gw.viewsCounted, ['-1:40']);

    // Read a moment later: the position moves, the view is not counted twice.
    m.read(
      {-1: 40},
      viewed: {
        -1: [40],
      },
    );
    await m.flush();
    expect(gw.viewed, ['-1:20,30', '-1:40']);
    expect(gw.viewsCounted, ['-1:40']);
    expect(gw.readPositions, {-1: 40});
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
