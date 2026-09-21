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
  /// rows around them.
  final FeedFilter filter;

  /// The posts the filter hid, per chat: message id to date.
  final _hidden = <int, SplayTreeMap<int, int>>{};

  /// True when the post may be listed; a hidden one is remembered.
  bool _sort(Post post) {
    final ok = filter.allows(post);
    if (!ok) {
      (_hidden[post.chatId] ??= SplayTreeMap())[post.messageId] = post.date;
    }
    return ok;
  }

  /// A part the filter hid that its album's row shows after all.
  void _promote(Post post) => _hidden[post.chatId]?.remove(post.messageId);

  /// True when the filter hid [post] but its album's row may still carry it
  /// ([FeedFilter.wholePost]).
  bool _ridesAlong(Post post) => post.albumId != 0 && filter.mayShow(post);

  /// Hidden parts whose album has no row yet, per (chat, album): the sibling that opens
  /// the row takes them along. An album that never gets one loses them again, and the map
  /// is capped so a long run of such albums cannot grow it.
  final _held = <(int, int), List<Post>>{};

  void _hold(Post post) {
    final key = (post.chatId, post.albumId);
    if (_held.length >= 8 && !_held.containsKey(key)) {
      _held.remove(_held.keys.first);
    }
    (_held[key] ??= []).add(post);
  }

  /// A row for [post] together with the parts held for its album; the newest of them is
  /// the head, the rest follow newest first.
  TimelineItem _newRow(Post post) {
    if (post.albumId == 0) return TimelineItem(post);
    final held = _held.remove((post.chatId, post.albumId));
    if (held == null) return TimelineItem(post);
    for (final p in held) {
      _promote(p);
    }
    final parts = [post, ...held]
      ..sort((a, b) => b.messageId.compareTo(a.messageId));
    return TimelineItem(parts.first, parts.sublist(1));
  }

  /// Puts [post] into its album's row if that row is listed; parts stay newest first.
  bool _merge(Post post) {
    if (post.albumId == 0) return false;
    for (final item in _items) {
      if (item.chatId != post.chatId || item.albumId != post.albumId) continue;
      if (post.messageId > item.head.messageId) {
        item.parts.insert(0, item.head);
        item.head = post;
        return true;
      }
      var i = 0;
      while (i < item.parts.length &&
          item.parts[i].messageId > post.messageId) {
        i++;
      }
      item.parts.insert(i, post);
      return true;
    }
    return false;
  }

  /// A hidden part of a whole-post feed: into its row when there is one, held for the
  /// sibling that will open it otherwise. True when the list changed.
  bool _rideAlong(Post post) {
    if (!_merge(post)) {
      _hold(post);
      return false;
    }
    _promote(post);
    return true;
  }

  final TelegramGateway gateway;
  final int pageSize;
  final int historyLimit;
  final List<_Source> _sources;
  final List<TimelineItem> _items = [];
  final List<Post> _pending = [];

  /// Set by the screen: true while the user is at the top of the list.
  bool atTop = true;

  List<TimelineItem> get items => List.unmodifiable(_items);
  int get pendingNew => _pending.length;
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

  /// Appends up to [pageSize] items (older posts). Returns the items added.
  Future<List<TimelineItem>> loadMore() async {
    final added = <TimelineItem>[];
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
      final passes = _sort(post);
      if (!passes && !_ridesAlong(post)) continue;
      final last = _items.isEmpty ? null : _items.last;
      if (post.albumId != 0 &&
          last != null &&
          last.chatId == post.chatId &&
          last.albumId == post.albumId) {
        if (!passes) _promote(post);
        last.parts.add(post); // older part of the album already listed
        continue;
      }
      if (!passes) {
        _hold(
          post,
        ); // the next part of this album opens the row, or nothing does
        continue;
      }
      final item = _newRow(post);
      _items.add(item);
      added.add(item);
    }
    return added;
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
    var added = 0;
    // Oldest first: each one is inserted where the order puts it, so the album parts of a
    // row meet each other whichever end they came from.
    for (final post in fetched..sort((a, b) => _compare(b, a))) {
      if (!_seen.add((post.chatId, post.messageId))) continue;
      if (!_sort(post)) {
        if (_ridesAlong(post)) _rideAlong(post);
        continue;
      }
      final before = _items.length;
      _insertNew(post);
      if (_items.length > before) added++;
    }
    return added;
  }

  /// Applies a live event. Returns true when the visible list changed.
  bool apply(PostEvent e) {
    switch (e) {
      case PostAdded(:final post):
        if (!chatIds.contains(post.chatId)) return false;
        if (!_seen.add((post.chatId, post.messageId))) return false;
        if (!_sort(post)) {
          if (!_ridesAlong(post)) return false;
          // Its row is listed, or it waits for the sibling that opens one — which may
          // itself still be in [_pending].
          if (!atTop) {
            _hold(post);
            return false;
          }
          return _rideAlong(post);
        }
        if (atTop) {
          _insertNew(post);
          return true;
        }
        _pending.add(post);
        return false;
      case PostEdited(:final post):
        for (final item in _items) {
          if (item.head.chatId == post.chatId &&
              item.head.messageId == post.messageId) {
            item.head = post;
            return true;
          }
          final i = item.parts.indexWhere(
            (p) => p.messageId == post.messageId && p.chatId == post.chatId,
          );
          if (i >= 0) {
            item.parts[i] = post;
            return true;
          }
        }
        return false;
      case PostsDeleted(:final chatId, :final messageIds):
        var changed = false;
        final ids = messageIds.toSet();
        for (var i = _items.length - 1; i >= 0; i--) {
          final item = _items[i];
          if (item.chatId != chatId) continue;
          item.parts.removeWhere((p) => ids.contains(p.messageId));
          if (ids.contains(item.head.messageId)) {
            if (item.parts.isEmpty) {
              _items.removeAt(i);
            } else {
              item.head = item.parts.removeAt(0);
            }
            changed = true;
          }
        }
        _pending.removeWhere(
          (p) => p.chatId == chatId && ids.contains(p.messageId),
        );
        for (final held in _held.values) {
          held.removeWhere(
            (p) => p.chatId == chatId && ids.contains(p.messageId),
          );
        }
        _held.removeWhere((_, held) => held.isEmpty);
        return changed;
    }
  }

  /// Whether [item] is newer than the read mark of its chat (0 = never read).
  static bool isUnread(TimelineItem item, Map<int, int> marks) =>
      item.head.messageId > (marks[item.chatId] ?? 0);

  /// The unread posts of the loaded rows, counted as Telegram counts them: every part of
  /// an album is one. With [pendingNew], what the button to the newest posts shows.
  int unreadPosts(Map<int, int> marks) {
    var n = 0;
    // A channel's rows are newest first, so its first read row ends its unread ones.
    final open = chatIds;
    for (final item in _items) {
      if (open.isEmpty) break;
      if (!open.contains(item.chatId)) continue;
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

  /// Moves pending new posts to the head (user tapped "N new posts").
  void releasePending() {
    final posts = [..._pending]..sort(_compare);
    _pending.clear();
    for (final p in posts.reversed) {
      _insertNew(p);
    }
  }

  void _insertNew(Post post) {
    // Album parts arrive one by one; each one joins the row the first of them opened.
    if (_merge(post)) return;
    var i = 0;
    while (i < _items.length && _compare(_items[i].head, post) < 0) {
      i++;
    }
    _items.insert(i, _newRow(post));
  }
}
