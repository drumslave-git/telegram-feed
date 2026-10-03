import 'dart:async';
import 'dart:math' as math;

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../l10n/l10n.dart';
import '../media/media_viewer.dart';
import '../widgets/error_state.dart';
import 'bubble_text.dart';
import 'formatted_text.dart';
import 'media_view.dart';
import 'open_links.dart';
import 'post_card.dart';
import 'sticker_view.dart';
import 'text_scale.dart';

/// Comments on a post from the channel's discussion group, with a reply composer.
class ThreadScreen extends StatefulWidget {
  const ThreadScreen({
    super.key,
    required this.gateway,
    required this.post,
    required this.channelTitle,
    this.channelPhoto,
    this.item,
    this.onOpenTelegramLink,
  });
  final TelegramGateway gateway;
  final Post post;
  final String channelTitle;
  final FileRef? channelPhoto;

  /// Opens a link into Telegram (a mention, a link to a post) inside the app when it
  /// leads to a channel the account follows; true when it did.
  final bool Function(Uri uri)? onOpenTelegramLink;

  /// The timeline row of [post]; with it the header shows the whole album.
  final TimelineItem? item;

  @override
  State<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<ThreadScreen> {
  final _composer = TextEditingController();

  /// The list is turned over, like the timeline's: index 0 is the newest comment at the
  /// bottom, and the post the comments belong to is the last row, at the top.
  final _scroll = ItemScrollController();
  final _positions = ItemPositionsListener.create();
  int _initialIndex = 0;
  double _initialAlignment = 0;
  bool _settled = false;

  /// The comment under the "Unread comments" divider: the first one that came after the
  /// thread was last read.
  int? _firstUnread;

  /// How many comments an opening loads at most on its way to the first unread one.
  static const _openCap = 300;

  /// The newest comment that has been on the screen, and the timer that tells Telegram.
  int _seenUpTo = 0;
  int _reportedUpTo = 0;
  Timer? _readDebounce;

  /// Comments that arrived while the thread is open, on top of what Telegram counted.
  int _arrived = 0;

  /// The first pages are on their way; the list is built once it is known where it opens.
  bool _opening = true;
  Thread? _thread;
  bool _loading = true;
  bool _noThread = false;
  bool _sending = false;
  bool _exhausted = false;
  String? _error;
  final _comments = <Comment>[]; // oldest first
  StreamSubscription<Comment>? _live;

  /// Search inside the thread (H-27): open, the words, what was found (newest first).
  bool _searchOpen = false;
  final _queryCtl = TextEditingController();
  Timer? _debounce;
  List<Comment>? _found;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _positions.itemPositions.addListener(_onPositions);
    unawaited(_open());
  }

  /// Row [index] of the list for the comment at [at] of [_comments], and back.
  int _rowOf(int at) => _comments.length - 1 - at;

  /// What is on the screen: the comments that are read by being there, and whether the
  /// few unread ones leave the list short of its end.
  void _onPositions() {
    final positions = _positions.itemPositions.value;
    if (positions.isEmpty || _comments.isEmpty) return;
    if (!_settled) {
      _settled = true;
      // A few unread comments do not fill the screen under the divider: the newest one
      // goes to the bottom edge instead of leaving a gap there.
      for (final p in positions) {
        if (p.index == 0 && p.itemLeadingEdge > 0.02 && _initialIndex > 0) {
          _scroll.jumpTo(index: 0, alignment: 0);
          return;
        }
      }
    }
    var newest = _seenUpTo;
    for (final p in positions) {
      if (p.index >= _comments.length) continue; // the post on top
      // Read once its lower edge is on the screen, as a post is.
      if (p.itemLeadingEdge < -0.02 || p.itemTrailingEdge > 1.2) continue;
      final id = _comments[_rowOf(p.index)].messageId;
      if (id > newest) newest = id;
    }
    if (newest > _seenUpTo) {
      _seenUpTo = newest;
      _readDebounce?.cancel();
      _readDebounce = Timer(
        const Duration(milliseconds: 300),
        () => unawaited(_reportRead()),
      );
    }
  }

