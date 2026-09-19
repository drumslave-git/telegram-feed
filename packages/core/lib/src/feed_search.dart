import 'dart:collection';

import 'package:telegram_gateway/telegram_gateway.dart';

import 'feed_filter.dart';

/// A merged, paginated search over the channels of a feed; one channel is the same thing
/// with a single source (ARCHITECTURE.md section 5.10).
///
/// Order is the timeline's, `(date desc, chatId, messageId desc)`. Albums are not collapsed:
/// a result row and a media tile point at one post, the way the official app lists them.
/// The feed's own [FeedFilter] applies, so a feed searches exactly what it shows.
final class FeedSearch {
  FeedSearch(
    this.gateway,
    List<int> chatIds, {
    this.query = '',
    this.filter = HistoryFilter.any,
    this.feedFilter = FeedFilter.none,
    this.pageSize = 30,
    this.sourceLimit = 30,
  }) : _sources = [for (final id in chatIds) _Source(id)];

  final TelegramGateway gateway;

  /// Words to look for; empty with a [filter] is how the shared media tabs list a channel.
  final String query;
  final HistoryFilter filter;

  /// The feed's content filter; posts it hides are not results either.
  final FeedFilter feedFilter;

  /// True for the shared media tabs: they list single media items by kind, so the feed's
  /// filter applies post by post there. A search for words instead finds everything the
  /// timeline shows, an album part carried by its siblings included
  /// ([FeedFilter.mayShow]).
  bool get listsMedia => query.isEmpty;

  /// Results added per [loadMore].
  final int pageSize;

  /// Posts fetched from one source per request.
  final int sourceLimit;

  final List<_Source> _sources;
  final List<Post> _results = [];
  final _seen = <(int, int)>{};

  List<Post> get results => List.unmodifiable(_results);
  bool get exhausted => _sources.every((s) => s.exhausted && s.buffer.isEmpty);

  /// Telegram's approximate number of matches over all sources. It counts what the server
  /// matched, so a feed filter can only make the real number smaller; once [exhausted],
  /// `results.length` is exact.
  int get totalCount {
    var sum = 0;
    for (final s in _sources) {
      if (s.total > 0) sum += s.total;
    }
    return sum;
  }

  Future<void> _fill(_Source s) async {
    if (s.exhausted || s.buffer.isNotEmpty) return;
    final page = await gateway.searchHistory(
      s.chatId,
      query: query,
      filter: filter,
      fromMessageId: s.from,
      limit: sourceLimit,
    );
    if (page.totalCount > 0 && s.total == 0) s.total = page.totalCount;
    s.buffer.addAll(page.posts);
    if (page.isLast || page.posts.isEmpty) {
      s.exhausted = true;
    } else {
      s.from = page.nextFromMessageId;
    }
  }

  static int _compare(Post a, Post b) {
    if (a.date != b.date) return b.date.compareTo(a.date);
    if (a.chatId != b.chatId) return b.chatId.compareTo(a.chatId);
    return b.messageId.compareTo(a.messageId);
  }

  /// Appends up to [pageSize] older results. Returns what was added.
  Future<List<Post>> loadMore() async {
    final added = <Post>[];
    while (added.length < pageSize) {
      await Future.wait(_sources.map(_fill));
      _Source? best;
      for (final s in _sources) {
        if (s.buffer.isEmpty) continue;
        if (best == null || _compare(s.buffer.first, best.buffer.first) < 0) {
          best = s;
        }
      }
      if (best == null) break;
      final post = best.buffer.removeFirst();
      if (!_seen.add((post.chatId, post.messageId))) continue;
      if (!(listsMedia ? feedFilter.allows(post) : feedFilter.mayShow(post))) {
        continue;
      }
      _results.add(post);
      added.add(post);
    }
    return added;
  }

  /// Drops a deleted post from the results. True when something was removed.
  bool removePosts(int chatId, List<int> messageIds) {
    final ids = messageIds.toSet();
    final before = _results.length;
    _results.removeWhere(
      (p) => p.chatId == chatId && ids.contains(p.messageId),
    );
    return _results.length != before;
  }
}

class _Source {
  _Source(this.chatId);
  final int chatId;

  /// Where the next request starts; 0 = newest.
  int from = 0;
  int total = 0;
  bool exhausted = false;
  final buffer = Queue<Post>();
}

/// Where a timeline of [chatIds] has to start to open at [unixDate]: per channel the newest
/// post sent no later than it. A channel with nothing that old is left out — everything it
/// has is newer, so it has nothing to show at that point.
Future<Map<int, int>> anchorsForDate(
  TelegramGateway gateway,
  Iterable<int> chatIds,
  int unixDate,
) async {
  final out = <int, int>{};
  await Future.wait([
    for (final id in chatIds)
      gateway.messageIdByDate(id, unixDate).then((m) {
        if (m != 0) out[id] = m;
      }),
  ]);
  return out;
}
