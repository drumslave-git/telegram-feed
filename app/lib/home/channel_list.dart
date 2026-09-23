import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../feeds/media_view.dart' show Downloaded;
import '../feeds/post_card.dart' show formatTime, peerColor;
import '../widgets/error_state.dart';
import '../widgets/skeleton_list.dart';
import 'unread_badge.dart';

/// Channels as the official app lists chats: photo, title, newest post, time, unread count.
/// Used by the folder tabs and, with a search box, by "All channels".
class ChannelList extends StatefulWidget {
  const ChannelList({
    super.key,
    required this.channels,
    required this.gateway,
    required this.onOpen,
    this.onMenu,
    this.header,
    this.searchable = false,
    this.onRefresh,
    this.emptyText = 'No channels here.',
    this.feedsByChat = const {},
    this.loading = false,
    this.error,
  });
  final List<Channel> channels;
  final TelegramGateway gateway;
  final void Function(Channel channel) onOpen;

  /// Long press on a row: the menu of H-15, at the point the finger was on.
  final void Function(Channel channel, Offset at)? onMenu;

  /// A row above the channels, which the list scrolls with them (the Archive of H-30).
  final Widget? header;
  final bool searchable;
  final Future<void> Function()? onRefresh;
  final String emptyText;

  /// True while the channels are still coming: a spinner instead of [emptyText].
  final bool loading;

  /// A failed reload while channels are shown: a banner with Retry above them.
  final String? error;

  /// Names of the feeds each channel belongs to, by chat id ([AppDatabase.feedNamesByChat]).
  final Map<int, List<String>> feedsByChat;

  @override
  State<ChannelList> createState() => _ChannelListState();
}

class _ChannelListState extends State<ChannelList>
    with AutomaticKeepAliveClientMixin {
  String _query = '';

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final q = _query.trim().toLowerCase();
    final shown = [
      for (final c in widget.channels)
        if (q.isEmpty ||
            c.title.toLowerCase().contains(q) ||
            (c.username?.toLowerCase().contains(q) ?? false))
          c,
    ];
    if (widget.loading && widget.channels.isEmpty) {
      return const SkeletonList();
    }
    // Nothing to show and a failed load: the whole tab says so and offers the retry,
    // instead of hiding the code in the "no channels" line.
    if (widget.channels.isEmpty && widget.error != null) {
      return ErrorState(
        what: 'Could not load the channels.',
        message: widget.error,
        onRetry: widget.onRefresh == null
            ? null
            : () => unawaited(widget.onRefresh!()),
      );
    }
    Widget list = shown.isEmpty
        ? ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  q.isEmpty
                      ? widget.emptyText
                      : 'No channel matches "$_query".',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          )
        : ListView.builder(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            itemCount: shown.length + (widget.header == null ? 0 : 1),
            itemBuilder: (context, row) {
              if (widget.header != null && row == 0) return widget.header!;
              final i = widget.header == null ? row : row - 1;
              return ChannelTile(
                key: ValueKey(shown[i].chatId),
                channel: shown[i],
                gateway: widget.gateway,
                feeds: widget.feedsByChat[shown[i].chatId] ?? const [],
                onTap: () => widget.onOpen(shown[i]),
                onMenu: widget.onMenu == null
                    ? null
                    : (at) => widget.onMenu!(shown[i], at),
              );
            },
          );
    if (widget.onRefresh != null) {
      list = RefreshIndicator(onRefresh: widget.onRefresh!, child: list);
    }
    final error = widget.error;
    final banner = error == null
        ? null
        : MaterialBanner(
            content: Text(
              telegramErrorLine(error, what: 'Could not refresh the channels.'),
            ),
            actions: [
              TextButton(
                onPressed: widget.onRefresh == null
                    ? null
                    : () => unawaited(widget.onRefresh!()),
                child: const Text('Retry'),
              ),
            ],
          );
    if (!widget.searchable) {
      return banner == null
          ? list
          : Column(
              children: [
                banner,
                Expanded(child: list),
              ],
            );
    }
    return Column(
      children: [
        ?banner,
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search channels',
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(child: list),
      ],
    );
  }
}

class ChannelTile extends StatelessWidget {
  const ChannelTile({
    super.key,
    required this.channel,
    required this.gateway,
    required this.onTap,
    this.onMenu,
    this.feeds = const [],
  });
  final Channel channel;
  final TelegramGateway gateway;
  final VoidCallback onTap;

