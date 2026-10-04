import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../home/channel_list.dart' show ChannelAvatar, formatListDate;
import '../l10n/l10n.dart';
import '../media/media_viewer.dart';
import '../widgets/error_state.dart';
import 'formatted_text.dart' show foundRanges;
import 'post_card.dart' show peerColor;
import 'shared_media.dart' show FileRow, LinkRow, MediaRow, MediaTile;

/// The chips under a search bar: what kind of post to look for, as the official app offers
/// inside its search. "Everything" is the plain text search.
class SearchFilterChips extends StatelessWidget {
  const SearchFilterChips({
    super.key,
    required this.filter,
    required this.onChanged,
    this.leading,
  });
  final HistoryFilter filter;
  final ValueChanged<HistoryFilter> onChanged;

  /// What stands before the kinds: the span of days the search is narrowed to.
  final Widget? leading;

  /// The kinds of post the chips offer, in their order.
  static const _filters = [
    HistoryFilter.any,
    HistoryFilter.photoAndVideo,
    HistoryFilter.url,
    HistoryFilter.document,
    HistoryFilter.audio,
    HistoryFilter.voice,
  ];

  static String labelOf(HistoryFilter f, AppLocalizations l10n) => switch (f) {
    HistoryFilter.any => l10n.searchFilterEverything,
    HistoryFilter.photoAndVideo => l10n.tabMedia,
    HistoryFilter.url => l10n.tabLinks,
    HistoryFilter.document => l10n.tabFiles,
    HistoryFilter.audio => l10n.tabMusic,
    HistoryFilter.voice => l10n.tabVoice,
    HistoryFilter.photo => l10n.sharedMediaPhotos,
    HistoryFilter.video => l10n.sharedMediaVideos,
    HistoryFilter.animation => l10n.tabGifs,
  };

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    child: Row(
      children: [
        if (leading != null)
          Padding(padding: const EdgeInsets.only(right: 6), child: leading),
        for (final f in _filters)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(labelOf(f, context.l10n)),
              selected: filter == f,
              onSelected: (_) => onChanged(f),
            ),
          ),
      ],
    ),
  );
}

/// Everything a search row needs about the channel a post came from.
typedef ChannelLook = ({String title, FileRef? photo});

/// The list of search results under the search bar: one row per post, newest first, the way
/// the official app lists what it found in a chat. In a feed the rows come from every source
/// at once, so each one names its channel.
class SearchResults extends StatelessWidget {
  const SearchResults({
    super.key,
    required this.results,
    required this.gateway,
    required this.look,
    required this.onOpen,
    required this.onLoadMore,
    this.query = '',
    this.kind = HistoryFilter.any,
    this.searched = false,
    this.loading = false,
    this.exhausted = false,
    this.total = -1,
    this.error,
    this.current = -1,
    this.recent = const [],
    this.onRecent,
    this.onClearRecent,
    this.onRemoveRecent,
  });

  final List<Post> results;
  final TelegramGateway gateway;

  /// Title and photo of a channel; the rows of a feed mix several.
  final ChannelLook Function(int chatId) look;
  final void Function(int index) onOpen;
  final VoidCallback onLoadMore;
  final String query;

  /// The kind of post that was looked for. Each kind is listed the way the official app
  /// lists it: pictures and videos as a grid, files, links and audio as their own rows.
  final HistoryFilter kind;

  /// A search has run, with words or without (a kind of post, a span of days).
  final bool searched;
  final bool loading;
  final bool exhausted;

  /// Telegram's count of the matches, -1 while it is unknown.
  final int total;
  final String? error;

  /// Result the timeline is showing, if any; it is marked in the list.
  final int current;

  /// The words searched for last, offered while nothing has been typed (H-28).
  final List<String> recent;
  final void Function(String query)? onRecent;
  final VoidCallback? onClearRecent;

  /// Takes one of the words searched for last out of the list.
  final void Function(String query)? onRemoveRecent;

