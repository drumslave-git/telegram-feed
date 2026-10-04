import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/shared_media.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fixtures.dart';

/// A channel whose posts are found by kind and by words, and counted by kind, the way
/// Telegram answers. It records what it was asked for.
class SharedGateway extends ChannelsGateway {
  SharedGateway(this.shared) : super(const []);
  final List<Post> shared;

  /// Every search, as `kind|words`.
  final asked = <String>[];

  static bool _is(HistoryFilter f, Post p) {
    final m = p.media;
    return switch (f) {
      HistoryFilter.any => true,
      HistoryFilter.photoAndVideo =>
        m is PhotoMedia || (m is VideoMedia && !m.isAnimation),
      HistoryFilter.photo => m is PhotoMedia,
      HistoryFilter.video => m is VideoMedia && !m.isAnimation,
      HistoryFilter.animation => m is VideoMedia && m.isAnimation,
      HistoryFilter.document => m is DocumentMedia,
      HistoryFilter.url => p.text.contains('http'),
      HistoryFilter.audio => m is AudioMedia && !m.isVoice,
      HistoryFilter.voice => m is AudioMedia && m.isVoice,
    };
  }

  @override
  Future<Map<HistoryFilter, int>> mediaCounts(int chatId) async => {
    for (final kind in sharedMediaKinds)
      kind: shared.where((p) => _is(kind, p)).length,
  };

  @override
  Future<SearchPage> searchHistory(
    int chatId, {
    String query = '',
    HistoryFilter filter = HistoryFilter.any,
    int fromMessageId = 0,
    int limit = 30,
  }) async {
    asked.add('${filter.name}|$query');
    final found = [
      for (final p in shared)
        if (_is(filter, p) &&
            (query.isEmpty ||
                p.text.toLowerCase().contains(query.toLowerCase()) ||
                (p.media is DocumentMedia &&
                    (p.media! as DocumentMedia).fileName.contains(query))) &&
            (fromMessageId == 0 || p.messageId < fromMessageId))
          p,
    ];
    final page = found.take(limit).toList();
    return SearchPage(
      posts: page,
      totalCount: found.length,
      nextFromMessageId: page.length < found.length ? page.last.messageId : 0,
    );
  }
}

