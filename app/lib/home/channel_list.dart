import 'dart:io';

import 'package:flutter/material.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../feeds/media_view.dart' show Downloaded;

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
    if (!widget.searchable) return list;
    return Column(
      children: [
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
    final preview = c.lastMessageText.isEmpty
        ? null
        : Text(c.lastMessageText, maxLines: 1, overflow: TextOverflow.ellipsis);
    return ListTile(
      onTap: onTap,
      onLongPress: onMenu == null
          ? null
          : () {
              // The menu opens where the row is, since a ListTile reports no position.
              final box = context.findRenderObject()! as RenderBox;
              onMenu!(box.localToGlobal(box.size.center(Offset.zero)));
            },
      isThreeLine: preview != null && feeds.isNotEmpty,
      leading: ChannelAvatar(photo: c.photo, title: c.title, gateway: gateway),
      title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: preview == null && feeds.isEmpty
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ?preview,
                if (feeds.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
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
              ),
              style: theme.textTheme.labelSmall,
            ),
          if (c.unreadCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Badge(
                label: Text(c.unreadCount > 999 ? '999+' : '${c.unreadCount}'),
                backgroundColor: theme.colorScheme.primary,
                textColor: theme.colorScheme.onPrimary,
              ),
            ),
        ],
      ),
    );
  }
}

/// The feeds a channel belongs to, as small chips. Channel lists carry them so that it is
/// visible at a glance what a channel is already read in.
class FeedTags extends StatelessWidget {
  const FeedTags({super.key, required this.names});
  final List<String> names;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final n in names)
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
    this.radius = 22,
  });
  final FileRef? photo;
  final String title;
  final TelegramGateway gateway;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final letters = title.trim().isEmpty
        ? '?'
        : title.trim().characters.first.toUpperCase();
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: scheme.secondaryContainer,
      foregroundColor: scheme.onSecondaryContainer,
      child: Text(letters, style: TextStyle(fontSize: radius * 0.8)),
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

/// Time today, weekday within a week, else the date.
String formatListDate(DateTime d, {DateTime? now}) {
  final n = now ?? DateTime.now();
  String two(int x) => x.toString().padLeft(2, '0');
  if (d.year == n.year && d.month == n.month && d.day == n.day) {
    return '${two(d.hour)}:${two(d.minute)}';
  }
  if (n.difference(d).inDays < 6 && !d.isAfter(n)) {
    return const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday -
        1];
  }
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}
