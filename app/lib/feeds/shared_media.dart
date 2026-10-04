import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../host/haptics.dart';
import '../l10n/l10n.dart';
import '../media/media_viewer.dart';
import '../widgets/error_state.dart';
import '../widgets/menu_item.dart';
import 'media_view.dart';
import 'open_links.dart';
import 'post_card.dart' show formatDay;

/// How many columns the media grids have, from two to nine: what the reader's pinch last
/// chose, for every grid while the app runs. Three, as the official app starts.
final mediaGridColumns = ValueNotifier<int>(3);

/// The shared media of a channel — or of every channel of a feed at once, merged by date
/// and filtered like the feed (ARCHITECTURE.md 5.10). The tabs are the ones of the official
/// app: Media, Files, Links, Music, Voice and GIFs, and a kind nobody posted has no tab.
class SharedMediaTabs extends StatefulWidget {
  const SharedMediaTabs({
    super.key,
    required this.gateway,
    required this.chatIds,
    this.filter = FeedFilter.none,
    this.titles = const {},
    this.header,
    this.onShowInChat,
  });

  final TelegramGateway gateway;
  final List<int> chatIds;

  /// The feed's content filter; a channel of its own has none.
  final FeedFilter filter;

  /// Channel titles by chat id, for what the viewer says about a picture.
  final Map<int, String> titles;

  /// Shown above the tabs and scrolled away with them, as the official app's channel
  /// header is. Without one the tabs fill the whole box.
  final Widget? header;

  /// Goes to the post an item belongs to: "Show in chat" of an item's long press. Without
  /// it the items have no menu.
  final void Function(Post post)? onShowInChat;

  /// The tabs, in the order of the official app.
  static List<(String, HistoryFilter)> kindsOf(AppLocalizations l10n) => [
    (l10n.tabMedia, HistoryFilter.photoAndVideo),
    (l10n.tabFiles, HistoryFilter.document),
    (l10n.tabLinks, HistoryFilter.url),
    (l10n.tabMusic, HistoryFilter.audio),
    (l10n.tabVoice, HistoryFilter.voice),
    (l10n.tabGifs, HistoryFilter.animation),
  ];

  @override
  State<SharedMediaTabs> createState() => _SharedMediaTabsState();
}

