import 'dart:collection';

import 'package:telegram_gateway/telegram_gateway.dart';

import 'feed_filter.dart';

/// One row of the timeline: a post, or an album collapsed into its first post plus parts.
final class TimelineItem {
  TimelineItem(this.head, [List<Post>? parts]) : parts = parts ?? [];

  /// The newest post of the item (albums: the part with the highest message id).
  Post head;

  /// Other album parts, newest first. Empty for single posts.
  final List<Post> parts;

  /// The feed's filter leaves this post out and the feed shows such posts minimized
  /// ([FeedFilter.minimize]): the row stands for a hidden post, with all of its parts.
  bool minimized = false;

  int get chatId => head.chatId;
  int get albumId => head.albumId;
  bool get isAlbum => albumId != 0;

  /// Stable identity within the chat: the head of an album changes while its parts arrive.
  int get rowId => isAlbum ? albumId : head.messageId;

  /// The post whose text the row shows: the head, or the first album part with a caption.
  Post get textPost {
    if (head.text.isNotEmpty) return head;
    for (final p in parts) {
      if (p.text.isNotEmpty) return p;
    }
    return head;
  }

  /// Plain text of the item: the head's text, or the first non-empty caption of an album.
  String get text => textPost.text;

  List<Post> get allPosts => [head, ...parts];

  /// The post that carries the row's reactions. Telegram keeps the reactions of an album
  /// on its first message, which is where the official app reads and sends them
  /// (`findPrimaryMessageObject`); should another part hold them, that one is taken.
  Post get reactionPost {
    if (parts.isEmpty) return head;
    final oldestFirst = allPosts.reversed;
    for (final p in oldestFirst) {
      if (p.reactions.isNotEmpty) return p;
    }
    return oldestFirst.first;
  }

  /// The post whose comments are the row's: the first message of an album, or whichever
  /// part Telegram hung the discussion on.
  Post get threadPost {
    if (parts.isEmpty) return head;
    final oldestFirst = allPosts.reversed;
    for (final p in oldestFirst) {
      if (p.canComment) return p;
    }
    return oldestFirst.first;
  }

  /// The channel protects its content: the row may not be copied, shared or saved.
  bool get isProtected => !head.canBeSaved || parts.any((p) => !p.canBeSaved);
}

class _Source {
  _Source(this.chatId);
  final int chatId;
  int fromMessageId = 0; // 0 = newest
  final buffer = Queue<Post>();
  bool exhausted = false;

  /// Newest post loaded from this source; where paging towards the newest end continues.
  /// Only used by an anchored timeline; 0 means it is already at the newest end.
  int newerFrom = 0;
  bool noNewer = true;
}

/// Merged, paginated, live timeline over several channels (ARCHITECTURE.md section 5.3).
///
/// Order: `(date desc, chatId, messageId desc)`. Nothing is persisted; TDLib's database makes
/// re-fetching cheap. Live events are applied through [apply]; new posts go to the head when
/// [atTop] is true and otherwise accumulate in [pendingNew] until [releasePending].
final class FeedTimeline {
  FeedTimeline(
    this.gateway,
    List<int> chatIds, {
    this.pageSize = 30,
    this.historyLimit = 30,
    this.filter = FeedFilter.none,
    Map<int, int>? startAt,
  }) : _sources = [for (final id in chatIds) _Source(id)],
       anchored = startAt != null {
    if (startAt == null) return;
    // Opened at an older post (a search result, a date): every source starts at its own
    // anchor, which is the newest post it may show, and can page both ways from there.
    // A source without an anchor has nothing that old; it stays out until the timeline is
    // back at the newest end, where it is opened without anchors again.
    atTop = false;
    for (final s in _sources) {
      final anchor = startAt[s.chatId];
      if (anchor == null) {
        s.exhausted = true;
        continue;
      }
      // getChatHistory answers with posts older than the bound, so the anchor itself needs
      // one more: TDLib message ids are server ids shifted left by 20 bits, nothing sits
      // between id and id + 1.
      s.fromMessageId = anchor + 1;
      s.newerFrom = anchor;
      s.noNewer = false;
    }
  }