  /// "Clear" empties the whole list, so it asks first, in the official app's words.
  Future<void> _askToClear(BuildContext context) async {
    final l10n = context.l10n;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.searchClearHistoryTitle),
        content: Text(l10n.searchClearHistoryBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.searchClearAll),
          ),
        ],
      ),
    );
    if (sure == true) onClearRecent?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Nothing typed yet: the words searched for last, as the official app offers them.
    if (results.isEmpty &&
        query.trim().isEmpty &&
        !searched &&
        recent.isNotEmpty &&
        onRecent != null) {
      return ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          ListTile(
            dense: true,
            title: Text(
              l10n.searchRecent,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            trailing: onClearRecent == null
                ? null
                : TextButton(
                    onPressed: () => _askToClear(context),
                    child: Text(l10n.commonClear),
                  ),
          ),
          for (final words in recent)
            ListTile(
              leading: const Icon(Icons.history),
              title: Text(words),
              onTap: () => onRecent!(words),
              trailing: onRemoveRecent == null
                  ? null
                  : IconButton(
                      tooltip: l10n.searchRemoveRecent,
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => onRemoveRecent!(words),
                    ),
            ),
        ],
      );
    }
    if (results.isEmpty) {
      if (error != null) {
        return ErrorState(
          what: l10n.searchFailed,
          message: error,
          onRetry: onLoadMore,
        );
      }
      if (loading) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          ),
        );
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            query.trim().isNotEmpty
                ? l10n.searchNothingFound(query)
                : searched
                ? l10n.searchNothingFoundPlain
                : l10n.searchTypeToSearch,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final found = exhausted || total < 0 ? results.length : total;
    if (kind != HistoryFilter.any) return _byKind(context, found);
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      // A head row that says how many there are, as the official app does.
      itemCount: results.length + 2,
      itemBuilder: (context, row) {
        if (row == 0) return _head(context, found);
        final i = row - 1;
        if (i == results.length) return _more(context);
        final post = results[i];
        final channel = look(post.chatId);
        return SearchResultTile(
          post: post,
          channelTitle: channel.title,
          channelPhoto: channel.photo,
          gateway: gateway,
          query: query,
          selected: i == current,
          onTap: () => onOpen(i),
        );
      },
    );
  }

  /// How many were found, over the results.
  Widget _head(BuildContext context, int found) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
    child: Text(
      context.l10n.searchPostsFound(found),
      style: Theme.of(context).textTheme.labelMedium
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );

  /// Under the results: the next page on its way, asked for when this is built.
  Widget _more(BuildContext context) {
    if (!exhausted && error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onLoadMore());
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: exhausted
            ? const SizedBox.shrink()
            : error != null
            ? ErrorState(
                what: context.l10n.searchMoreFailed,
                message: error,
                compact: true,
                onRetry: onLoadMore,
              )
            : const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
      ),
    );
  }

  /// The results of a kind of post in that kind's own layout, as the shared media tabs
  /// draw them. A tap does what the item does (opens the picture, the file, the link,
  /// plays the audio); a long press goes to the post.
  Widget _byKind(BuildContext context, int found) {
    if (kind == HistoryFilter.photoAndVideo) {
      return CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverToBoxAdapter(child: _head(context, found)),
          SliverPadding(
            padding: const EdgeInsets.all(2),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              itemCount: results.length,
              itemBuilder: (context, i) => GestureDetector(
                onLongPress: () => onOpen(i),
                child: MediaTile(
                  post: results[i],
                  gateway: gateway,
                  onTap: () => _openViewer(context, i),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(child: _more(context)),
        ],
      );
    }
    final theme = Theme.of(context);
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: results.length + 2,
      itemBuilder: (context, row) {
        if (row == 0) return _head(context, found);
        final i = row - 1;
        if (i == results.length) return _more(context);
        final post = results[i];
        final media = post.media;
        final title = look(post.chatId).title;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: () => onOpen(i),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Whose it is: the rows of several channels stand under one another.
              if (title.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: peerColor(post.chatId, theme.brightness),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (kind == HistoryFilter.url)
                LinkRow(post: post)
              else if (media is DocumentMedia)
                FileRow(post: post, media: media, gateway: gateway)
              else
                MediaRow(post: post, gateway: gateway),
              const Divider(height: 1),
            ],
          ),
        );
      },
    );
  }

  /// The picture or video at [index] in the viewer, which pages through everything that
  /// was found.
  void _openViewer(BuildContext context, int index) {
    final items = <Media>[];
    final details = <ViewerDetail>[];
    var initial = 0;
    for (var i = 0; i < results.length; i++) {
      final p = results[i];
      final media = p.media;
      if (media == null) continue;
      final shown = MediaViewerScreen.viewable([media]);
      if (i == index) initial = items.length;
      items.addAll(shown);
      details.addAll(
        List.filled(
          shown.length,
          ViewerDetail(
            channel: look(p.chatId).title,
            date: p.date,
            caption: p.text,
            entities: p.entities,
            postKey: '${p.chatId}:${p.messageId}',
            protected: !p.canBeSaved,
            // The post in its timeline, as a tap on a found row opens it.
            onShowInChat: () => onOpen(i),
          ),
        ),
      );
    }
    if (items.isEmpty) return;
    MediaViewerScreen.open(
      context,
      items: items,
      gateway: gateway,
      initialIndex: initial,
      details: details,
    );
  }
}

