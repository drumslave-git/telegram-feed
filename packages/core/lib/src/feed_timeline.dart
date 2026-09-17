import 'dart:collection';

import 'package:telegram_gateway/telegram_gateway.dart';

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

  /// Plain text of the item: the head's text, or the first non-empty caption of an album.
  String get text {
    if (head.text.isNotEmpty) return head.text;
    for (final p in parts) {
      if (p.text.isNotEmpty) return p.text;
    }
    return '';
  }

  List<Post> get allPosts => [head, ...parts];
}

class _Source {
  _Source(this.chatId);
  final int chatId;
  int fromMessageId = 0; // 0 = newest
  final buffer = Queue<Post>();
  bool exhausted = false;
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
  }) : _sources = [for (final id in chatIds) _Source(id)];

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
      final last = _items.isEmpty ? null : _items.last;
      if (post.albumId != 0 &&
          last != null &&
          last.chatId == post.chatId &&
          last.albumId == post.albumId) {
        last.parts.add(post); // older part of the album already listed
        continue;
      }
      final item = TimelineItem(post);
      _items.add(item);
      added.add(item);
    }
    return added;
  }

  /// Applies a live event. Returns true when the visible list changed.
  bool apply(PostEvent e) {
    switch (e) {
      case PostAdded(:final post):
        if (!chatIds.contains(post.chatId)) return false;
        if (!_seen.add((post.chatId, post.messageId))) return false;
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
        return changed;
    }
  }

  /// Whether [item] is newer than the read mark of its chat (0 = never read).
  static bool isUnread(TimelineItem item, Map<int, int> marks) =>
      item.head.messageId > (marks[item.chatId] ?? 0);

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
    // Live posts are almost always the newest; album parts arrive one by one.
    if (post.albumId != 0) {
      for (final item in _items.take(5)) {
        if (item.chatId == post.chatId && item.albumId == post.albumId) {
          if (post.messageId > item.head.messageId) {
            item.parts.insert(0, item.head);
            item.head = post;
          } else {
            item.parts.add(post);
          }
          return;
        }
      }
    }
    var i = 0;
    while (i < _items.length && _compare(_items[i].head, post) < 0) {
      i++;
    }
    _items.insert(i, TimelineItem(post));
  }
}
