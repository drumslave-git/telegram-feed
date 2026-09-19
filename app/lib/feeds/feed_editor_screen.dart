import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../home/channel_list.dart' show ChannelAvatar;

/// Edit a feed's sources: add joined channels from a searchable picker, remove, reorder.
/// Only channels the account has joined can be added (SPEC section 7); the app never joins.
class FeedEditorScreen extends StatefulWidget {
  const FeedEditorScreen({
    super.key,
    required this.db,
    required this.gateway,
    required this.feedId,
  });
  final AppDatabase db;
  final TelegramGateway gateway;
  final int feedId;

  @override
  State<FeedEditorScreen> createState() => _FeedEditorScreenState();
}

class _FeedEditorScreenState extends State<FeedEditorScreen> {
  late final Future<List<Channel>> _channels = widget.gateway.myChannels();

  Future<void> _pick(List<WatchedChannel> current) async {
    final channels = await _channels;
    if (!mounted) return;
    final taken = current.map((c) => c.chatId).toSet();
    final picked = await showModalBottomSheet<Channel>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ChannelPicker(
        channels: channels.where((c) => !taken.contains(c.chatId)).toList(),
        gateway: widget.gateway,
      ),
    );
    if (picked != null) {
      await widget.db.addSource(
        widget.feedId,
        picked.chatId,
        title: picked.title,
        username: picked.username,
      );
      // The feed starts where Telegram's own read position is, so the channel's backlog
      // does not count as unread here (ARCHITECTURE 5.4).
      if (picked.lastReadMessageId > 0) {
        await widget.db.markRead(
          widget.feedId,
          picked.chatId,
          picked.lastReadMessageId,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<WatchedChannel>>(
      stream: widget.db.watchSourceChannels(widget.feedId),
      builder: (context, sourcesSnap) {
        final sources = sourcesSnap.data ?? const <WatchedChannel>[];
        return Scaffold(
          appBar: AppBar(
            title: FutureBuilder<FeedWithSources?>(
              future: widget.db.feedWithSources(widget.feedId),
              builder: (context, s) =>
                  Text(s.data == null ? 'Feed' : 'Edit ${s.data!.feed.name}'),
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _pick(sources),
            icon: const Icon(Icons.add),
            label: const Text('Add channel'),
          ),
          body: FutureBuilder<List<Channel>>(
            future: _channels,
            builder: (context, chSnap) {
              final left = {
                for (final c in chSnap.data ?? const <Channel>[])
                  if (!c.isMember) c.chatId,
              };
              final photos = {
                for (final c in chSnap.data ?? const <Channel>[])
                  c.chatId: c.photo,
              };
              if (sources.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No channels yet. Add channels your Telegram account has joined.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              return ReorderableListView.builder(
                padding: const EdgeInsets.only(bottom: 88),
                header: FeedFilterTile(db: widget.db, feedId: widget.feedId),
                itemCount: sources.length,
                onReorderItem: (from, to) {
                  final ids = sources.map((s) => s.chatId).toList();
                  final id = ids.removeAt(from);
                  ids.insert(to, id);
                  widget.db.reorderSources(widget.feedId, ids);
                },
                itemBuilder: (context, i) {
                  final s = sources[i];
                  final hasLeft = left.contains(s.chatId);
                  return ListTile(
                    key: ValueKey(s.chatId),
                    leading: ChannelAvatar(
                      photo: photos[s.chatId],
                      title: s.title,
                      gateway: widget.gateway,
                      radius: 20,
                    ),
                    title: Text(s.title),
                    subtitle: hasLeft
                        ? const Text('Left in Telegram; history stays readable')
                        : (s.username == null ? null : Text('@${s.username}')),
                    trailing: IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () =>
                          widget.db.removeSource(widget.feedId, s.chatId),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

/// "Show" row of the feed editor: what the feed's filter lets through, and the sheet that
/// edits it.
class FeedFilterTile extends StatelessWidget {
  const FeedFilterTile({super.key, required this.db, required this.feedId});
  final AppDatabase db;
  final int feedId;

  @override
  Widget build(BuildContext context) => StreamBuilder<Feed?>(
    stream: db.watchFeed(feedId),
    builder: (context, snap) {
      final filter = FeedFilter.decode(snap.data?.filterJson);
      return Column(
        children: [
          ListTile(
            leading: const Icon(Icons.filter_list),
            title: const Text('Show'),
            subtitle: Text(filter.describe()),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final edited = await showModalBottomSheet<FeedFilter>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                showDragHandle: true,
                builder: (_) => FeedFilterSheet(initial: filter),
              );
              if (edited != null && edited != filter) {
                await db.setFeedFilter(feedId, edited.encode());
              }
            },
          ),
          const Divider(height: 1),
        ],
      );
    },
  );
}

/// Edits a [FeedFilter]; pops with the result on "Apply".
class FeedFilterSheet extends StatefulWidget {
  const FeedFilterSheet({super.key, required this.initial});
  final FeedFilter initial;

  @override
  State<FeedFilterSheet> createState() => _FeedFilterSheetState();
}

class _FeedFilterSheetState extends State<FeedFilterSheet> {
  late FeedFilter _f = widget.initial;

  static const _kindLabels = {
    MediaKind.photo: 'Photos',
    MediaKind.video: 'Videos',
    MediaKind.gif: 'GIFs',
    MediaKind.audio: 'Audio',
    MediaKind.voice: 'Voice messages',
    MediaKind.document: 'Files',
    MediaKind.other: 'Other (polls, stickers, ...)',
  };
  static const _videoLengths = [0, 30, 60, 120, 300, 600, 1800];
  static const _textLengths = [0, 50, 100, 280, 500, 1000];

  static String _duration(int s) => s == 0
      ? 'Any length'
      : s < 60
      ? 'From $s s'
      : 'From ${s ~/ 60} min';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaPossible = _f.media != MediaPresence.textOnly;
    final textPossible = _f.media != MediaPresence.withMedia;
    final videoPossible =
        mediaPossible &&
        (_f.kinds.isEmpty || _f.kinds.contains(MediaKind.video));
    Widget label(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(text, style: theme.textTheme.titleSmall),
    );
    return ListView(
      shrinkWrap: true,
      children: [
        label('Posts'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<MediaPresence>(
            segments: const [
              ButtonSegment(value: MediaPresence.any, label: Text('All')),
              ButtonSegment(
                value: MediaPresence.withMedia,
                label: Text('With media'),
              ),
              ButtonSegment(
                value: MediaPresence.textOnly,
                label: Text('Text only'),
              ),
            ],
            selected: {_f.media},
            onSelectionChanged: (s) =>
                setState(() => _f = _f.copyWith(media: s.first)),
          ),
        ),
        label('Media types (none selected = all)'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            children: [
              for (final kind in MediaKind.values)
                FilterChip(
                  label: Text(_kindLabels[kind]!),
                  selected: _f.kinds.contains(kind),
                  onSelected: !mediaPossible
                      ? null
                      : (on) => setState(
                          () => _f = _f.copyWith(
                            kinds: on
                                ? {..._f.kinds, kind}
                                : ({..._f.kinds}..remove(kind)),
                          ),
                        ),
                ),
            ],
          ),
        ),
        ListTile(
          enabled: videoPossible,
          title: const Text('Video length'),
          trailing: DropdownButton<int>(
            value: _videoLengths.contains(_f.minVideoSeconds)
                ? _f.minVideoSeconds
                : 0,
            onChanged: !videoPossible
                ? null
                : (v) =>
                      setState(() => _f = _f.copyWith(minVideoSeconds: v ?? 0)),
            items: [
              for (final s in _videoLengths)
                DropdownMenuItem(value: s, child: Text(_duration(s))),
            ],
          ),
        ),
        ListTile(
          enabled: textPossible,
          title: const Text('Text posts'),
          trailing: DropdownButton<int>(
            value: _textLengths.contains(_f.minTextLength)
                ? _f.minTextLength
                : 0,
            onChanged: !textPossible
                ? null
                : (v) =>
                      setState(() => _f = _f.copyWith(minTextLength: v ?? 0)),
            items: [
              for (final n in _textLengths)
                DropdownMenuItem(
                  value: n,
                  child: Text(n == 0 ? 'Any length' : 'From $n characters'),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            'Posts this feed hides count as read, and rules stay quiet about them unless '
            'another feed with the same channel shows them.',
            style: theme.textTheme.bodySmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            children: [
              TextButton(
                onPressed: () => setState(() => _f = FeedFilter.none),
                child: const Text('Show everything'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.pop(context, _f),
                child: const Text('Apply'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Searchable list of joined channels; pops with the chosen [Channel].
class ChannelPicker extends StatefulWidget {
  const ChannelPicker({super.key, required this.channels, this.gateway});
  final List<Channel> channels;

  /// Downloads the channel photos; without it the rows show no picture.
  final TelegramGateway? gateway;

  @override
  State<ChannelPicker> createState() => _ChannelPickerState();
}

class _ChannelPickerState extends State<ChannelPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final shown = widget.channels
        .where(
          (c) =>
              q.isEmpty ||
              c.title.toLowerCase().contains(q) ||
              (c.username?.toLowerCase().contains(q) ?? false),
        )
        .toList();
    // The sheet ends above the keyboard, otherwise the last channels hide behind it.
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: _sheet(shown),
    );
  }

  Widget _sheet(List<Channel> shown) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      builder: (context, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search joined channels',
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: shown.isEmpty
                ? Center(
                    child: Text(
                      widget.channels.isEmpty
                          ? 'All joined channels are already in this feed.'
                          : 'No channel matches "$_query".',
                    ),
                  )
                : ListView.builder(
                    controller: scroll,
                    itemCount: shown.length,
                    itemBuilder: (context, i) {
                      final c = shown[i];
                      final gateway = widget.gateway;
                      return ListTile(
                        leading: gateway == null
                            ? null
                            : ChannelAvatar(
                                photo: c.photo,
                                title: c.title,
                                gateway: gateway,
                                radius: 20,
                              ),
                        title: Text(c.title),
                        subtitle: c.username == null
                            ? null
                            : Text('@${c.username}'),
                        trailing: c.memberCount > 0
                            ? Text('${c.memberCount}')
                            : null,
                        onTap: () => Navigator.pop(context, c),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