void main() {
  FileRef file(int id) =>
      FileRef(id: id, remoteId: 'r$id', size: 10, width: 40, height: 40);
  Post photo(int id) => Post(
    chatId: -1,
    messageId: id,
    // A day apart, the newest first.
    date: 1700000000 + id * 86400,
    text: '',
    media: PhotoMedia(sizes: [file(id)]),
  );
  Post video(int id) => Post(
    chatId: -1,
    messageId: id,
    date: 1700000000 + id * 86400,
    text: '',
    media: VideoMedia(
      file: file(id),
      durationSeconds: 9,
      thumbnail: file(1000 + id),
    ),
  );
  Post doc(int id, String name) => Post(
    chatId: -1,
    messageId: id,
    date: 1700000000 + id * 86400,
    text: '',
    media: DocumentMedia(
      file: file(id),
      fileName: name,
      mimeType: 'application/pdf',
    ),
  );

  Future<void> settle(WidgetTester tester) => tester.runAsync(() async {
    for (var i = 0; i < 3; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await tester.pump();
    }
  });

  /// Lets a tab change, a menu or a page of results happen. The pictures of this gateway
  /// never finish loading, so nothing is waited out.
  Future<void> step(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));
    await settle(tester);
  }

  Future<void> show(
    WidgetTester tester,
    SharedGateway gw, {
    void Function(Post post)? onShowInChat,
  }) async {
    mediaGridColumns.value = 3;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SharedMediaTabs(
            gateway: gw,
            chatIds: const [-1],
            titles: const {-1: 'News'},
            onShowInChat: onShowInChat,
          ),
        ),
      ),
    );
    await settle(tester);
    await settle(tester);
  }

  testWidgets('a kind nobody posted has no tab, and GIFs have their own', (
    tester,
  ) async {
    final gw = SharedGateway([
      photo(5),
      doc(4, 'report.pdf'),
      Post(
        chatId: -1,
        messageId: 3,
        date: 3,
        text: '',
        media: VideoMedia(
          file: file(3),
          durationSeconds: 2,
          isAnimation: true,
          thumbnail: file(1003),
        ),
      ),
    ]);
    await show(tester, gw);
    expect(find.widgetWithText(Tab, 'Media'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Files'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'GIFs'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Links'), findsNothing);
    expect(find.widgetWithText(Tab, 'Music'), findsNothing);
    expect(find.widgetWithText(Tab, 'Voice'), findsNothing);
    // The GIF is not among the photos and videos.
    expect(find.byType(MediaTile), findsOneWidget);

    await tester.tap(find.widgetWithText(Tab, 'GIFs'));
    await step(tester);
    expect(gw.asked.last, 'animation|');
    expect(find.byType(MediaTile), findsOneWidget);
  });

  testWidgets('a channel that shared nothing says so and has no tabs', (
    tester,
  ) async {
    await show(tester, SharedGateway(const []));
    expect(find.byType(Tab), findsNothing);
    expect(find.text('Nothing here yet.'), findsOneWidget);
  });

  testWidgets('the media tab shows photos, videos or both', (tester) async {
    final gw = SharedGateway([photo(5), video(4), photo(3)]);
    await show(tester, gw);
    expect(find.byType(MediaTile), findsNWidgets(3));

    await tester.tap(find.byTooltip('Photos and videos'));
    await step(tester);
    await tester.tap(find.text('Videos'));
    await step(tester);
    await settle(tester);
    // Videos were switched off: photos alone.
    expect(gw.asked.last, 'photo|');
    expect(find.byType(MediaTile), findsNWidgets(2));

    // Switching the last one off switches the other on.
    await tester.tap(find.byTooltip('Photos and videos'));
    await step(tester);
    await tester.tap(find.text('Photos'));
    await step(tester);
    await settle(tester);
    expect(gw.asked.last, 'video|');
    expect(find.byType(MediaTile), findsOneWidget);

    // The button belongs to the Media tab only.
    expect(find.byTooltip('Photos and videos'), findsOneWidget);
  });

  testWidgets('a pinch changes the number of columns, from two to nine', (
    tester,
  ) async {
    final gw = SharedGateway([for (var id = 30; id > 0; id--) photo(id)]);
    await show(tester, gw);
    double tileWidth() => tester.getSize(find.byType(MediaTile).first).width;
    final three = tileWidth();

    // Two fingers move apart: larger pictures, fewer columns.
    final centre = tester.getCenter(find.byType(GridView));
    final a = await tester.startGesture(centre - const Offset(40, 0));
    final b = await tester.startGesture(centre + const Offset(40, 0));
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await a.moveBy(const Offset(-20, 0));
      await b.moveBy(const Offset(20, 0));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await tester.pump();
    expect(mediaGridColumns.value, 2);
    expect(tileWidth(), greaterThan(three));

    // And together again: more columns, never more than nine.
    final c = await tester.startGesture(centre - const Offset(300, 0));
    final d = await tester.startGesture(centre + const Offset(300, 0));
    await tester.pump();
    for (var i = 0; i < 28; i++) {
      await c.moveBy(const Offset(10, 0));
      await d.moveBy(const Offset(-10, 0));
      await tester.pump();
    }
    await c.up();
    await d.up();
    await tester.pump();
    expect(mediaGridColumns.value, greaterThan(3));
    expect(mediaGridColumns.value, lessThanOrEqualTo(9));
    expect(tileWidth(), lessThan(three));
    mediaGridColumns.value = 3;
  });

  testWidgets('files are searched by words', (tester) async {
    final gw = SharedGateway([
      doc(5, 'ferries.pdf'),
      doc(4, 'budget.pdf'),
      photo(3),
    ]);
    await show(tester, gw);
    await tester.tap(find.widgetWithText(Tab, 'Files'));
    await step(tester);
    expect(find.text('ferries.pdf'), findsOneWidget);
    expect(find.text('budget.pdf'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'budget');
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    expect(gw.asked.last, 'document|budget');
    expect(find.text('budget.pdf'), findsOneWidget);
    expect(find.text('ferries.pdf'), findsNothing);

    await tester.enterText(find.byType(TextField), 'nothing like it');
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    expect(find.text('Nothing found for "nothing like it".'), findsOneWidget);
    // The field stays, to search for something else.
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('the media grid has no search field', (tester) async {
    await show(tester, SharedGateway([photo(5)]));
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('a long press on an item offers to show it in the chat', (
    tester,
  ) async {
    recordHaptics(tester);
    final shown = <int>[];
    final gw = SharedGateway([photo(5), doc(4, 'report.pdf')]);
    await show(tester, gw, onShowInChat: (post) => shown.add(post.messageId));

    await tester.longPress(find.byType(MediaTile));
    await step(tester);
    await tester.tap(find.text('Show in chat'));
    await step(tester);
    expect(shown, [5]);

    await tester.tap(find.widgetWithText(Tab, 'Files'));
    await step(tester);
    await tester.longPress(find.text('report.pdf'));
    await step(tester);
    await tester.tap(find.text('Show in chat'));
    await step(tester);
    expect(shown, [5, 4]);
  });

  testWidgets('without a way to the chat the items have no menu', (
    tester,
  ) async {
    await show(tester, SharedGateway([photo(5)]));
    await tester.longPress(find.byType(MediaTile));
    await step(tester);
    expect(find.text('Show in chat'), findsNothing);
  });

  testWidgets(
    'the scroller along the grid runs through it and names the month',
    (tester) async {
      // Ninety days of photos, newest first: three months at least.
      final gw = SharedGateway([for (var id = 90; id > 0; id--) photo(id)]);
      await show(tester, gw);
      await tester.pump();
      final handle = find.byKey(const ValueKey('date-scroller'));
      expect(handle, findsOneWidget);
      // Nothing is named while the grid is only looked at.
      expect(find.textContaining('2024'), findsNothing);
      expect(find.textContaining('2023'), findsNothing);
      final first = tester.getTopLeft(find.byType(MediaTile).first);

      final drag = await tester.startGesture(tester.getCenter(handle));
      await drag.moveBy(const Offset(0, 30));
      await tester.pump();
      await drag.moveBy(const Offset(0, 200));
      await tester.pump();
      await tester.pump();
      // The grid moved, and the month of what is on top stands beside the handle.
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              RegExp(r'^[A-Z][a-z]+ 20\d\d$').hasMatch(w.data ?? ''),
        ),
        findsOneWidget,
      );
      await drag.up();
      await tester.pump();
      await tester.pump();
      expect(tester.getTopLeft(find.byType(MediaTile).first), isNot(first));
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              RegExp(r'^[A-Z][a-z]+ 20\d\d$').hasMatch(w.data ?? ''),
        ),
        findsNothing,
      );
    },
  );
}