class _SharedMediaTabsState extends State<SharedMediaTabs>
    with TickerProviderStateMixin {
  /// The kinds that have a tab; null until Telegram has counted them.
  List<HistoryFilter>? _kinds;
  TabController? _tabs;

  /// What the Media tab shows: photos, videos, or both.
  bool _photos = true;
  bool _videos = true;

  @override
  void initState() {
    super.initState();
    unawaited(_count());
  }

  @override
  void dispose() {
    _tabs?.dispose();
    super.dispose();
  }

  /// Asks Telegram how many posts of each kind the channels have. A kind with none gets
  /// no tab; a kind that could not be counted keeps its tab.
  Future<void> _count() async {
    final sums = <HistoryFilter, int>{};
    final unknown = <HistoryFilter>{};
    await Future.wait([
      for (final id in widget.chatIds)
        () async {
          try {
            final counts = await widget.gateway.mediaCounts(id);
            for (final kind in sharedMediaKinds) {
              final n = counts[kind];
              if (n == null || n < 0) {
                unknown.add(kind);
              } else {
                sums[kind] = (sums[kind] ?? 0) + n;
              }
            }
          } on TelegramException {
            unknown.addAll(sharedMediaKinds);
          }
        }(),
    ]);
    if (!mounted) return;
    final kinds = [
      for (final kind in sharedMediaKinds)
        if (unknown.contains(kind) || (sums[kind] ?? 0) > 0) kind,
    ];
    setState(() {
      _kinds = kinds;
      _tabs?.dispose();
      _tabs = kinds.isEmpty
          ? null
          : (TabController(length: kinds.length, vsync: this)
              // The button of the Media tab comes and goes with it.
              ..addListener(() {
                if (mounted) setState(() {});
              }));
    });
  }

  /// The kind the Media tab asks for, by its two switches.
  HistoryFilter get _mediaKind => _photos && _videos
      ? HistoryFilter.photoAndVideo
      : _photos
      ? HistoryFilter.photo
      : HistoryFilter.video;

  /// One of the two is always shown: switching the last one off switches the other on.
  void _toggle({required bool photos}) => setState(() {
    if (photos) {
      _photos = !_photos;
      if (!_photos) _videos = true;
    } else {
      _videos = !_videos;
      if (!_videos) _photos = true;
    }
  });

  Widget _message(String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [Text(text)]),
    ),
  );

  /// The header over something that has no tabs: a message, or the wait for the counts.
  Widget _alone(Widget body) => widget.header == null
      ? body
      : ListView(children: [widget.header!, const SizedBox(height: 48), body]);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (widget.chatIds.isEmpty) {
      return _alone(_message(l10n.sharedMediaNoChannels));
    }
    final kinds = _kinds;
    final tabs = _tabs;
    if (kinds == null) {
      return _alone(const Center(child: CircularProgressIndicator()));
    }
    if (kinds.isEmpty || tabs == null) {
      return _alone(_message(l10n.sharedMediaEmpty));
    }
    final labels = {
      for (final (label, kind) in SharedMediaTabs.kindsOf(l10n)) kind: label,
    };
    final onMedia = kinds[tabs.index] == HistoryFilter.photoAndVideo;
    final bar = Row(
      children: [
        Expanded(
          child: TabBar(
            controller: tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            // The line under the tabs runs under the Media tab's button too: the bar
            // draws it.
            dividerHeight: 0,
            tabs: [for (final kind in kinds) Tab(text: labels[kind])],
          ),
        ),
        // Photos, videos or both, as the official app's media tab offers in its menu.
        if (onMedia)
          PopupMenuButton<bool>(
            tooltip: l10n.sharedMediaFilter,
            icon: const Icon(Icons.filter_list),
            onSelected: (photos) => _toggle(photos: photos),
            itemBuilder: (context) => [
              CheckedPopupMenuItem(
                value: true,
                checked: _photos,
                child: Text(l10n.sharedMediaPhotos),
              ),
              CheckedPopupMenuItem(
                value: false,
                checked: _videos,
                child: Text(l10n.sharedMediaVideos),
              ),
            ],
          ),
      ],
    );
    final views = TabBarView(
      controller: tabs,
      children: [
        for (final kind in kinds)
          () {
            final asked = kind == HistoryFilter.photoAndVideo
                ? _mediaKind
                : kind;
            return SharedMediaTab(
              key: ValueKey('${asked.name}:${widget.chatIds.join(",")}'),
              gateway: widget.gateway,
              chatIds: widget.chatIds,
              kind: asked,
              filter: widget.filter,
              titles: widget.titles,
              onShowInChat: widget.onShowInChat,
            );
          }(),
      ],
    );
    final scheme = Theme.of(context).colorScheme;
    final surface = Material(
      color: scheme.surface,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
        ),
        child: bar,
      ),
    );
    return widget.header == null
        ? Column(
            children: [
              surface,
              Expanded(child: views),
            ],
          )
        // The header scrolls away with the media and the tabs stay under the app bar,
        // so a long description cannot squeeze the tabs off the screen.
        : NestedScrollView(
            headerSliverBuilder: (context, _) => [
              SliverToBoxAdapter(child: widget.header),
              SliverPersistentHeader(
                pinned: true,
                delegate: _PinnedTabBar(surface, onMedia: onMedia),
              ),
            ],
            body: views,
          );
  }
}

/// Keeps the media tabs under the app bar while the header above them scrolls away.
class _PinnedTabBar extends SliverPersistentHeaderDelegate {
  _PinnedTabBar(this.bar, {required this.onMedia});
  final Widget bar;

  /// Whether the bar carries the Media tab's button: it is rebuilt when that changes.
  final bool onMedia;

  @override
  double get minExtent => kTextTabBarHeight;
  @override
  double get maxExtent => kTextTabBarHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) => bar;

  @override
  bool shouldRebuild(_PinnedTabBar old) => true;
}

/// One tab: a search with one media filter, with words or without, paged as it is
/// scrolled.
class SharedMediaTab extends StatefulWidget {
  const SharedMediaTab({
    super.key,
    required this.gateway,
    required this.chatIds,
    required this.kind,
    this.filter = FeedFilter.none,
    this.titles = const {},
    this.onShowInChat,
  });

  final TelegramGateway gateway;
  final List<int> chatIds;
  final HistoryFilter kind;
  final FeedFilter filter;

  /// Channel titles by chat id, for what the viewer says about a picture.
  final Map<int, String> titles;

