import 'dart:async';
import 'dart:math' as math;

import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

/// Feeds with their unread counts: the posts newer than the feed's read mark, as the
/// feed's timeline would show them, or the channels that have such posts — the
/// "Count unread posts" switch of Notifications and sounds decides which the badges show
/// (J-1), as the official app's "Count unread messages" does.
final class FeedsController extends ChangeNotifier {
  FeedsController({required this.db, required this.gateway}) {
    _feedsSub = db.watchFeeds().listen((f) {
      _feeds = f;
      _schedule();
    });
    _marksSub = db.watchAllReadMarks().listen((_) => _schedule());
    _modeSub = db.watchSetting(SettingKeys.countUnreadPosts).listen((v) {
      final posts = v != 'false';
      if (posts == _countPosts) return;
      _countPosts = posts;
      // A count of channels stopped at the first post of each; posts start over.
      _unread.clear();
      notifyListeners();
      _schedule();
    });
    _postsSub = gateway.postEvents.listen(_onPost);
    unawaited(refreshChannels());
  }

  final AppDatabase db;
  final TelegramGateway gateway;
  late final StreamSubscription<List<Feed>> _feedsSub;
  late final StreamSubscription<PostEvent> _postsSub;
  late final StreamSubscription<List<FeedReadMark>> _marksSub;
  late final StreamSubscription<String?> _modeSub;
  List<Feed> _feeds = const [];
  final _lastIds = <int, int>{};
  bool _channelsLoaded = false;
  bool _countPosts = true;
  String? error;

  /// Counted posts per (feed, channel); dropped with the source.
  final _unread = <(int, int), _Unread>{};
  Map<int, int> _posts = const {};
  Map<int, int> _channels = const {};

  /// A channel is counted up to this many unread posts; the badge says "999+" by then.
  static const cap = 1000;

  List<Feed> get feeds => _feeds;
  bool get channelsLoaded => _channelsLoaded;

  /// Whether the badges count posts (the default) or channels with unread posts.
  bool get countPosts => _countPosts;

  /// What a feed's badge shows: its unread posts, or its channels with unread posts.
  int unreadOf(int feedId) => (_countPosts ? _posts : _channels)[feedId] ?? 0;

  /// Channels of the feed with unread posts, whichever the badge counts.
  int unreadChannelsOf(int feedId) => _channels[feedId] ?? 0;

  /// What the Feeds tab shows: every feed's unread posts together, or the feeds with any.
  int get unreadOnTab => _countPosts
      ? _feeds.fold(0, (n, f) => n + unreadOf(f.id))
      : _feeds.where((f) => unreadChannelsOf(f.id) > 0).length;

  Future<void> refreshChannels() async {
    try {
      for (final c in await gateway.myChannels()) {
        _lastIds[c.chatId] = math.max(_lastIds[c.chatId] ?? 0, c.lastMessageId);
      }
      _channelsLoaded = true;
      error = null;
    } on TelegramException catch (e) {
      error = e.message;
    }
    _schedule();
  }

  /// A new post is counted where it is seen, without asking for the history again; a
  /// deleted one stops counting, or the reader could never read past it.
  void _onPost(PostEvent e) {
    switch (e) {
      case PostAdded(:final post):
        final id = post.messageId;
        _lastIds[post.chatId] = math.max(_lastIds[post.chatId] ?? 0, id);
        for (final entry in _unread.entries) {
          if (entry.key.$2 == post.chatId) entry.value.arrived(post);
        }
      case PostsDeleted(:final chatId, :final messageIds):
        for (final entry in _unread.entries) {
          if (entry.key.$2 == chatId) entry.value.deleted(messageIds);
        }
      case PostEdited():
        return;
    }
    _schedule();
  }

  bool _running = false;
  bool _again = false;

  /// One count at a time; a change during a count runs it once more afterwards.
  void _schedule() {
    if (_running) {
      _again = true;
      return;
    }
    unawaited(_recount());
  }

  Future<void> _recount() async {
    _running = true;
    try {
      do {
        _again = false;
        await _count();
      } while (_again);
    } finally {
      _running = false;
    }
  }

  /// Two steps: what is known at once (every channel whose newest post is past the mark
  /// has news, as far as anyone can tell yet), then the posts, counted in parallel.
  Future<void> _count() async {
    final pairs = <_Pair>[];
    final seen = <(int, int)>{};
    for (final f in _feeds) {
      final filter = FeedFilter.decode(f.filterJson);
      for (final m in (await db.readMarks(f.id)).entries) {
        final key = (f.id, m.key);
        seen.add(key);
        final last = _lastIds[m.key] ?? 0;
        _Unread? u;
        // Channels are counted from the history too, one page at most: a newest post
        // id past the mark can be one the timeline does not show.
        if (last > m.value) {
          u = _unread[key];
          if (u == null || u.filterJson != f.filterJson || m.value < u.mark) {
            u = _unread[key] = _Unread(m.value, f.filterJson, filter);
          } else {
            u.readTo(m.value);
          }
        } else {
          _unread.remove(key);
        }
        pairs.add(_Pair(f.id, m.key, m.value, last, u));
      }
    }
    _unread.removeWhere((key, _) => !seen.contains(key));
    _publish(pairs);
    final enough = _countPosts ? cap : 1;
    await Future.wait([
      for (final p in pairs)
        if (p.unread case final u?)
          u.fill(gateway, p.chat, last: p.last, enough: enough),
    ]);
    _publish(pairs);
  }

