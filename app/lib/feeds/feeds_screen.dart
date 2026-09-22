import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

/// Feeds with their unread counts (ARCHITECTURE.md 5.4): the unread posts of their channels
/// after Telegram's own read position, counted as Telegram counts them (every part of an
/// album is one) and as the feed shows them, or the channels that have such posts. The
/// "Count unread posts" switch of Notifications and sounds decides which the badges show,
/// as the official app's "Count unread messages" does.
final class FeedsController extends ChangeNotifier {
  FeedsController({required this.db, required this.gateway}) {
    _feedsSub = db.watchFeeds().listen((f) {
      _feeds = f;
      if (!_loaded) {
        _loaded = true;
        notifyListeners();
      }
      _schedule();
    });
    _sourcesSub = db.watchSourceChanges().listen((_) => _schedule());
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
    _readSub = gateway.readUpdates.listen(_onRead);
    unawaited(refreshChannels());
  }

  final AppDatabase db;
  final TelegramGateway gateway;
  late final StreamSubscription<List<Feed>> _feedsSub;
  late final StreamSubscription<List<FeedSource>> _sourcesSub;
  late final StreamSubscription<PostEvent> _postsSub;
  late final StreamSubscription<ReadState> _readSub;
  late final StreamSubscription<String?> _modeSub;
  List<Feed> _feeds = const [];

  /// Telegram's read state of every channel counted, by chat id.
  final _states = <int, ReadState>{};
  bool _channelsLoaded = false;
  bool _countPosts = true;
  String? error;

  /// Counted posts per (feed, channel) of a feed that hides some; dropped with the source.
  final _unread = <(int, int), _Unread>{};
  Map<int, int> _posts = const {};
  Map<int, int> _channels = const {};

  /// A channel is counted up to this many unread posts; the badge says "999+" by then.
  static const cap = 1000;

  List<Feed> get feeds => _feeds;

  /// False until the database answered with the feeds the first time.
  bool get loaded => _loaded;
  bool _loaded = false;