  /// True when the timeline was opened at an older post instead of at the newest one. New
  /// posts then wait in [pendingNew] and [loadNewer] pages towards the newest end.
  final bool anchored;

  /// What the feed shows. Hidden posts never become rows; [passedAt] reads them with the
  /// rows around them. With [FeedFilter.minimize] a hidden post is a minimized row instead.
  final FeedFilter filter;

  /// The posts no row shows, per chat: message id to date.
  final _hidden = <int, SplayTreeMap<int, int>>{};

  /// Every part of every album taken so far, shown or not, per (chat, album), newest
  /// first. The filter decides an album as a whole ([FeedFilter.shownParts]), so each part
  /// that arrives, changes or goes decides it again with its siblings.
  final _albums = <(int, int), List<Post>>{};

  /// The listed rows by [_rowKey].
  final _rows = <(int, int, bool), TimelineItem>{};

  final TelegramGateway gateway;
  final int pageSize;
  final int historyLimit;
  final List<_Source> _sources;
  final List<TimelineItem> _items = [];

  /// Posts that arrived while the reader was further up, not yet taken into the list.
  final List<Post> _pending = [];
  int _pendingShown = 0;

  /// Set by the screen: true while the user is at the top of the list.
  bool atTop = true;

  List<TimelineItem> get items => List.unmodifiable(_items);

  /// The posts waiting behind the button that the feed shows, every part of an album one;
  /// minimized ones are not counted.
  int get pendingNew => _pendingShown;

  /// True while any post waits behind the button, minimized or hidden ones included.
  bool get hasPending => _pending.isNotEmpty;
  Set<int> get chatIds => {for (final s in _sources) s.chatId};
  bool get exhausted => _sources.every((s) => s.exhausted && s.buffer.isEmpty);

  /// Ids seen in the list; guards against duplicates from live events and history overlap.
  final _seen = <(int, int)>{};

  Future<void> _fill(_Source s) async {
    if (s.exhausted || s.buffer.isNotEmpty) return;
    // Local first (fast, P0-3), then network if the local database has nothing more.
    var posts = await gateway.history(
      s.chatId,
      fromMessageId: s.fromMessageId,
      limit: historyLimit,
      onlyLocal: true,
    );
    if (posts.isEmpty) {
      posts = await gateway.history(
        s.chatId,
        fromMessageId: s.fromMessageId,
        limit: historyLimit,
      );
    }
    if (posts.isEmpty) {
      s.exhausted = true;
      return;
    }
    s.buffer.addAll(posts);
    s.fromMessageId = posts.last.messageId;
  }

  static int _compare(Post a, Post b) {
    if (a.date != b.date) return b.date.compareTo(a.date);
    if (a.chatId != b.chatId) return b.chatId.compareTo(a.chatId);
    return b.messageId.compareTo(a.messageId);
  }

  /// The row of [post]: its album's, or its own. An album id and a message id are
  /// different numbers even where they are equal.
  static (int, int, bool) _rowKey(Post post) => post.albumId != 0
      ? (post.chatId, post.albumId, true)
      : (post.chatId, post.messageId, false);

  /// Takes [post] into the list, alone or into its album, and decides its row again. True
  /// when the list changed.
  bool _take(Post post) {
    if (post.albumId == 0) return _settle([post]);
    final parts = _albums[(post.chatId, post.albumId)] ??= [];
    var i = 0;
    while (i < parts.length && parts[i].messageId > post.messageId) {
      i++;
    }
    parts.insert(i, post);
    return _settle(parts);
  }