/// One found post: channel photo, coloured channel name, the matching text, the date.
class SearchResultTile extends StatelessWidget {
  const SearchResultTile({
    super.key,
    required this.post,
    required this.channelTitle,
    required this.channelPhoto,
    required this.gateway,
    required this.onTap,
    this.query = '',
    this.selected = false,
  });

  final Post post;
  final String channelTitle;
  final FileRef? channelPhoto;
  final TelegramGateway gateway;
  final VoidCallback onTap;
  final String query;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = DateTime.fromMillisecondsSinceEpoch(post.date * 1000);
    final text = post.text.trim().isEmpty
        ? mediaLabel(post.media, context.l10n.mediaWords)
        : post.text.replaceAll(RegExp(r'\s+'), ' ');
    return ListTile(
      onTap: onTap,
      selected: selected,
      leading: ChannelAvatar(
        photo: channelPhoto,
        title: channelTitle,
        gateway: gateway,
        radius: 20,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              channelTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                color: peerColor(post.chatId, theme.brightness),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            // As the official app's rows: a time, a weekday or a short date.
            formatListDate(date, context: context),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      subtitle: _Snippet(text: text, query: query),
    );
  }
}

/// Two lines of the post with every word of the search marked, starting at the first
/// place one of them stands.
class _Snippet extends StatelessWidget {
  const _Snippet({required this.text, required this.query});
  final String text;
  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = query.trim();
    if (q.isEmpty) {
      return Text(text, maxLines: 2, overflow: TextOverflow.ellipsis);
    }
    final all = foundRanges(text, q);
    if (all.isEmpty) {
      return Text(text, maxLines: 2, overflow: TextOverflow.ellipsis);
    }
    // Start a little before the first match, so it is on the first line of the row, and
    // not in the middle of a character that takes two code units.
    final first = all.first.$1;
    var start = first <= 24 ? 0 : first - 20;
    if (start > 0 && (text.codeUnitAt(start) & 0xFC00) == 0xDC00) start++;
    final shown = start == 0 ? text : '…${text.substring(start)}';
    final marked = TextStyle(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.w600,
    );
    final spans = <TextSpan>[];
    var i = 0;
    for (final (from, to) in foundRanges(shown, q)) {
      if (from > i) spans.add(TextSpan(text: shown.substring(i, from)));
      spans.add(TextSpan(text: shown.substring(from, to), style: marked));
      i = to;
    }
    if (i < shown.length) spans.add(TextSpan(text: shown.substring(i)));
    return Text.rich(
      TextSpan(children: spans),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Completes once the keyboard has left the screen. The lists are anchored at their lower
/// edge, so a jump made while the keyboard is still closing would leave the post lower by
/// the keyboard's height once it is gone.
Future<void> keyboardGone(BuildContext context) async {
  final view = View.of(context);
  for (var i = 0; i < 40 && view.viewInsets.bottom > 0; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

/// The bar the official app shows under a search that has run: which match the timeline
/// stands on, arrows to step to the older or the newer one, and "Show as list", which
/// puts the results in a list and, as "Show as chat", takes it away again.
class SearchStepper extends StatelessWidget {
  const SearchStepper({
    super.key,
    required this.current,
    required this.total,
    required this.onOlder,
    required this.onNewer,
    this.loading = false,
    this.listShown = false,
    this.onToggleList,
  });

  /// The results are shown as a list: the arrows have nothing to step through.
  final bool listShown;

  /// Switches between the list and the timeline; null while there is nothing to list.
  final VoidCallback? onToggleList;

  /// Zero-based position in the results (newest first).
  final int current;

  /// Telegram's count of matches, or the number found once the search is exhausted.
  final int total;
  final VoidCallback? onOlder;
  final VoidCallback? onNewer;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final shown = total < current + 1 ? current + 1 : total;
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 48,
          child: Row(
            children: [
              // The arrows keep their room in the list, so the bar's words do not move.
              Visibility.maintain(
                visible: !listShown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: l10n.searchOlderMatch,
                      onPressed: listShown ? null : onOlder,
                      icon: const Icon(Icons.keyboard_arrow_up),
                    ),
                    IconButton(
                      tooltip: l10n.searchNewerMatch,
                      onPressed: listShown ? null : onNewer,
                      icon: const Icon(Icons.keyboard_arrow_down),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: onToggleList == null || total <= 0
                    ? const SizedBox.shrink()
                    : Center(
                        child: TextButton(
                          onPressed: onToggleList,
                          child: Text(
                            listShown
                                ? l10n.searchShowAsChat
                                : l10n.searchShowAsList,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
              ),
              if (loading)
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  total <= 0
                      ? (loading ? '' : l10n.searchNoMatches)
                      // The list says itself how many it holds.
                      : listShown || current < 0
                      ? ''
                      : l10n.searchMatchOf(current + 1, shown),
                  style: theme.textTheme.labelLarge,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Runs a [FeedSearch] for one query and keeps what it found; the screen only reads it.
/// A new query gets a new session, so answers of the old one are dropped with it.
/// Paging state of a search over the posts of every channel the account follows (H-25).
/// Telegram searches all chats at once and pages with a token of its own.
final class GlobalSearchSession {
  GlobalSearchSession({
    required this.gateway,
    required this.query,
    this.filter = HistoryFilter.any,
    this.minDate = 0,
    this.maxDate = 0,
    List<int> chatIds = const [],
  }) : _byChannel =
           query.trim().isEmpty &&
               filter == HistoryFilter.any &&
               (minDate > 0 || maxDate > 0)
           ? FeedSearch(gateway, chatIds, minDate: minDate, maxDate: maxDate)
           : null;
  final TelegramGateway gateway;
  final String query;
  final HistoryFilter filter;

  /// The span of days searched, in unix seconds; 0 for an open end.
  final int minDate;
  final int maxDate;

  /// A span of days with neither words nor a kind of post: Telegram's search over all
  /// chats answers nothing to that, so the channels are read one by one and merged.
  final FeedSearch? _byChannel;

  final _found = <Post>[];
  List<Post> get results => _byChannel?.results ?? _found;
  String _offset = '';
  bool exhausted = false;
  bool loading = false;
  String? error;
  int _total = 0;

  /// Telegram's estimate while more can come, the exact number once it cannot; -1 where
  /// it gives none.
  int get total => exhausted
      ? results.length
      : _byChannel != null
      ? -1
      : _total;

  /// Loads the next page. True when the screen should rebuild.
  Future<bool> loadMore() async {
    if (loading || exhausted) return false;
    loading = true;
    try {
      final byChannel = _byChannel;
      if (byChannel != null) {
        await byChannel.loadMore();
        error = null;
        exhausted = byChannel.exhausted;
        return true;
      }
      final page = await gateway.searchAllChannels(
        query: query,
        filter: filter,
        offset: _offset,
        minDate: minDate,
        maxDate: maxDate,
      );
      error = null;
      _found.addAll(page.posts);
      if (page.totalCount >= 0) _total = page.totalCount;
      _offset = page.nextOffset;
      if (page.nextOffset.isEmpty) exhausted = true;
      return true;
    } on TelegramException catch (e) {
      error = e.message;
      return true;
    } finally {
      loading = false;
    }
  }
}

final class SearchSession {
  SearchSession({
    required this.gateway,
    required this.chatIds,
    required this.query,
    this.filter = HistoryFilter.any,
    FeedFilter feedFilter = FeedFilter.none,
  }) : _search = FeedSearch(
         gateway,
         chatIds,
         query: query,
         filter: filter,
         feedFilter: feedFilter,
       );

  final TelegramGateway gateway;
  final List<int> chatIds;
  final String query;
  final HistoryFilter filter;
  final FeedSearch _search;

  List<Post> get results => _search.results;
  bool get exhausted => _search.exhausted;

  /// Telegram's approximate count while more can be loaded, the exact one afterwards.
  int get total =>
      _search.exhausted ? _search.results.length : _search.totalCount;
  bool loading = false;
  String? error;

  /// Loads the next page. True when the screen should rebuild.
  Future<bool> loadMore() async {
    if (loading || _search.exhausted) return false;
    loading = true;
    try {
      final added = await _search.loadMore();
      error = null;
      return added.isNotEmpty || _search.exhausted;
    } on TelegramException catch (e) {
      error = e.message;
      return true;
    } finally {
      loading = false;
    }
  }

  /// Loads until the result at [index] exists or the search runs out.
  Future<bool> ensure(int index) async {
    while (results.length <= index && !exhausted && error == null) {
      await loadMore();
    }
    return index >= 0 && index < results.length;
  }

  void removePosts(int chatId, List<int> messageIds) =>
      _search.removePosts(chatId, messageIds);
}
