import 'dart:async';

import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../home/channel_list.dart' show ChannelAvatar, FeedTags;
import '../rules/rules_screen.dart' show RuleList, openRuleEditor;
import '../widgets/destructive_button.dart';
import 'shared_media.dart';

/// The feed's own info screen: its channels (add from a searchable picker, remove,
/// reorder), its rules, and, in the tabs beside them, the shared media of all its channels
/// at once, filtered like the feed. Only channels the account has joined can be added; the
/// app never joins.
class FeedEditorScreen extends StatefulWidget {
  const FeedEditorScreen({
    super.key,
    required this.db,
    required this.gateway,
    required this.feedId,
    this.initialTab = channelsTab,
  });
  final AppDatabase db;
  final TelegramGateway gateway;
  final int feedId;

  /// The tab the screen opens on.
  final int initialTab;

  static const channelsTab = 0;
  static const rulesTab = 1;

  @override
  State<FeedEditorScreen> createState() => _FeedEditorScreenState();
}

class _FeedEditorScreenState extends State<FeedEditorScreen>
    with SingleTickerProviderStateMixin {
  late final Future<List<Channel>> _channels = widget.gateway.myChannels();

  // Kept, not rebuilt: a fresh query stream on every build would make the screen
  // resubscribe (and drift re-query) with every tab animation frame.
  late final Stream<List<WatchedChannel>> _sourcesStream = widget.db
      .watchSourceChannels(widget.feedId);
  late final Stream<Feed?> _feedStream = widget.db.watchFeed(widget.feedId);

  /// Channels, rules, then the media tabs.
  late final TabController _tab = TabController(
    length: SharedMediaTabs.kinds.length + 2,
    initialIndex: widget.initialTab,
    vsync: this,
  )..addListener(() => setState(() {}));

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _pick(List<WatchedChannel> current) async {
    final channels = await _channels;
    final tags = await widget.db.feedNamesByChat();
    final hide =
        await widget.db.setting(SettingKeys.pickerHidesChannelsInFeeds) ==
        'true';
    if (!mounted) return;
    final taken = current.map((c) => c.chatId).toSet();
    final picked = await showModalBottomSheet<List<Channel>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ChannelPicker(
        channels: channels.where((c) => !taken.contains(c.chatId)).toList(),
        gateway: widget.gateway,
        feedsByChat: tags,
        hideInFeeds: hide,
        onHideInFeedsChanged: (v) =>
            widget.db.setSetting(SettingKeys.pickerHidesChannelsInFeeds, '$v'),
      ),
    );
    for (final channel in picked ?? const <Channel>[]) {
      await widget.db.addSource(
        widget.feedId,
        channel.chatId,
        title: channel.title,
        username: channel.username,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<WatchedChannel>>(
      stream: _sourcesStream,
      builder: (context, sourcesSnap) {
        final sources = sourcesSnap.data ?? const <WatchedChannel>[];
        final chatIds = [for (final s in sources) s.chatId];
        return Scaffold(
          appBar: AppBar(
            title: FutureBuilder<FeedWithSources?>(
              future: widget.db.feedWithSources(widget.feedId),
              builder: (context, s) =>
                  Text(s.data == null ? 'Feed' : 'Edit ${s.data!.feed.name}'),
            ),
            bottom: TabBar(
              controller: _tab,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                const Tab(text: 'Channels'),
                const Tab(text: 'Rules'),
                for (final (label, _) in SharedMediaTabs.kinds)
                  Tab(text: label),
              ],
            ),
          ),
          // Adding a channel belongs to the list of channels, a new rule to the rules.
          floatingActionButton: switch (_tab.index) {
            FeedEditorScreen.channelsTab => FloatingActionButton.extended(
              onPressed: () => _pick(sources),
              icon: const Icon(Icons.add),
              label: const Text('Add channel'),
            ),
            FeedEditorScreen.rulesTab => FloatingActionButton.extended(
              onPressed: () => openRuleEditor(
                context,
                db: widget.db,
                gateway: widget.gateway,
                feedId: widget.feedId,
              ),
              icon: const Icon(Icons.add),
              label: const Text('New rule'),
            ),
            _ => null,
          },
          body: TabBarView(
            controller: _tab,
            children: [
              _channelsTab(sources),
              RuleList(
                db: widget.db,
                gateway: widget.gateway,
                feedId: widget.feedId,
              ),
              for (final (label, kind) in SharedMediaTabs.kinds)
                if (chatIds.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'No channels yet.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else
                  StreamBuilder<Feed?>(
                    stream: _feedStream,
                    builder: (context, feedSnap) {
                      // The feed shows the same here as in its timeline; an edited filter
                      // (or another channel) starts the tab's search over.
                      final filter = FeedFilter.decode(
                        feedSnap.data?.filterJson,
                      );
                      return SharedMediaTab(
                        key: ValueKey(
                          '$label:${chatIds.join(",")}:${filter.encode()}',
                        ),
                        gateway: widget.gateway,
                        chatIds: chatIds,
                        kind: kind,
                        filter: filter,
                      );
                    },
                  ),
            ],
          ),
        );
      },
    );
  }

  /// Takes a channel out of the feed. Rules that watch only that channel go with it, so
  /// the user is asked first when there are any; otherwise an Undo puts it back in place.
  Future<void> _removeSource(WatchedChannel s, List<int> order) async {
    final messenger = ScaffoldMessenger.of(context);
    final rules = [
      for (final r in await widget.db.allRules())
        if (r.feedId == widget.feedId && r.scopeChatId == s.chatId) r,
    ];
    if (!mounted) return;
    if (rules.isNotEmpty) {
      final names = rules.map((r) => '"${r.name}"').join(', ');
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Remove ${s.title}?'),
          content: Text(
            rules.length == 1
                ? 'The rule $names watches only this channel and is deleted with it.'
                : 'The rules $names watch only this channel and are deleted with it.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            DestructiveButton(
              onPressed: () => Navigator.pop(context, true),
              label: 'Remove',
            ),
          ],
        ),
      );
      if (ok != true) return;
      await widget.db.removeSource(widget.feedId, s.chatId);
      return;
    }
    await widget.db.removeSource(widget.feedId, s.chatId);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('${s.title} removed'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => unawaited(() async {
              await widget.db.addSource(
                widget.feedId,
                s.chatId,
                title: s.title,
                username: s.username,
              );
              await widget.db.reorderSources(widget.feedId, order);
            }()),
          ),
        ),
      );
  }

  Widget _channelsTab(List<WatchedChannel> sources) {
    return FutureBuilder<List<Channel>>(
      future: _channels,
      builder: (context, chSnap) {
        final left = {
          for (final c in chSnap.data ?? const <Channel>[])
            if (!c.isMember) c.chatId,
        };
        final photos = {
          for (final c in chSnap.data ?? const <Channel>[]) c.chatId: c.photo,
        };
        if (sources.isEmpty) {
          // The filter is set before the channels as well as after.
          return Column(
            children: [
              FeedFilterTile(db: widget.db, feedId: widget.feedId),
              const Expanded(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No channels yet. Add channels your Telegram account has joined.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ],
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
                onPressed: () => unawaited(
                  _removeSource(s, [for (final x in sources) x.chatId]),
                ),
              ),
            );
          },
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
        CheckboxListTile(
          value: _f.wholePost,
          enabled: mediaPossible,
          onChanged: !mediaPossible
              ? null
              : (v) => setState(() => _f = _f.copyWith(wholePost: v ?? true)),
          title: const Text('Show the whole post'),
          subtitle: const Text(
            'A post with several pictures or videos is shown complete, with its caption, '
            'as soon as one of them passes. Off shows only the parts that pass.',
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
  const ChannelPicker({
    super.key,
    required this.channels,
    this.gateway,
    this.feedsByChat = const {},
    this.hideInFeeds = false,
    this.onHideInFeedsChanged,
  });
  final List<Channel> channels;

  /// Downloads the channel photos; without it the rows show no picture.
  final TelegramGateway? gateway;

  /// Names of the feeds each channel is already in ([AppDatabase.feedNamesByChat]).
  final Map<int, List<String>> feedsByChat;

  /// Whether the channels that are already in a feed are left out, as the reader last
  /// chose; [onHideInFeedsChanged] keeps a new choice.
  final bool hideInFeeds;
  final ValueChanged<bool>? onHideInFeedsChanged;

  @override
  State<ChannelPicker> createState() => _ChannelPickerState();
}

class _ChannelPickerState extends State<ChannelPicker> {
  String _query = '';

  /// The channels ticked off so far, by chat id: several go in at once (H-37).
  final _picked = <int>{};

  late bool _hideInFeeds = widget.hideInFeeds;

  List<String> _tagsOf(Channel c) => widget.feedsByChat[c.chatId] ?? const [];

  /// A channel ticked and then hidden is not added unseen.
  void _setHideInFeeds(bool hide) {
    setState(() {
      _hideInFeeds = hide;
      if (hide) {
        _picked.removeWhere(
          (id) => widget.feedsByChat[id]?.isNotEmpty ?? false,
        );
      }
    });
    widget.onHideInFeedsChanged?.call(hide);
  }

  void _toggle(Channel c) => setState(() {
    if (!_picked.remove(c.chatId)) _picked.add(c.chatId);
  });

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final shown = widget.channels
        .where(
          (c) =>
              !(_hideInFeeds && _tagsOf(c).isNotEmpty) &&
              (q.isEmpty ||
                  c.title.toLowerCase().contains(q) ||
                  (c.username?.toLowerCase().contains(q) ?? false)),
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
          if (widget.channels.any((c) => _tagsOf(c).isNotEmpty))
            CheckboxListTile(
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Hide channels already in a feed'),
              value: _hideInFeeds,
              onChanged: (v) => _setHideInFeeds(v ?? false),
            ),
          Expanded(
            child: shown.isEmpty
                ? Center(
                    child: Text(
                      widget.channels.isEmpty
                          ? 'All joined channels are already in this feed.'
                          : _query.trim().isEmpty
                          ? 'Every joined channel is already in a feed.'
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
                        isThreeLine:
                            c.username != null && _tagsOf(c).isNotEmpty,
                        subtitle: c.username == null && _tagsOf(c).isEmpty
                            ? null
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (c.username != null)
                                    Text('@${c.username}'),
                                  if (_tagsOf(c).isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: FeedTags(names: _tagsOf(c)),
                                    ),
                                ],
                              ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (c.memberCount > 0) Text('${c.memberCount}'),
                            Checkbox(
                              value: _picked.contains(c.chatId),
                              onChanged: (_) => _toggle(c),
                            ),
                          ],
                        ),
                        onTap: () => _toggle(c),
                      );
                    },
                  ),
          ),
          // What was ticked goes in together, as one button press.
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _picked.isEmpty
                          ? 'Tick the channels to add'
                          : '${_picked.length} channel${_picked.length == 1 ? '' : 's'} ticked',
                    ),
                  ),
                  FilledButton(
                    onPressed: _picked.isEmpty
                        ? null
                        : () => Navigator.pop(context, [
                            for (final c in widget.channels)
                              if (_picked.contains(c.chatId)) c,
                          ]),
                    child: const Text('Add'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
