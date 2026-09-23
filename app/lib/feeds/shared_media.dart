import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../media/media_viewer.dart';
import '../widgets/error_state.dart';
import 'media_view.dart';
import 'open_links.dart';
import 'post_card.dart' show formatDay;

/// The shared media of a channel — or of every channel of a feed at once, merged by date
/// and filtered like the feed (ARCHITECTURE.md 5.10). The tabs are the ones of the official
/// app: Media, Files, Links, Music and Voice.
class SharedMediaTabs extends StatelessWidget {
  const SharedMediaTabs({
    super.key,
    required this.gateway,
    required this.chatIds,
    this.filter = FeedFilter.none,
    this.titles = const {},
    this.header,
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

  /// The tabs, in the order of the official app. The feed editor puts its own "Channels"
  /// tab in front of them and builds the pages itself.
  static const kinds = <(String, HistoryFilter)>[
    ('Media', HistoryFilter.photoAndVideo),
    ('Files', HistoryFilter.document),
    ('Links', HistoryFilter.url),
    ('Music', HistoryFilter.audio),
    ('Voice', HistoryFilter.voice),
  ];

  @override
  Widget build(BuildContext context) {
    if (chatIds.isEmpty) {
      final empty = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [Text('No channels yet.')],
          ),
        ),
      );
      return header == null
          ? empty
          : ListView(children: [header!, const SizedBox(height: 48), empty]);
    }
    final bar = TabBar(
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      tabs: [for (final (label, _) in kinds) Tab(text: label)],
    );
    final views = TabBarView(
      children: [
        for (final (label, kind) in kinds)
          SharedMediaTab(
            key: ValueKey('$label:${chatIds.join(",")}'),
            gateway: gateway,
            chatIds: chatIds,
            kind: kind,
            filter: filter,
            titles: titles,
          ),
      ],
    );
    return DefaultTabController(
      length: kinds.length,
      child: header == null
          ? Column(
              children: [
                bar,
                Expanded(child: views),
              ],
            )
          // The header scrolls away with the media and the tabs stay under the app bar,
          // so a long description cannot squeeze the tabs off the screen.
          : NestedScrollView(
              headerSliverBuilder: (context, _) => [
                SliverToBoxAdapter(child: header),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _PinnedTabBar(bar),
                ),
              ],
              body: views,
            ),
    );
  }
}

/// Keeps the media tabs under the app bar while the header above them scrolls away.
class _PinnedTabBar extends SliverPersistentHeaderDelegate {
  _PinnedTabBar(this.bar);
  final TabBar bar;

  @override
  double get minExtent => bar.preferredSize.height;
  @override
  double get maxExtent => bar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      Material(color: Theme.of(context).colorScheme.surface, child: bar);

  @override
  bool shouldRebuild(_PinnedTabBar old) => old.bar != bar;
}

/// One tab: a search with no query and one media filter, paged as it is scrolled.
class SharedMediaTab extends StatefulWidget {
  const SharedMediaTab({
    super.key,
    required this.gateway,
    required this.chatIds,
    required this.kind,
    this.filter = FeedFilter.none,
    this.titles = const {},
  });

  final TelegramGateway gateway;
  final List<int> chatIds;
  final HistoryFilter kind;
  final FeedFilter filter;

  /// Channel titles by chat id, for what the viewer says about a picture.
  final Map<int, String> titles;

  @override
  State<SharedMediaTab> createState() => _SharedMediaTabState();
}

class _SharedMediaTabState extends State<SharedMediaTab>
    with AutomaticKeepAliveClientMixin {
  late final FeedSearch _search = FeedSearch(
    widget.gateway,
    widget.chatIds,
    filter: widget.kind,
    feedFilter: widget.filter,
  );
  bool _loading = false;
  bool _started = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    unawaited(_more());
  }

  Future<void> _more() async {
    if (_loading || _search.exhausted) return;
    setState(() => _loading = true);
    try {
      await _search.loadMore();
      _error = null;
    } on TelegramException catch (e) {
      _error = e.message;
    } finally {
      _started = true;
      if (mounted) setState(() => _loading = false);
    }
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
      details.addAll(
        List.filled(
          shown.length,
          ViewerDetail(
            channel: widget.titles[p.chatId] ?? '',
            date: p.date,
            caption: p.text,
            postKey: '${p.chatId}:${p.messageId}',
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final results = _search.results;
    if (results.isEmpty) {
      if (_loading || !_started) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          ),
        );
      }
      if (_error != null) {
        return ErrorState(
          what: 'Could not load this media.',
          message: _error,
          onRetry: () {
            setState(() {
              _error = null;
              _started = false;
            });
            unawaited(_more());
          },
        );
      }
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('Nothing here yet.', textAlign: TextAlign.center),
        ),
      );
    }
    final grid = widget.kind == HistoryFilter.photoAndVideo;
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.pixels > n.metrics.maxScrollExtent - 600) {
          unawaited(_more());
        }
        return false;
      },
      child: grid ? _grid(results) : _list(results),
    );
  }

  Widget _grid(List<Post> results) => GridView.builder(
    padding: const EdgeInsets.all(2),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 3,
      mainAxisSpacing: 2,
      crossAxisSpacing: 2,
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
        : MediaTile(
            post: results[i],
            gateway: widget.gateway,
            onTap: () => _openViewer(results[i]),
          ),
  );

  Widget _list(List<Post> results) => ListView.separated(
    padding: const EdgeInsets.symmetric(vertical: 8),
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
      if (widget.kind == HistoryFilter.url) return LinkRow(post: post);
      if (media is DocumentMedia) {
        return FileRow(post: post, media: media, gateway: widget.gateway);
      }
      return MediaRow(post: post, gateway: widget.gateway);
    },
  );
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
    return Semantics(
      label: switch (media) {
        VideoMedia(:final isAnimation, :final durationSeconds) =>
          isAnimation
              ? 'GIF, ${formatDay(DateTime.fromMillisecondsSinceEpoch(post.date * 1000))}'
              : 'Video ${formatDuration(durationSeconds)}, '
                    '${formatDay(DateTime.fromMillisecondsSinceEpoch(post.date * 1000))}',
        PhotoMedia() =>
          'Photo, ${formatDay(DateTime.fromMillisecondsSinceEpoch(post.date * 1000))}',
        _ =>
          'Post of ${formatDay(DateTime.fromMillisecondsSinceEpoch(post.date * 1000))}',
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
                      ? 'GIF'
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
        trailing: IconButton(
          tooltip: 'Open with…',
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
      leading: const Icon(Icons.insert_drive_file_outlined, size: 32),
      title: Text(media.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${formatBytes(media.file.size)} · ${formatDay(day)}'),
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
              formatDay(day),
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
    final day = DateTime.fromMillisecondsSinceEpoch(post.date * 1000);
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
        text.isEmpty ? formatDay(day) : '$text · ${formatDay(day)}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: link == null
          ? null
          : () async {
              final messenger = ScaffoldMessenger.of(context);
              if (await launchFirst([Uri.tryParse(link)])) return;
              messenger.showSnackBar(
                SnackBar(content: Text('No app can open $link')),
              );
            },
    );
  }
}
