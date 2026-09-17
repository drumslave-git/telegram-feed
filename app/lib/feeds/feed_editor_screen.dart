import 'package:app_db/app_db.dart';
import 'package:flutter/material.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

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
      builder: (_) => ChannelPicker(
        channels: channels.where((c) => !taken.contains(c.chatId)).toList(),
      ),
    );
    if (picked != null) {
      await widget.db.addSource(
        widget.feedId,
        picked.chatId,
        title: picked.title,
        username: picked.username,
      );
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
                    leading: const Icon(Icons.campaign_outlined),
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

/// Searchable list of joined channels; pops with the chosen [Channel].
class ChannelPicker extends StatefulWidget {
  const ChannelPicker({super.key, required this.channels});
  final List<Channel> channels;

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
                      return ListTile(
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