  /// Tells Telegram which comments were seen since the last time it was told.
  Future<void> _reportRead() async {
    final t = _thread;
    final upTo = _seenUpTo;
    if (t == null || upTo <= _reportedUpTo) return;
    final ids = [
      for (final c in _comments)
        if (c.messageId > _reportedUpTo && c.messageId <= upTo) c.messageId,
    ];
    _reportedUpTo = upTo;
    if (ids.isEmpty) return;
    try {
      await widget.gateway.markCommentsViewed(t, ids);
    } on TelegramException {
      // The thread stays unread for Telegram; the next comment seen tells it again.
    }
  }

  void _openSearch() => setState(() => _searchOpen = true);

  void _closeSearch() {
    _debounce?.cancel();
    _queryCtl.clear();
    setState(() {
      _searchOpen = false;
      _found = null;
    });
  }

  void _onQuery(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(_search(value)),
    );
  }

  /// Telegram searches the thread itself, so a comment far above is found without loading
  /// everything in between.
  Future<void> _search(String value) async {
    final thread = _thread;
    final query = value.trim();
    if (thread == null) return;
    if (query.isEmpty) {
      setState(() => _found = null);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    setState(() => _searching = true);
    try {
      final found = await widget.gateway.searchThread(thread, query: query);
      if (mounted) setState(() => _found = found);
    } on TelegramException catch (e) {
      // A snackbar, not [_error]: the comments stay on screen, so a message hidden
      // behind them would never be read.
      if (mounted) {
        showTelegramError(
          messenger,
          e,
          what: l10n.threadSearchFailed,
          onRetry: () => unawaited(_search(value)),
        );
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _open() async {
    try {
      final t = await widget.gateway.discussion(
        widget.post.chatId,
        widget.post.messageId,
      );
      if (!mounted) return;
      if (t == null) {
        setState(() {
          _noThread = true;
          _loading = false;
        });
        return;
      }
      _thread = t;
      _reportedUpTo = t.lastReadId;
      _live = widget.gateway.comments.listen((c) {
        if (c.chatId != t.chatId || c.threadId != t.threadId) return;
        if (_comments.any((x) => x.messageId == c.messageId)) return;
        final atEnd = _nearEnd;
        // The row closest to the newest end: with a comment added below it every row
        // moves up by one, and a reader who is further up is put back where they were.
        ItemPosition? held;
        for (final p in _positions.itemPositions.value) {
          if (held == null || p.index < held.index) held = p;
        }
        setState(() {
          _comments.add(c);
          _arrived++;
        });
        if (atEnd) {
          _scrollToEnd();
        } else if (held != null && _scroll.isAttached) {
          _scroll.jumpTo(
            index: held.index + 1,
            alignment: held.itemLeadingEdge,
          );
        }
      });
      await _loadOlder(opening: true);
      // The official app opens a discussion at the first unread comment: the pages down
      // to it are loaded, within reason, and the list starts there under a divider. A
      // thread that was never opened, or has nothing new, opens at its newest comment.
      if (t.lastReadId > 0 && t.unreadCount > 0) {
        while (mounted &&
            !_exhausted &&
            _comments.isNotEmpty &&
            _comments.first.messageId > t.lastReadId &&
            _comments.length < _openCap) {
          await _loadOlder(opening: true);
        }
        final reached =
            _exhausted ||
            (_comments.isNotEmpty && _comments.first.messageId <= t.lastReadId);
        final at = _comments.indexWhere(
          (c) => c.messageId > t.lastReadId && !c.isOutgoing,
        );
        if (reached && at >= 0) {
          _firstUnread = _comments[at].messageId;
          // The row above the divider just under the top of the list.
          _initialIndex = _rowOf(at) + 1;
          _initialAlignment = 0.92;
        }
      }
      if (mounted) {
        setState(() {
          _loading = false;
          _opening = false;
        });
      }
    } on TelegramException catch (e) {
      _opening = false;
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  bool _loadingOlder = false;

  /// One more page of older comments. They go to the far end of the turned list, so what
  /// is on the screen stays where it is. While the thread [opening]s the spinner stays.
  Future<void> _loadOlder({bool opening = false}) async {
    final t = _thread;
    if (t == null || _exhausted || _loadingOlder) return;
    _loadingOlder = true;
    if (!opening) setState(() => _loading = true);
    try {
      final oldest = _comments.isEmpty ? 0 : _comments.first.messageId;
      final page = await widget.gateway.threadHistory(
        t,
        fromMessageId: oldest,
        limit: 30,
      );
      if (!mounted) return;
      setState(() {
        if (page.isEmpty) _exhausted = true;
        // Page is newest first; prepend in chronological order.
        _comments.insertAll(
          0,
          page.reversed.where(
            (c) => !_comments.any((x) => x.messageId == c.messageId),
          ),
        );
        if (!opening) _loading = false;
      });
    } on TelegramException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } finally {
      _loadingOlder = false;
    }
  }

  /// Leaves the search and shows that comment among the others, loading older ones
  /// until it is there.
  Future<void> _openFound(Comment target) async {
    setState(() {
      _found = null;
      _queryCtl.clear();
      _searchOpen = false;
    });
    var guard = 0;
    while (!_comments.any((c) => c.messageId == target.messageId) &&
        !_exhausted &&
        guard++ < 20) {
      await _loadOlder();
    }
    if (!mounted) return;
    final index = _comments.indexWhere((c) => c.messageId == target.messageId);
    if (index < 0) return;
    setState(() => _highlight = target.messageId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.isAttached) return;
      // The comment itself, a third of the way up the list; the tint says which one.
      _scroll.jumpTo(index: _rowOf(index), alignment: 0.3);
    });
  }

  /// "N comments", as the official app titles a discussion: what Telegram counted and
  /// what has arrived since; "Comments" while the number is not known or there are none.
  String _title(AppLocalizations l10n) {
    final count = math.max(
      (_thread?.replyCount ?? 0) + _arrived,
      _comments.length,
    );
    return count == 0
        ? l10n.commonComments
        : l10n.postCommentCount(count, '$count');
  }

  /// The comment a search result led to, tinted for a moment.
  int? _highlight;

  Future<void> _send() async {
    final t = _thread;
    final text = _composer.text.trim();
    if (t == null || text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.gateway.reply(t, text);
      _composer.clear();
    } on TelegramException catch (e) {
      if (mounted) {
        showTelegramError(
          ScaffoldMessenger.of(context),
          e,
          what: context.l10n.threadPostFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openLink(String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final uri = Uri.tryParse(url);
    if (uri != null && (widget.onOpenTelegramLink?.call(uri) ?? false)) return;
    if (await launchFirst([uri])) return;
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.timelineNoAppForLink(url))),
    );
  }

  /// True while the newest comment is (nearly) on screen.
  bool get _nearEnd {
    final positions = _positions.itemPositions.value;
    return positions.isEmpty || positions.any((p) => p.index <= 1);
  }

  void _scrollToEnd({bool onlyNearEnd = false, bool animate = true}) {
    if (onlyNearEnd && !_nearEnd) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.isAttached) return;
      if (animate) {
        unawaited(
          _scroll.scrollTo(
            index: 0,
            alignment: 0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          ),
        );
      } else {
        _scroll.jumpTo(index: 0, alignment: 0);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryCtl.dispose();
    _live?.cancel();
    _positions.itemPositions.removeListener(_onPositions);
    // What was seen in the last moment is told before the thread closes.
    _readDebounce?.cancel();
    unawaited(_reportRead());
    final t = _thread;
    if (t != null) unawaited(widget.gateway.closeThread(t));
    _composer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ChatColors.of(context);
    final l10n = context.l10n;
    final found = _found;
    return PopScope(
      canPop: !_searchOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeSearch();
      },
      child: Scaffold(
        appBar: _searchOpen
            ? AppBar(
                leading: BackButton(onPressed: _closeSearch),
                titleSpacing: 0,
                title: TextField(
                  controller: _queryCtl,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: l10n.threadSearchComments,
                    border: InputBorder.none,
                  ),
                  onChanged: _onQuery,
                ),
                actions: [
                  if (_queryCtl.text.isNotEmpty)
                    IconButton(
                      tooltip: l10n.commonClear,
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _queryCtl.clear();
                        _onQuery('');
                      },
                    ),
                ],
              )
            : AppBar(
                title: Text(_title(l10n)),
                actions: [
                  if (!_noThread)
                    IconButton(
                      tooltip: l10n.threadSearchComments,
                      icon: const Icon(Icons.search),
                      onPressed: _openSearch,
                    ),
                ],
              ),
        // The comments follow the reader's text size, like the posts.
        body: PostTextScale.wrap(
          context,
          ColoredBox(
            color: colors.background,
            child: Column(
              children: [
                Expanded(
                  child: _noThread
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              l10n.threadNoDiscussion,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : _error != null && _comments.isEmpty
                      ? ErrorState(
                          what: l10n.threadLoadFailed,
                          message: _error,
                          onRetry: () {
                            setState(() {
                              _error = null;
                              _loading = true;
                            });
                            unawaited(_open());
                          },
                        )
                      // While searching, what was found takes the place of the thread.
                      : found != null
                      ? (found.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(32),
                                  child: Text(
                                    _searching
                                        ? l10n.threadSearching
                                        : l10n.searchNothingFound(
                                            _queryCtl.text,
                                          ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                itemCount: found.length,
                                itemBuilder: (context, i) => InkWell(
                                  onTap: () => _openFound(found[i]),
                                  child: CommentBubble(
                                    comment: found[i],
                                    gateway: widget.gateway,
                                    onOpenLink: _openLink,
                                  ),
                                ),
                              ))
                      : _opening
                      ? const Center(child: CircularProgressIndicator())
                      : ScrollablePositionedList.builder(
                          reverse: true,
                          itemScrollController: _scroll,
                          itemPositionsListener: _positions,
                          initialScrollIndex: _initialIndex.clamp(
                            0,
                            _comments.length,
                          ),
                          initialAlignment: _initialAlignment,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _comments.length + 1,
                          itemBuilder: (context, i) {
                            // The post, on top of everything that is loaded.
                            if (i == _comments.length) return _header(l10n);
                            final comment = _comments[_rowOf(i)];
                            final bubble = AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              color: comment.messageId == _highlight
                                  ? Theme.of(context).colorScheme.primary
                                        .withValues(alpha: 0.12)
                                  : Colors.transparent,
                              child: CommentBubble(
                                comment: comment,
                                gateway: widget.gateway,
                                onOpenLink: _openLink,
                              ),
                            );
                            if (comment.messageId != _firstUnread) {
                              return bubble;
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                UnreadDivider(label: l10n.threadUnreadDivider),
                                bubble,
                              ],
                            );
                          },
                        ),
                ),
                if (_thread != null)
                  Material(
                    color: Theme.of(context).colorScheme.surface,
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _composer,
                                minLines: 1,
                                maxLines: 4,
                                decoration: InputDecoration(
                                  hintText: l10n.threadWriteComment,
                                  isDense: true,
                                ),
                                onSubmitted: (_) => _send(),
                              ),
                            ),
                            IconButton(
                              tooltip: l10n.threadSend,
                              icon: const Icon(Icons.send),
                              onPressed: _sending ? null : _send,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The post the comments belong to, as it looks in the timeline, as the official app
  /// shows it on top of its comments.
  Widget _header(AppLocalizations l10n) {
    // The list builds this row a little before it scrolls into view: time to fetch older
    // comments, as the timeline fetches older posts.
    if (!_exhausted && _thread != null && _error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_loadOlder());
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PostCard(
          item: widget.item ?? TimelineItem(widget.post),
          channelTitle: widget.channelTitle,
          channelPhoto: widget.channelPhoto,
          gateway: widget.gateway,
          onOpenLink: _openLink,
        ),
        if (!_exhausted && _thread != null)
          Padding(
            padding: const EdgeInsets.all(10),
            child: Center(
              child: _error != null
                  ? TextButton(
                      onPressed: () {
                        setState(() => _error = null);
                        unawaited(_loadOlder());
                      },
                      child: Text(l10n.threadLoadOlder),
                    )
                  : const SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
            ),
          )
        else if (_comments.isNotEmpty)
          ChatPill(l10n.threadDiscussionStarted)
        else if (!_loading)
          ChatPill(l10n.threadNoComments),
      ],
    );
  }
}

/// One comment: a bubble with the coloured name, the author's photo at the right end of
/// that line, the text and the time. Own comments sit on the right without name and photo.
class CommentBubble extends StatelessWidget {
  const CommentBubble({
    super.key,
    required this.comment,
    required this.gateway,
    this.onOpenLink,
  });
  final Comment comment;
  final TelegramGateway gateway;
  final void Function(String url)? onOpenLink;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = ChatColors.of(context);
    final c = comment;
    final own = c.isOutgoing;
    final media = c.media;
    final viewable =
        media != null && MediaViewerScreen.viewable([media]).isNotEmpty;
    final time = Text(
      formatTime(DateTime.fromMillisecondsSinceEpoch(c.date * 1000), context),
      style: TextStyle(
        fontSize: 12,
        height: 1.2,
        color: scheme.onSurfaceVariant,
      ),
    );
    final bubble = Material(
      color: own ? colors.ownBubble : colors.bubble,
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(14),
          topRight: const Radius.circular(14),
          bottomLeft: const Radius.circular(14),
          bottomRight: Radius.circular(own ? 4 : 14),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        // Words make the bubble as wide as they are. A picture, a player or a file row
        // cannot say how wide it wants to be, so such a bubble has a width of its own.
        child: _BubbleWidth(
          width: media == null
              ? null
              : media is StickerMedia
              ? 180
              : 280,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!own)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: BubbleTitle(
                    name: c.author,
                    colorId: c.authorId,
                    photo: c.authorPhoto,
                    gateway: gateway,
                  ),
                ),
              if (media != null)
                Padding(
                  padding: EdgeInsets.only(bottom: c.text.isEmpty ? 2 : 6),
                  child: media is StickerMedia
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: StickerView(
                            sticker: media,
                            gateway: gateway,
                            side: 140,
                          ),
                        )
                      : ConstrainedBox(
                          // A tall picture is cut to this height.
                          constraints: const BoxConstraints(maxHeight: 320),
                          child: MediaView(
                            media: media,
                            gateway: gateway,
                            onOpen: viewable
                                ? () => unawaited(
                                    MediaViewerScreen.open(
                                      context,
                                      items: [media],
                                      gateway: gateway,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                ),
              // A comment that is only a picture has its time under it.
              if (c.text.isEmpty && media != null)
                Align(alignment: Alignment.centerRight, child: time)
              else
                BubbleText(
                  text: FormattedText(
                    text: c.text,
                    entities: c.entities,
                    onOpenLink: onOpenLink,
                    gateway: gateway,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.3,
                      color: scheme.onSurface,
                    ),
                  ),
                  footer: time,
                ),
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(own ? 48 : 8, 3, own ? 8 : 48, 3),
      child: Align(
        alignment: own ? Alignment.centerRight : Alignment.centerLeft,
        child: bubble,
      ),
    );
  }
}

/// As wide as its child wants to be, or [width] where that is given.
class _BubbleWidth extends StatelessWidget {
  const _BubbleWidth({required this.width, required this.child});
  final double? width;
  final Widget child;

  @override
  Widget build(BuildContext context) => width == null
      ? IntrinsicWidth(child: child)
      : SizedBox(width: width, child: child);
}
