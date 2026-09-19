import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../home/channel_list.dart' show ChannelAvatar, formatListDate;
import 'post_card.dart' show peerColor;

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
    this.loading = false,
    this.exhausted = false,
    this.error,
    this.current = -1,
  });

  final List<Post> results;
  final TelegramGateway gateway;

  /// Title and photo of a channel; the rows of a feed mix several.
  final ChannelLook Function(int chatId) look;
  final void Function(int index) onOpen;
  final VoidCallback onLoadMore;
  final String query;
  final bool loading;
  final bool exhausted;
  final String? error;

  /// Result the timeline is showing, if any; it is marked in the list.
  final int current;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            error != null
                ? 'Telegram: $error'
                : loading
                ? 'Searching…'
                : query.trim().isEmpty
                ? 'Type to search the posts.'
                : 'Nothing found for "$query".',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: results.length + 1,
      itemBuilder: (context, i) {
        if (i == results.length) {
          if (!exhausted && error == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) => onLoadMore());
          }
          final found = results.length;
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: exhausted
                  ? Text(
                      '$found result${found == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.labelMedium,
                    )
                  : error != null
                  ? Text('Telegram: $error')
                  : const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
            ),
          );
        }
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
        ? mediaLabel(post.media)
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
            formatListDate(date),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      subtitle: _Snippet(text: text, query: query),
    );
  }

  /// What a post without text is called in a list.
  static String mediaLabel(Media? m) => switch (m) {
    PhotoMedia() => 'Photo',
    VideoMedia(:final isAnimation) => isAnimation ? 'GIF' : 'Video',
    AudioMedia(:final isVoice) => isVoice ? 'Voice message' : 'Audio',
    DocumentMedia(:final fileName) => fileName,
    UnsupportedMedia() => 'Post',
    null => 'Post',
  };
}

/// Two lines of the post with the searched words marked, starting at the first match.
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
    final lower = text.toLowerCase();
    final needle = q.toLowerCase();
    final first = lower.indexOf(needle);
    // Start a little before the match, so it is on the first line of the row.
    final start = first <= 24 ? 0 : first - 20;
    final shown = start == 0 ? text : '…${text.substring(start)}';
    final hay = shown.toLowerCase();
    final spans = <TextSpan>[];
    var i = 0;
    while (true) {
      final at = hay.indexOf(needle, i);
      if (at < 0) {
        spans.add(TextSpan(text: shown.substring(i)));
        break;
      }
      if (at > i) spans.add(TextSpan(text: shown.substring(i, at)));
      spans.add(
        TextSpan(
          text: shown.substring(at, at + needle.length),
          style: TextStyle(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      i = at + needle.length;
    }
    return Text.rich(
      TextSpan(children: spans),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// The bar the official app shows once a result is open: which match the timeline stands on,
/// and arrows to step to the older or the newer one.
class SearchStepper extends StatelessWidget {
  const SearchStepper({
    super.key,
    required this.current,
    required this.total,
    required this.onOlder,
    required this.onNewer,
    this.loading = false,
  });

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
    final shown = total < current + 1 ? current + 1 : total;
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 48,
          child: Row(
            children: [
              IconButton(
                tooltip: 'Older match',
                onPressed: onOlder,
                icon: const Icon(Icons.keyboard_arrow_up),
              ),
              IconButton(
                tooltip: 'Newer match',
                onPressed: onNewer,
                icon: const Icon(Icons.keyboard_arrow_down),
              ),
              const Spacer(),
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
                  total <= 0 ? 'No matches' : '${current + 1} of $shown',
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