  /// "Show in chat" of an item's long press; without it the items have no menu.
  final void Function(Post post)? onShowInChat;

  @override
  State<SharedMediaTab> createState() => _SharedMediaTabState();
}

class _SharedMediaTabState extends State<SharedMediaTab>
    with AutomaticKeepAliveClientMixin {
  late FeedSearch _search = _newSearch();
  bool _loading = false;
  bool _started = false;
  String? _error;

  /// The words the tab is searched for: Files, Links and Music have a field for them.
  String _query = '';
  Timer? _debounce;

  /// Fingers on the grid: with two of them it is a pinch and the grid does not scroll.
  int _fingers = 0;
  double _pinchFrom = 1;

  /// Where the grid stands, for the date scroller.
  ScrollPosition? _position;

  /// The scroller is being dragged: the date it stands on is shown.
  bool _scrubbing = false;

  bool get _isGrid => const {
    HistoryFilter.photoAndVideo,
    HistoryFilter.photo,
    HistoryFilter.video,
    HistoryFilter.animation,
  }.contains(widget.kind);

  bool get _searchable => const {
    HistoryFilter.document,
    HistoryFilter.url,
    HistoryFilter.audio,
  }.contains(widget.kind);

  FeedSearch _newSearch() => FeedSearch(
    widget.gateway,
    widget.chatIds,
    query: _query,
    filter: widget.kind,
    feedFilter: widget.filter,
  );

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    unawaited(_more());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _more() async {
    final search = _search;
    if (_loading || search.exhausted) return;
    setState(() => _loading = true);
    try {
      await search.loadMore();
      _error = null;
    } on TelegramException catch (e) {
      _error = e.message;
    } finally {
      // Words typed meanwhile started a search of their own.
      if (identical(search, _search)) _started = true;
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onQuery(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final query = value.trim();
      if (!mounted || query == _query) return;
      setState(() {
        _query = query;
        _search = _newSearch();
        _started = false;
        _loading = false;
        _error = null;
      });
      unawaited(_more());
    });
  }

  /// Everything the viewer can show in this tab, so it pages through the whole grid.
  void _openViewer(Post post) {
    final items = <Media>[];
    final details = <ViewerDetail>[];
    var initial = 0;
    for (final p in _search.results) {
      final media = p.media;
      if (media == null) continue;
      final shown = MediaViewerScreen.viewable([media]);
      if (identical(p, post)) initial = items.length;
      items.addAll(shown);
      // The channel, the day and the caption, as the timeline hands them over: a
      // picture opened from the grid used to arrive with no word about where it is from.
      final show = widget.onShowInChat;
      details.addAll(
        List.filled(
          shown.length,
          ViewerDetail(
            channel: widget.titles[p.chatId] ?? '',
            date: p.date,
            caption: p.text,
            entities: p.entities,
            postKey: '${p.chatId}:${p.messageId}',
            protected: !p.canBeSaved,
            onShowInChat: show == null ? null : () => show(p),
          ),
        ),
      );
    }
    if (items.isEmpty) return;
    unawaited(
      MediaViewerScreen.open(
        context,
        items: items,
        gateway: widget.gateway,
        initialIndex: initial,
        details: details,
      ),
    );
  }

  /// The menu of an item, where it was touched: "Show in chat", as in the official app.
  Future<void> _itemMenu(Post post, Offset at) async {
    final show = widget.onShowInChat;
    if (show == null) return;
    Haptics.longPress();
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        at & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: [
        menuItem(
          'show',
          Icons.chat_bubble_outline,
          context.l10n.sharedMediaShowInChat,
        ),
      ],
    );
    if (choice == 'show') show(post);
  }

  /// An item with its long-press menu.
  Widget _item(Post post, Widget child) => widget.onShowInChat == null
      ? child
      : GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPressStart: (d) => unawaited(_itemMenu(post, d.globalPosition)),
          child: child,
        );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = context.l10n;
    final results = _search.results;
    final Widget body;
    if (results.isEmpty) {
      if (_loading || !_started) {
        body = const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          ),
        );
      } else if (_error != null) {
        body = ErrorState(
          what: l10n.sharedMediaLoadFailed,
          message: _error,
          onRetry: () {
            setState(() {
              _error = null;
              _started = false;
            });
            unawaited(_more());
          },
        );
      } else {
        body = Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              _query.isEmpty
                  ? l10n.sharedMediaEmpty
                  : l10n.sharedMediaNothingFound(_query),
              textAlign: TextAlign.center,
            ),
          ),
        );
      }
    } else {
      body = NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.axis != Axis.vertical) return false;
          if (n.metrics.pixels > n.metrics.maxScrollExtent - 600) {
            unawaited(_more());
          }
          return false;
        },
        child: _isGrid ? _grid(results) : _list(results),
      );
    }
    if (!_searchable) return body;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: l10n.sharedMediaSearchHint,
              isDense: true,
            ),
            textInputAction: TextInputAction.search,
            onChanged: _onQuery,
          ),
        ),
        Expanded(child: body),
      ],
    );
  }

  /// The grid, with the pinch that changes its columns and the scroller along its edge.
  Widget _grid(List<Post> results) => ValueListenableBuilder<int>(
    valueListenable: mediaGridColumns,
    builder: (context, columns, _) => LayoutBuilder(
      builder: (context, box) {
        const gap = 2.0;
        // A row of square cells: what the scroller needs to tell which item is on top.
        final rowExtent =
            (box.maxWidth - 2 * gap - (columns - 1) * gap) / columns + gap;
        final grid = GridView.builder(
          padding: const EdgeInsets.all(gap),
          // Two fingers pinch; one scrolls.
          physics: _fingers >= 2 ? const NeverScrollableScrollPhysics() : null,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: gap,
            crossAxisSpacing: gap,
          ),
          itemCount: results.length + (_search.exhausted ? 0 : 1),
          itemBuilder: (context, i) => i == results.length
              ? const Center(
                  child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : _item(
                  results[i],
                  MediaTile(
                    post: results[i],
                    gateway: widget.gateway,
                    onTap: () => _openViewer(results[i]),
                  ),
                ),
        );
        return Listener(
          onPointerDown: (_) => _setFingers(_fingers + 1),
          onPointerUp: (_) => _setFingers(_fingers - 1),
          onPointerCancel: (_) => _setFingers(_fingers - 1),
          child: GestureDetector(
            onScaleStart: (_) => _pinchFrom = 1,
            onScaleUpdate: (d) {
              if (d.pointerCount < 2) return;
              // Spreading the fingers makes the pictures larger: fewer columns.
              final ratio = d.scale / _pinchFrom;
              if (ratio > 1.25 && columns > 2) {
                mediaGridColumns.value = columns - 1;
                _pinchFrom = d.scale;
                Haptics.reaction();
              } else if (ratio < 0.8 && columns < 9) {
                mediaGridColumns.value = columns + 1;
                _pinchFrom = d.scale;
                Haptics.reaction();
              }
            },
            child: NotificationListener<ScrollMetricsNotification>(
              onNotification: (n) {
                _track(n.context);
                return false;
              },
              child: NotificationListener<ScrollUpdateNotification>(
                onNotification: (n) {
                  _track(n.context);
                  return false;
                },
                child: Stack(
                  children: [
                    grid,
                    _DateScroller(
                      position: _position,
                      scrubbing: _scrubbing,
                      label: _dateAt(results, columns, rowExtent),
                      onScrub: (scrubbing) =>
                          setState(() => _scrubbing = scrubbing),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );

  void _setFingers(int n) {
    final next = n < 0 ? 0 : n;
    // Only the change between scrolling and pinching rebuilds the grid.
    if ((next >= 2) != (_fingers >= 2)) {
      setState(() => _fingers = next);
    } else {
      _fingers = next;
    }
  }

  /// Remembers the grid's scroll position, and redraws the scroller as it moves.
  void _track(BuildContext? scrolled) {
    if (scrolled == null) return;
    final position = Scrollable.maybeOf(scrolled)?.position;
    if (position == null || position.axis != Axis.vertical) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _position = position);
    });
  }

  /// The month of the item at the top of the grid, for the scroller's label.
  String _dateAt(List<Post> results, int columns, double rowExtent) {
    final position = _position;
    if (position == null || results.isEmpty || !position.hasPixels) return '';
    final row = (position.pixels / rowExtent).floor().clamp(0, 1 << 30);
    final index = (row * columns).clamp(0, results.length - 1);
    final l10n = context.l10n;
    return DateFormat.yMMMM(
      l10n.localeName == 'en' ? 'en_US' : l10n.localeName,
    ).format(DateTime.fromMillisecondsSinceEpoch(results[index].date * 1000));
  }

  Widget _list(List<Post> results) => ListView.separated(
    padding: const EdgeInsets.symmetric(vertical: 8),
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    itemCount: results.length + (_search.exhausted ? 0 : 1),
    separatorBuilder: (_, _) => const Divider(height: 1),
    itemBuilder: (context, i) {
      if (i == results.length) {
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      }
      final post = results[i];
      final media = post.media;
      if (widget.kind == HistoryFilter.url) {
        return _item(post, LinkRow(post: post));
      }
      if (media is DocumentMedia) {
        return _item(
          post,
          FileRow(post: post, media: media, gateway: widget.gateway),
        );
      }
      return _item(post, MediaRow(post: post, gateway: widget.gateway));
    },
  );
}

/// The handle along the right edge of a media grid: it stands where the grid stands, and
/// dragging it runs through what is loaded, with the month it passes shown beside it, as
/// the official app's media tab scrolls by date. Reaching its end loads more.
class _DateScroller extends StatelessWidget {
  const _DateScroller({
    required this.position,
    required this.scrubbing,
    required this.label,
    required this.onScrub,
  });
  final ScrollPosition? position;
  final bool scrubbing;
  final String label;
  final ValueChanged<bool> onScrub;

  static const _handle = 44.0;

  @override
  Widget build(BuildContext context) {
    final position = this.position;
    if (position == null ||
        !position.hasContentDimensions ||
        position.maxScrollExtent <= 0) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, box) {
          final track = box.maxHeight - _handle;
          final fraction = (position.pixels / position.maxScrollExtent).clamp(
            0.0,
            1.0,
          );
          void drag(double dy) {
            final at = ((dy - _handle / 2) / track).clamp(0.0, 1.0);
            position.jumpTo(at * position.maxScrollExtent);
          }

          return Stack(
            children: [
              Positioned(
                right: 0,
                top: fraction * track,
                height: _handle,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (scrubbing && label.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.inverseSurface,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(color: scheme.onInverseSurface),
                        ),
                      ),
                    Semantics(
                      label: context.l10n.sharedMediaScroller,
                      child: GestureDetector(
                        key: const ValueKey('date-scroller'),
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragStart: (d) {
                          onScrub(true);
                          final local =
                              (context.findRenderObject()! as RenderBox)
                                  .globalToLocal(d.globalPosition);
                          drag(local.dy);
                        },
                        onVerticalDragUpdate: (d) {
                          final local =
                              (context.findRenderObject()! as RenderBox)
                                  .globalToLocal(d.globalPosition);
                          drag(local.dy);
                        },
                        onVerticalDragEnd: (_) => onScrub(false),
                        onVerticalDragCancel: () => onScrub(false),
                        child: SizedBox(
                          width: 28,
                          height: _handle,
                          child: Center(
                            child: Container(
                              width: 6,
                              height: 36,
                              decoration: BoxDecoration(
                                color: scheme.onSurface.withValues(
                                  alpha: scrubbing ? 0.7 : 0.35,
                                ),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A cell of the media grid: the picture, cropped, with the length of a video on it.
class MediaTile extends StatelessWidget {
  const MediaTile({
    super.key,
    required this.post,
    required this.gateway,
    required this.onTap,
  });

  final Post post;
  final TelegramGateway gateway;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final media = post.media;
    final scheme = Theme.of(context).colorScheme;
    // A play arrow here used to promise a video even for a poll or a sticker.
    final empty = ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          media is VideoMedia
              ? Icons.play_arrow
              : Icons.image_not_supported_outlined,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
    Widget picture;
    switch (media) {
      case PhotoMedia(:final sizes):
        picture = PhotoView(
          file: sizes.first, // the grid is small: the thumbnail is enough
          gateway: gateway,
          heroTag: mediaHeroTag('${post.chatId}:${post.messageId}', 0),
          fill: true,
          radius: 0,
          onTap: onTap,
        );
      case VideoMedia(:final thumbnail):
        picture = thumbnail == null
            ? empty
            : PhotoView(
                file: thumbnail,
                gateway: gateway,
                heroTag: mediaHeroTag('${post.chatId}:${post.messageId}', 0),
                fill: true,
                radius: 0,
                onTap: onTap,
              );
      default:
        picture = empty;
    }
    final l10n = context.l10n;
    final day = formatDay(
      DateTime.fromMillisecondsSinceEpoch(post.date * 1000),
      l10n: l10n,
    );
    return Semantics(
      label: switch (media) {
        VideoMedia(:final isAnimation, :final durationSeconds) =>
          isAnimation
              ? l10n.sharedMediaGifTile(day)
              : l10n.sharedMediaVideoTile(formatDuration(durationSeconds), day),
        PhotoMedia() => l10n.sharedMediaPhotoTile(day),
        _ => l10n.sharedMediaPostTile(day),
      },
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            picture,
            if (media is VideoMedia)
              Positioned(
                left: 4,
                bottom: 4,
                child: MediaBadge(
                  media.isAnimation
                      ? l10n.mediaGif
                      : formatDuration(media.durationSeconds),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A row of the Files tab: name, size and day, with the download control of the timeline
/// at its end. The name is there before the file is, which the plain document view cannot
/// show since it only knows the file once it is downloaded.
class FileRow extends StatelessWidget {
  const FileRow({
    super.key,
    required this.post,
    required this.media,
    required this.gateway,
  });
  final Post post;
  final DocumentMedia media;
  final TelegramGateway gateway;

  @override
  Widget build(BuildContext context) {
    final day = DateTime.fromMillisecondsSinceEpoch(post.date * 1000);
    return Downloaded(
      file: media.file,
      gateway: gateway,
      autoStart: false,
      // The row itself is the button, and it keeps its shape while the file comes.
      pending: (context, start, progress, started) => _fileTile(
        context,
        day: day,
        trailing: started
            ? SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 2,
                ),
              )
            : const Icon(Icons.download_outlined),
        onTap: started ? null : start,
      ),
      builder: (context, path) => _fileTile(
        context,
        day: day,
        onTap: () =>
            unawaited(openDownloadedFile(context, path, media.mimeType)),
        trailing: IconButton(
          tooltip: context.l10n.postOpenWith,
          icon: const Icon(Icons.open_in_new),
          onPressed: () => unawaited(
            SharePlus.instance.share(
              ShareParams(files: [XFile(path, name: media.fileName)]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fileTile(
    BuildContext context, {
    required DateTime day,
    required Widget trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: SizedBox.square(
        dimension: 40,
        child: FileThumbnail(
          thumbnail: media.thumbnail,
          gateway: gateway,
          iconSize: 32,
        ),
      ),
      title: Text(media.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${formatBytes(media.file.size)} · '
        '${formatDay(day, l10n: context.l10n)}',
      ),
      trailing: trailing,
    );
  }
}

/// A row of the Music and Voice tabs: the media with its own controls, and the day.
class MediaRow extends StatelessWidget {
  const MediaRow({super.key, required this.post, required this.gateway});
  final Post post;
  final TelegramGateway gateway;

  @override
  Widget build(BuildContext context) {
    final media = post.media;
    final day = DateTime.fromMillisecondsSinceEpoch(post.date * 1000);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (media != null) MediaView(media: media, gateway: gateway),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              formatDay(day, l10n: context.l10n),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// A row of the Links tab: the first link of the post, its text, and the day.
class LinkRow extends StatelessWidget {
  const LinkRow({super.key, required this.post});
  final Post post;

  /// The first link of the post: a link entity, else the first URL in the text.
  static String? linkOf(Post post) {
    for (final e in post.entities) {
      if (e.kind != TextEntityKind.link) continue;
      final url = e.url;
      if (url != null && url.isNotEmpty) return url;
      if (e.offset >= 0 && e.end <= post.text.length) {
        return post.text.substring(e.offset, e.end);
      }
    }
    final match = RegExp(r'https?://\S+').firstMatch(post.text);
    return match?.group(0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final link = linkOf(post);
    final day = formatDay(
      DateTime.fromMillisecondsSinceEpoch(post.date * 1000),
      l10n: context.l10n,
    );
    final text = post.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return ListTile(
      leading: const Icon(Icons.link),
      title: Text(
        link ?? text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: theme.colorScheme.primary),
      ),
      subtitle: Text(
        text.isEmpty ? day : '$text · $day',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: link == null
          ? null
          : () async {
              final messenger = ScaffoldMessenger.of(context);
              final failed = context.l10n.sharedMediaNoAppCanOpen(link);
              if (await launchFirst([Uri.tryParse(link)])) return;
              messenger.showSnackBar(SnackBar(content: Text(failed)));
            },
    );
  }
}