  /// How many channels a feed has.
  int channelsIn(int feedId) => _sizes[feedId] ?? 0;
  Map<int, int> _sizes = const {};
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
        _states[c.chatId] = ReadState(
          chatId: c.chatId,
          lastReadMessageId: c.lastReadMessageId,
          unreadCount: c.unreadCount,
          lastMessageId: c.lastMessageId,
        );
      }
      _channelsLoaded = true;
      error = null;
    } on TelegramException catch (e) {
      error = e.message;
    }
    _schedule();
  }

  /// Telegram moved a read position or counted a new post: read here, in the official app
  /// or on another device.
  void _onRead(ReadState r) {
    final old = _states[r.chatId];
    _states[r.chatId] = ReadState(
      chatId: r.chatId,
      lastReadMessageId: r.lastReadMessageId,
      unreadCount: r.unreadCount,
      lastMessageId: math.max(old?.lastMessageId ?? 0, r.lastMessageId),
    );
    _schedule();
  }

  /// A new post is counted where it is seen, without asking for the history again; a
  /// deleted one stops counting.
  void _onPost(PostEvent e) {
    switch (e) {
      case PostAdded(:final post):
        final old = _states[post.chatId];
        if (old != null && post.messageId > old.lastMessageId) {
          _states[post.chatId] = ReadState(
            chatId: post.chatId,
            lastReadMessageId: old.lastReadMessageId,
            unreadCount: old.unreadCount,
            lastMessageId: post.messageId,
          );
        }
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

  /// Telegram's read state of a source the channel list did not name (one the account
  /// left); null when Telegram cannot tell.
  Future<ReadState?> _stateOf(int chatId) async {
    final known = _states[chatId];
    if (known != null) return known;
    try {
      return _states[chatId] = await gateway.readState(chatId);
    } on TelegramException {
      return null;
    }
  }

  /// A feed that shows everything counts what Telegram counts. One that hides some counts
  /// its posts after the read position from the history, in two steps: what is known at
  /// once (a channel with unread posts has news, as far as anyone can tell yet), then the
  /// posts, counted in parallel.
  Future<void> _count() async {
    final pairs = <_Pair>[];
    final seen = <(int, int)>{};
    final sizes = <int, int>{};
    for (final f in _feeds) {
      final filter = FeedFilter.decode(f.filterJson);
      final sources = await db.sourcesOf(f.id);
      sizes[f.id] = sources.length;
      for (final source in sources) {
        final chat = source.chatId;
        final state = await _stateOf(chat);
        if (state == null) continue;
        final key = (f.id, chat);
        seen.add(key);
        _Unread? u;
        if (!filter.isEmpty && state.unreadCount > 0) {
          u = _unread[key];
          if (u == null ||
              u.filterJson != f.filterJson ||
              state.lastReadMessageId < u.mark) {
            u = _unread[key] = _Unread(
              state.lastReadMessageId,
              f.filterJson,
              filter,
            );
          } else {
            u.readTo(state.lastReadMessageId);
          }
        } else {
          _unread.remove(key);
        }
        pairs.add(_Pair(f.id, state, filter.isEmpty, u));
      }
    }
    _unread.removeWhere((key, _) => !seen.contains(key));
    _sizes = sizes;
    _publish(pairs);
    final enough = _countPosts ? cap : 1;
    await Future.wait([
      for (final p in pairs)
        if (p.unread case final u?)
          u.fill(
            gateway,
            p.state.chatId,
            last: p.state.lastMessageId,
            enough: enough,
          ),
    ]);
    _publish(pairs);
  }

  void _publish(List<_Pair> pairs) {
    final posts = {for (final f in _feeds) f.id: 0};
    final channels = {for (final f in _feeds) f.id: 0};
    for (final p in pairs) {
      final u = p.unread;
      final int count;
      final bool news;
      if (p.showsAll || p.state.unreadCount == 0) {
        count = math.min(p.state.unreadCount, cap);
        news = count > 0;
      } else if (u != null && u.complete) {
        count = u.counted.length;
        news = count > 0;
      } else {
        // Not counted yet: shown at once, so the line under the feed's name does not
        // appear only when the count is done; the filter may still take it away.
        count = u?.counted.length ?? 0;
        news = true;
      }
      if (news) channels[p.feed] = (channels[p.feed] ?? 0) + 1;
      posts[p.feed] = (posts[p.feed] ?? 0) + count;
    }
    _posts = posts;
    _channels = channels;
    notifyListeners();
  }

  @override
  void dispose() {
    _feedsSub.cancel();
    _sourcesSub.cancel();
    _postsSub.cancel();
    _readSub.cancel();
    _modeSub.cancel();
    super.dispose();
  }
}

/// One channel of one feed in a count.
final class _Pair {
  const _Pair(this.feed, this.state, this.showsAll, this.unread);
  final int feed;
  final ReadState state;

  /// The feed shows every post: Telegram's own count is the count.
  final bool showsAll;

  /// The posts counted from the history; null where Telegram's count does.
  final _Unread? unread;
}

/// The unread posts of one channel that a feed hiding some of them shows: the posts after
/// the read position its filter lets through, every part of a shown album included when the
/// feed shows whole posts.
final class _Unread {
  _Unread(this.mark, this.filterJson, this.filter) : upTo = mark;

  int mark;
  final String? filterJson;
  final FeedFilter filter;

  /// Newest message id looked at: everything up to it is counted.
  int upTo;

  /// The history was asked: [upTo] is the newest post there was then.
  bool complete = false;

  /// The message ids counted.
  final counted = SplayTreeSet<int>();

  /// The reader got further: posts up to the new mark are read.
  void readTo(int newMark) {
    if (newMark <= mark) return;
    mark = newMark;
    counted.removeWhere((id) => id <= newMark);
    if (newMark > upTo) upTo = newMark;
  }

  /// A post that came in now. A part of an album decides nothing alone, so the channel is
  /// counted again from the history.
  void arrived(Post p) {
    if (!complete || p.messageId <= upTo) return;
    if (p.albumId != 0) {
      complete = false;
      return;
    }
    upTo = p.messageId;
    if (filter.allows(p)) counted.add(p.messageId);
  }

  void deleted(List<int> ids) => counted.removeAll(ids);

  /// Asks the history for what is newer than the mark, newest first, down to it or until
  /// [enough] posts are found. Newest first because TDLib pages newer posts only from a
  /// message that exists: from a mark of 0 (a channel never read) it would answer with
  /// nothing. At the cap the counted posts are the newest ones, so the count stays right as
  /// the mark climbs into them.
  Future<void> fill(
    TelegramGateway gateway,
    int chatId, {
    required int last,
    required int enough,
  }) async {
    if (complete && last <= upTo) return;
    if (!complete) {
      counted.clear();
      upTo = mark;
    }
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
      if (counted.length + shown >= enough) break;
      from = got.last.messageId;
      page = 100;
    }
    _add(newer);
    while (counted.length > enough) {
      counted.remove(counted.first);
    }
    // The newest post Telegram named may be one history does not list (a service
    // message); counted up to it, so the next count does not ask again.
    upTo = math.max(
      upTo,
      math.max(last, newer.fold(0, (m, p) => math.max(m, p.messageId))),
    );
    complete = true;
  }

  /// Singles count when the filter lets them through; an album counts when one part does,
  /// with all its parts when the feed shows whole posts.
  void _add(List<Post> posts) {
    final albums = <int, List<Post>>{};
    for (final p in posts) {
      if (p.albumId == 0) {
        if (filter.allows(p)) counted.add(p.messageId);
      } else {
        (albums[p.albumId] ??= []).add(p);
      }
    }
    for (final parts in albums.values) {
      final shown = parts.where(filter.allows).toList();
      if (shown.isEmpty) continue;
      counted.addAll([
        for (final p in filter.wholePost ? parts : shown) p.messageId,
      ]);
    }
  }
}