  void _publish(List<_Pair> pairs) {
    final posts = {for (final f in _feeds) f.id: 0};
    final channels = {for (final f in _feeds) f.id: 0};
    for (final p in pairs) {
      final u = p.unread;
      final bool news;
      if (p.last <= p.mark) {
        news = false;
      } else if (u != null && (u.complete || u.rows.isNotEmpty)) {
        news = u.rows.isNotEmpty;
      } else {
        // Not counted yet: shown at once, so the line under the feed's name does not
        // appear only when the count is done; a filter may still take it away.
        news = true;
      }
      if (news) channels[p.feed] = (channels[p.feed] ?? 0) + 1;
      posts[p.feed] = (posts[p.feed] ?? 0) + (u?.rows.length ?? 0);
    }
    _posts = posts;
    _channels = channels;
    notifyListeners();
  }

  @override
  void dispose() {
    _feedsSub.cancel();
    _postsSub.cancel();
    _marksSub.cancel();
    _modeSub.cancel();
    super.dispose();
  }
}

/// One channel of one feed in a count.
final class _Pair {
  const _Pair(this.feed, this.chat, this.mark, this.last, this.unread);
  final int feed;
  final int chat;
  final int mark;
  final int last;

  /// Null where nothing is newer than the mark.
  final _Unread? unread;
}

/// The unread posts of one channel in one feed: the rows its timeline would show above the
/// read mark, an album being one row, and a post the feed's filter hides being none.
final class _Unread {
  _Unread(this.mark, this.filterJson, this.filter) : upTo = mark;

  int mark;
  final String? filterJson;
  final FeedFilter filter;

  /// Newest message id looked at: everything up to it is counted.
  int upTo;

  /// The history was asked: [upTo] is the newest post there was then.
  bool complete = false;

  /// The unread rows, oldest first: the album (0 for a single post) and the newest message
  /// of the row, which is what the read mark has to pass.
  final rows = <({int album, int newest})>[];

  /// The album of the last message looked at, and whether that album is counted already.
  int _album = 0;
  bool _albumCounted = false;

  /// The reader got further: rows at or below the mark are read.
  void readTo(int newMark) {
    if (newMark <= mark) return;
    mark = newMark;
    rows.removeWhere((r) => r.newest <= newMark);
    if (newMark > upTo) {
      upTo = newMark;
      _album = 0;
    }
  }

  void _add(Post p) {
    if (p.messageId <= upTo) return;
    upTo = p.messageId;
    final album = p.albumId;
    if (album != 0 && album == _album) {
      if (_albumCounted) {
        rows[rows.length - 1] = (album: album, newest: p.messageId);
      } else if (filter.allows(p)) {
        rows.add((album: album, newest: p.messageId));
        _albumCounted = true;
      }
      return;
    }
    _album = album;
    _albumCounted = filter.allows(p);
    if (_albumCounted) rows.add((album: album, newest: p.messageId));
  }

  /// A post that came in now; a count that has not asked the history yet fetches it with
  /// the rest.
  void arrived(Post p) {
    if (complete) _add(p);
  }

  void deleted(List<int> ids) {
    final gone = ids.toSet();
    rows.removeWhere((r) => gone.contains(r.newest));
  }

  /// Asks the history for what is newer than [upTo], newest first, down to what was
  /// counted already or until [enough] rows are found. Newest first because TDLib pages
  /// newer posts only from a message that exists: from a mark of 0 (a channel never read)
  /// it would answer with nothing. At the cap the rows are the newest ones, so the count
  /// stays right as the mark climbs into them.
  Future<void> fill(
    TelegramGateway gateway,
    int chatId, {
    required int last,
    required int enough,
  }) async {
    if (last <= upTo && complete) return;
    // Most channels have a few new posts: a short first page, then long ones.
    var page = 20;
    final newer = <Post>[];
    var shown = 0;
    var from = 0;
    while (true) {
      List<Post> got;
      try {
        got = await gateway.history(chatId, fromMessageId: from, limit: page);
      } on TelegramException catch (e) {
        debugPrint('feeds: unread of $chatId: ${e.message}');
        return;
      }
      final fresh = [
        for (final p in got)
          if (p.messageId > upTo) p,
      ];
      newer.addAll(fresh);
      shown += fresh.where(filter.allows).length;
      if (fresh.length < got.length || got.length < page) break;
      if (rows.length + shown >= enough) break;
      from = got.last.messageId;
      page = 100;
    }
    newer.sort((a, b) => a.messageId.compareTo(b.messageId));
    for (final p in newer) {
      _add(p);
    }
    // The newest ones are what the count needs; the oldest go over the cap.
    if (rows.length > enough) rows.removeRange(0, rows.length - enough);
    if (rows.isEmpty && last > mark) {
      debugPrint(
        'feeds: $chatId has $last past mark $mark, but no post to show',
      );
    }
    // The newest post Telegram named may be one history does not list (a service
    // message); counted up to it, so the next count does not ask again.
    upTo = math.max(upTo, last);
    complete = true;
  }
}