  /// Long press: the row's menu, at the point the finger was on.
  final void Function(Offset at)? onMenu;

  /// Names of the feeds this channel is in; shown as tags under the newest post.
  final List<String> feeds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = channel;
    final tile = ListTile(
      onTap: onTap,
      // Always two lines: the preview line stays even when there is nothing to preview,
      // and the feed tags share it, so rows keep one height as channels join feeds.
      leading: ChannelAvatar(
        photo: c.photo,
        title: c.title,
        colorId: c.chatId,
        gateway: gateway,
      ),
      title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              c.lastMessageText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (feeds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: FeedTags(names: feeds),
            ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (c.lastMessageDate > 0)
            Text(
              formatListDate(
                DateTime.fromMillisecondsSinceEpoch(c.lastMessageDate * 1000),
                context: context,
              ),
              style: theme.textTheme.labelSmall,
            ),
          if (c.unreadCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: UnreadBadge(c.unreadCount),
            ),
        ],
      ),
    );
    if (onMenu == null) return tile;
    // The menu opens under the finger, which a ListTile's own long press cannot report.
    return GestureDetector(
      onLongPressStart: (d) => onMenu!(d.globalPosition),
      child: tile,
    );
  }
}

/// The feeds a channel belongs to, as small chips. Channel lists carry them so that it is
/// visible at a glance what a channel is already read in.
class FeedTags extends StatelessWidget {
  const FeedTags({super.key, required this.names, this.max = 2});
  final List<String> names;

  /// Tags drawn before the rest becomes "+N".
  final int max;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = names.length > max ? names.take(max - 1).toList() : names;
    final rest = names.length - shown.length;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final n in [...shown, if (rest > 0) '+$rest'])
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: const BorderRadius.all(Radius.circular(6)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              child: Text(
                n,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Round photo of a channel or user; initials on a tinted disc until (or without) a photo.
class ChannelAvatar extends StatelessWidget {
  const ChannelAvatar({
    super.key,
    required this.photo,
    required this.title,
    required this.gateway,
    this.colorId,
    this.radius = 22,
  });
  final FileRef? photo;
  final String title;
  final TelegramGateway gateway;

  /// Chat id the disc takes its colour from, as the official app colours its avatars.
  /// Without one every disc is the theme's own tint.
  final int? colorId;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Up to two initials, as the official app draws them.
    final words = title.trim().split(RegExp(r'\s+'))
      ..removeWhere((w) => w.isEmpty);
    final letters = words.isEmpty
        ? '?'
        : words.length == 1
        ? words.first.characters.first.toUpperCase()
        : (words.first.characters.first + words[1].characters.first)
              .toUpperCase();
    final tint = colorId == null
        ? scheme.secondaryContainer
        : peerColor(colorId!, theme.brightness).withValues(alpha: 0.25);
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: tint,
      foregroundColor: colorId == null
          ? scheme.onSecondaryContainer
          : peerColor(colorId!, theme.brightness),
      child: Text(letters, style: TextStyle(fontSize: radius * 0.7)),
    );
    final file = photo;
    if (file == null) return fallback;
    return SizedBox.square(
      dimension: radius * 2,
      child: Downloaded(
        key: ValueKey(file.id),
        file: file,
        gateway: gateway,
        placeholder: fallback,
        builder: (context, path) => CircleAvatar(
          radius: radius,
          backgroundImage: FileImage(File(path)),
        ),
      ),
    );
  }
}

/// Time today, weekday within a week, else the date, as the official app's chat list
/// writes them. With a [context] the clock and the date follow the phone's own settings.
String formatListDate(DateTime d, {DateTime? now, BuildContext? context}) {
  final n = now ?? DateTime.now();
  String two(int x) => x.toString().padLeft(2, '0');
  if (d.year == n.year && d.month == n.month && d.day == n.day) {
    return formatTime(d, context);
  }
  if (n.difference(d).inDays < 6 && !d.isAfter(n)) {
    return const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday -
        1];
  }
  final l10n = context == null
      ? null
      : Localizations.of<MaterialLocalizations>(context, MaterialLocalizations);
  return l10n?.formatShortDate(d) ?? '${d.year}-${two(d.month)}-${two(d.day)}';
}