  /// Puts the row of [posts] (one post, or the known parts of an album, newest first) in
  /// line with what the filter makes of them: listed whole or in part, minimized, or not
  /// at all. True when the list changed.
  bool _settle(List<Post> posts) {
    final chatId = posts.first.chatId;
    final shown = filter.shownParts(posts);
    // A service line the filter leaves out goes; it is never a minimized row.
    final minimized =
        shown.isEmpty &&
        filter.minimize &&
        posts.any((p) => p.media is! ServiceNote);
    final listed = {for (final p in minimized ? posts : shown) p.messageId};
    for (final p in posts) {
      if (listed.contains(p.messageId)) {
        _hidden[chatId]?.remove(p.messageId);
      } else {
        (_hidden[chatId] ??= SplayTreeMap())[p.messageId] = p.date;
      }
    }
    final key = _rowKey(posts.first);
    final row = _rows[key];
    if (listed.isEmpty) {
      if (row == null) return false;
      _rows.remove(key);
      _items.remove(row);
      return true;
    }
    final ordered = [
      for (final p in posts)
        if (listed.contains(p.messageId)) p,
    ];
    if (row == null) {
      final item = TimelineItem(ordered.first, ordered.sublist(1))
        ..minimized = minimized;
      _rows[key] = item;
      _insertRow(item);
      return true;
    }
    if (row.minimized == minimized && _holds(row, ordered)) return false;
    row
      ..head = ordered.first
      ..minimized = minimized
      ..parts.clear()
      ..parts.addAll(ordered.skip(1));
    return true;
  }

  /// Whether [row] shows exactly [posts], newest first.
  static bool _holds(TimelineItem row, List<Post> posts) {
    if (!identical(row.head, posts.first) ||
        row.parts.length != posts.length - 1) {
      return false;
    }
    for (var i = 1; i < posts.length; i++) {
      if (!identical(row.parts[i - 1], posts[i])) return false;
    }
    return true;
  }

  /// Lists a new row where the order puts it: at the end while paging back, among the
  /// others for a post that arrived or a page of newer ones.
  void _insertRow(TimelineItem item) {
    if (_items.isEmpty || _compare(_items.last.head, item.head) < 0) {
      _items.add(item);
      return;
    }
    var i = 0;
    while (i < _items.length && _compare(_items[i].head, item.head) < 0) {
      i++;
    }
    _items.insert(i, item);
  }

  /// Hides [post] until its row is decided: a single post the reader will not see.
  void _hide(Post post) =>
      (_hidden[post.chatId] ??= SplayTreeMap())[post.messageId] = post.date;

