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
    this.searchable = false,
    this.onRefresh,
    this.emptyText = 'No channels here.',
  });
  final List<Channel> channels;
  final TelegramGateway gateway;
  final void Function(Channel channel) onOpen;
  final bool searchable;
  final Future<void> Function()? onRefresh;
  final String emptyText;

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
            itemCount: shown.length,
            itemBuilder: (context, i) => ChannelTile(
              key: ValueKey(shown[i].chatId),
              channel: shown[i],
              gateway: widget.gateway,
              onTap: () => widget.onOpen(shown[i]),
            ),
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
  });
  final Channel channel;
  final TelegramGateway gateway;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = channel;
    return ListTile(
      onTap: onTap,
      leading: ChannelAvatar(photo: c.photo, title: c.title, gateway: gateway),
      title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: c.lastMessageText.isEmpty
          ? null
          : Text(
              c.lastMessageText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
