import 'dart:io';

import 'package:fake_telegram/fake_telegram.dart';
import 'package:telegram_gateway/telegram_gateway.dart';
import 'package:test/test.dart';

void main() {
  late Directory media;
  late FakeTelegram tg;

  setUp(() async {
    media = await Directory.systemTemp.createTemp('fake-media');
    File('${media.path}/photo1.png').writeAsBytesSync(List.filled(10, 1));
    tg = FakeTelegram(mediaDirectory: media.path, arrivalEvery: null);
  });

  tearDown(() async {
    await tg.close();
    await media.delete(recursive: true);
  });

  test('logs in with any number and the fixture code', () async {
    final states = <AuthState>[];
    final sub = tg.authState.listen(states.add);
    await Future<void>.delayed(Duration.zero);
    await tg.setPhoneNumber('+15550100');
    await expectLater(tg.checkCode('00000'), throwsA(isA<TelegramException>()));
    await tg.checkCode(fakeLoginCode);
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(states.map((s) => s.runtimeType), [
      AuthWaitPhoneNumber,
      AuthWaitCode,
      AuthReady,
    ]);
    expect((states[1] as AuthWaitCode).phoneNumber, '+15550100');
  });

  test('starts logged in when asked', () async {
    final ready = FakeTelegram(
      mediaDirectory: media.path,
      loggedIn: true,
      arrivalEvery: null,
    );
    expect(await ready.authState.first, isA<AuthReady>());
    await ready.close();
  });

  test('lists the channels, folders and the archive', () async {
    final channels = await tg.myChannels();
    expect(channels.map((c) => c.title), [
      'Harbour Times',
      'Circuit Weekly',
      'Northfield Gazette',
      'Wire',
    ]);
    expect((await tg.chatFolders()).map((f) => f.title), ['News', 'Alerts']);
    expect((await tg.archivedChannels()).single.title, 'Old Ledger');
    // The newest three posts of a channel are unread: the divider has something to divide.
    expect(channels.map((c) => c.unreadCount), [3, 3, 3, 2]);
  });

  test('pages a history and finds every kind of post', () async {
    final first = await tg.history(FakeChats.circuitWeekly, limit: 10);
    expect(first.length, 10);
    final second = await tg.history(
      FakeChats.circuitWeekly,
      fromMessageId: first.last.messageId,
      limit: 10,
    );
    expect(second.length, 6);
    final harbour = await tg.history(FakeChats.harbourTimes);
    expect(harbour.map((p) => p.messageId), [
      11,
      10,
      9,
      8,
      7,
      6,
      5,
      4,
      3,
      2,
      1,
    ]);
    expect(harbour.where((p) => p.media is VideoMedia), hasLength(1));
    expect(harbour.where((p) => p.albumId == 7), hasLength(3));
    expect(harbour.where((p) => p.linkPreview != null), hasLength(1));
    expect(harbour.where((p) => p.forwardedFrom != null), hasLength(1));
    expect(harbour.where((p) => p.replyTo != null), hasLength(1));
    expect(harbour.where((p) => p.media is DocumentMedia), hasLength(1));
  });

  test('search honours the filter', () async {
    final media = await tg.searchHistory(
      FakeChats.harbourTimes,
      filter: HistoryFilter.photoAndVideo,
    );
    expect(media.posts, hasLength(5));
    final links = await tg.searchHistory(
      FakeChats.harbourTimes,
      filter: HistoryFilter.url,
    );
    expect(links.posts, hasLength(2));
    final words = await tg.searchAllChannels(query: 'pier');
    expect(words.posts.map((p) => p.chatId).toSet(), {FakeChats.harbourTimes});
  });

  test(
    'serves a file of the media directory and reports a missing one',
    () async {
      final photo =
          (await tg.history(FakeChats.harbourTimes)).last.media! as PhotoMedia;
      final ref = await tg.download(photo.sizes.first);
      expect(ref.localPath, '${media.path}/photo1.png');
      expect(ref.size, 10);
      expect(await tg.downloadedPrefix(ref.id, 4), 6);
      final video =
          (await tg.history(FakeChats.harbourTimes))[6].media! as VideoMedia;
      await expectLater(
        tg.download(video.file),
        throwsA(isA<TelegramException>()),
      );
    },
  );

  test('a reaction edits the post', () async {
    final edits = <PostEvent>[];
    final sub = tg.postEvents.listen(edits.add);
    await tg.react(FakeChats.harbourTimes, 11, '🔥');
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    final edited = (edits.single as PostEdited).post;
    expect(
      edited.reactions.where((r) => r.emoji == '🔥').single.chosen,
      isTrue,
    );
    expect(edited.reactions.where((r) => r.emoji == '👍').single.count, 31);
  });

  test('the market post has a thread that takes a reply', () async {
    final thread = await tg.discussion(FakeChats.harbourTimes, 11);
    expect(thread, isNotNull);
    expect(await tg.discussion(FakeChats.harbourTimes, 10), isNull);
    expect(await tg.threadHistory(thread!), hasLength(2));
    final live = tg.comments.first;
    await tg.reply(thread, 'Yes, with mackerel.');
    expect((await live).isOutgoing, isTrue);
    expect(await tg.threadHistory(thread), hasLength(3));
  });

  test('a post arrives on the wire', () async {
    final added = tg.postEvents.first;
    tg.arriveOnWire();
    final post = ((await added) as PostAdded).post;
    expect(post.chatId, FakeChats.wire);
    expect(post.text, 'Breaking: fixture post 1 from the wire.');
    expect((await tg.history(FakeChats.wire)).first.messageId, 3);
  });

  test('saving a post copies it into Saved Messages', () async {
    await tg.saveToSavedMessages(FakeChats.harbourTimes, [11]);
    final saved = await tg.history(FakeChats.savedMessages);
    expect(saved.first.forwardedFrom?.title, 'Harbour Times');
    expect(saved, hasLength(2));
  });
}