  /// Appends up to [pageSize] items (older posts). Returns the items added.
  Future<List<TimelineItem>> loadMore() async {
    final added = <TimelineItem>[];
    void take(Post post) {
      if (!_seen.add((post.chatId, post.messageId))) return;
      final key = _rowKey(post);
      final had = _rows[key];
      _take(post);
      final row = _rows[key];
      if (had == null && row != null) added.add(row);
    }

    Post? last;
    _Source? lastSource;
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
      last = best.buffer.removeFirst();
      lastSource = best;
      take(last);
    }
    // An album is decided as a whole: its older parts come in before the page ends, so a
    // caption further down cannot take the row away or bring it afterwards.
    while (last != null && last.albumId != 0 && lastSource != null) {
      await _fill(lastSource);
      if (lastSource.buffer.isEmpty ||
          lastSource.buffer.first.albumId != last.albumId) {
        break;
      }
      last = lastSource.buffer.removeFirst();
      take(last);
    }
    // A row the rest of its album took away again is not an addition.
    return [
      for (final row in added)
        if (identical(_rows[_rowKey(row.head)], row)) row,
    ];
  }

  /// True when every source has reached the newest post it knows: an anchored timeline is
  /// then as complete as an unanchored one.
  bool get exhaustedNewer => _sources.every((s) => s.noNewer);

  /// Adds posts newer than the ones loaded, at the newest end of the list (only meaningful
  /// for an [anchored] timeline). Returns how many rows appeared before the ones already
  /// there, so the screen can keep the reader in place.
  Future<int> loadNewer() async {
    final fetched = <Post>[];
    await Future.wait([
      for (final s in _sources)
        if (!s.noNewer)
          gateway
              .historyAfter(
                s.chatId,
                afterMessageId: s.newerFrom,
                limit: historyLimit,
              )
              .then((posts) {
                if (posts.isEmpty) {
                  s.noNewer = true;
                  return;
                }
                s.newerFrom = posts.first.messageId; // newest first
                fetched.addAll(posts);
              }),
    ]);
    final before = _items.length;
    // Oldest first: each one is inserted where the order puts it, so the album parts of a
    // row meet each other whichever end they came from.
    for (final post in fetched..sort((a, b) => _compare(b, a))) {
      if (!_seen.add((post.chatId, post.messageId))) continue;
      _take(post);
    }
    return _items.length - before;
  }

  /// Applies a live event. Returns true when the visible list changed.
  bool apply(PostEvent e) {
    switch (e) {
      case PostAdded(:final post):
        if (!chatIds.contains(post.chatId)) return false;
        if (!_seen.add((post.chatId, post.messageId))) return false;
        if (atTop) return _take(post);
        // A single post the reader will not see is hidden at once, so it is read with the
        // posts around it; everything else waits behind the button, an album part with
        // its siblings.
        if (post.albumId == 0 &&
            !filter.minimize &&
            filter.shownParts([post]).isEmpty) {
          _hide(post);
          return false;
        }
        _pending.add(post);
        _countPending();
        return false;
      case PostEdited(:final post):
        final waiting = _pending.indexWhere(
          (p) => p.chatId == post.chatId && p.messageId == post.messageId,
        );
        if (waiting >= 0) {
          _pending[waiting] = post;
          _countPending();
          return false;
        }
        if (!_seen.contains((post.chatId, post.messageId))) return false;
        // The words may have changed what the filter makes of the post.
        if (post.albumId == 0) return _settle([post]);
        final parts = _albums[(post.chatId, post.albumId)];
        final i = parts?.indexWhere((p) => p.messageId == post.messageId) ?? -1;
        if (parts == null || i < 0) return false;
        parts[i] = post;
        return _settle(parts);
      case PostsDeleted(:final chatId, :final messageIds):
        var changed = false;
        final ids = messageIds.toSet();
        for (var i = _items.length - 1; i >= 0; i--) {
          final item = _items[i];
          if (item.chatId != chatId ||
              item.isAlbum ||
              !ids.contains(item.head.messageId)) {
            continue;
          }
          _items.removeAt(i);
          _rows.remove(_rowKey(item.head));
          changed = true;
        }
        for (final key in [
          for (final k in _albums.keys)
            if (k.$1 == chatId) k,
        ]) {
          final parts = _albums[key]!;
          final before = parts.length;
          parts.removeWhere((p) => ids.contains(p.messageId));
          if (parts.length == before) continue;
          if (parts.isNotEmpty) {
            if (_settle(parts)) changed = true;
            continue;
          }
          _albums.remove(key);
          final row = _rows.remove((chatId, key.$2, true));
          if (row != null) {
            _items.remove(row);
            changed = true;
          }
        }
        _pending.removeWhere(
          (p) => p.chatId == chatId && ids.contains(p.messageId),
        );
        _countPending();
        return changed;
    }
  }

  /// Counts what the button shows of the posts waiting: an album by all of its parts known
  /// so far, listed ones included.
  void _countPending() {
    var n = 0;
    final albums = <(int, int), List<Post>>{};
    for (final p in _pending) {
      if (p.albumId == 0) {
        if (filter.shownParts([p]).isNotEmpty) n++;
      } else {
        (albums[(p.chatId, p.albumId)] ??= []).add(p);
      }
    }
    albums.forEach((key, waiting) {
      final shown = filter.shownParts([...?_albums[key], ...waiting]);
      n += shown.where(waiting.contains).length;
    });
    _pendingShown = n;
  }

  /// Whether [item] is newer than the read mark of its chat (0 = never read). A minimized
  /// row stands for a hidden post and is never unread.
  static bool isUnread(TimelineItem item, Map<int, int> marks) =>
      !item.minimized && item.head.messageId > (marks[item.chatId] ?? 0);

  /// The unread posts of the loaded rows, counted as Telegram counts them: every part of
  /// an album is one. With [pendingNew], what the button to the newest posts shows.
  /// Minimized rows count for nothing.
  int unreadPosts(Map<int, int> marks) {
    var n = 0;
    // A channel's rows are newest first, so its first read row ends its unread ones.
    final open = chatIds;
    for (final item in _items) {
      if (open.isEmpty) break;
      if (item.minimized || !open.contains(item.chatId)) continue;
      final mark = marks[item.chatId] ?? 0;
      if (item.head.messageId <= mark) {
        open.remove(item.chatId);
        continue;
      }
      for (final p in item.allPosts) {
        if (p.messageId > mark) n++;
      }
    }
    return n;
  }

  /// What a reader who has read the row at [index] has passed, per chat: the newest post of
  /// each chat at that row or older in the timeline's order, shown or hidden. The feed
  /// reads like one chat (ARCHITECTURE.md 5.4): everything above the newest post read is
  /// read. With [throughNewest] (the row is the newest one and nothing waits behind the
  /// button) the hidden posts after it are passed too. A chat with nothing loaded that old
  /// and nothing waiting in its buffer is left out.
  Map<int, int> passedAt(int index, {bool throughNewest = false}) {
    if (index < 0 || index >= _items.length) return const {};
    final row = _items[index].head;
    final out = <int, int>{};
    void take(int chat, int id) {
      if (id > (out[chat] ?? 0)) out[chat] = id;
    }

    final missing = chatIds;
    for (var i = index; i < _items.length && missing.isNotEmpty; i++) {
      final item = _items[i];
      if (missing.remove(item.chatId)) take(item.chatId, item.head.messageId);
    }
    // Buffered posts are older than every row, so older than this one too.
    for (final s in _sources) {
      if (missing.contains(s.chatId) && s.buffer.isNotEmpty) {
        take(s.chatId, s.buffer.first.messageId);
      }
    }
    _hidden.forEach((chat, hidden) {
      for (
        var id = hidden.lastKey();
        id != null;
        id = hidden.lastKeyBefore(id)
      ) {
        if (throughNewest || _notNewer(hidden[id]!, chat, id, row)) {
          take(chat, id);
          break;
        }
      }
    });
    return out;
  }

  /// Whether the post (date, chat, id) stands at [row] or below it in the timeline's order.
  static bool _notNewer(int date, int chatId, int messageId, Post row) {
    if (date != row.date) return date < row.date;
    if (chatId != row.chatId) return chatId < row.chatId;
    return messageId <= row.messageId;
  }

  /// Index of the oldest loaded unread item, or -1 when nothing loaded is unread.
  int firstUnreadIndex(Map<int, int> marks) {
    for (var i = _items.length - 1; i >= 0; i--) {
      if (isUnread(_items[i], marks)) return i;
    }
    return -1;
  }

  /// True when every source has either been loaded down to its read mark or is exhausted,
  /// i.e. loading more cannot reveal additional unread posts.
  bool reachedMarks(Map<int, int> marks) {
    for (final s in _sources) {
      if (s.exhausted && s.buffer.isEmpty) continue;
      final mark = marks[s.chatId] ?? 0;
      if (s.buffer.isNotEmpty) {
        if (s.buffer.first.messageId > mark) return false;
        continue;
      }
      // Nothing buffered: the last emitted post decides.
      if (s.fromMessageId == 0 || s.fromMessageId > mark) return false;
    }
    return true;
  }

  /// Moves pending new posts to the head (user tapped "N new posts"). Returns how many
  /// rows that added.
  int releasePending() {
    final posts = [..._pending]..sort(_compare);
    _pending.clear();
    _pendingShown = 0;
    final before = _items.length;
    for (final p in posts.reversed) {
      _take(p);
    }
    return _items.length - before;
  }
}
