import 'dart:async';

import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:rules/rules.dart' show RuleParser;
import 'package:telegram_gateway/telegram_gateway.dart';

import '../home/channel_list.dart' show ChannelAvatar, FeedTags;
import '../l10n/l10n.dart';
import 'post_card.dart' show formatCount;
import '../rules/condition_editor.dart';
import '../rules/rules_screen.dart' show RuleList, openRuleEditor;
import '../widgets/destructive_button.dart';
import '../widgets/empty_state.dart';
import 'shared_media.dart';
import 'timeline_screen.dart';

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

  /// Channels, rules, and the media of every channel of the feed.
  late final TabController _tab = TabController(
    length: 3,
    initialIndex: widget.initialTab,
    vsync: this,
  )..addListener(() => setState(() {}));

  /// Renames the feed from the screen that carries its name in the title.
  Future<void> _rename() async {
    final feed = await widget.db.feedById(widget.feedId);
    if (!mounted || feed == null) return;
    final ctl = TextEditingController(text: feed.name);
    final l10n = context.l10n;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.feedEditorRenameTitle),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.feedEditorNameLabel),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctl.text.trim()),
            child: Text(l10n.commonRename),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await widget.db.renameFeed(widget.feedId, name);
    }
  }

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
    final l10n = context.l10n;
    return StreamBuilder<List<WatchedChannel>>(
      stream: _sourcesStream,
      builder: (context, sourcesSnap) {
        final sources = sourcesSnap.data ?? const <WatchedChannel>[];
        final chatIds = [for (final s in sources) s.chatId];
        return Scaffold(
          appBar: AppBar(
            // The feed's own stream, not a future built here: the title neither flashes
            // "Feed" on every rebuild nor keeps the old name after a rename.
            title: StreamBuilder<Feed?>(
              stream: _feedStream,
              builder: (context, s) =>
                  Text(s.data?.name ?? l10n.feedEditorFallbackTitle),
            ),
            actions: [
              IconButton(
                tooltip: l10n.commonRename,
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => unawaited(_rename()),
              ),
            ],
            bottom: TabBar(
              controller: _tab,
              // Three tabs fit a phone; the five kinds of media live inside the last one,
              // where the official app keeps them too.
              tabs: [
                Tab(text: l10n.feedEditorTabChannels),
                Tab(text: l10n.commonRules),
                Tab(text: l10n.feedEditorTabSharedMedia),
              ],
            ),
          ),
          // Adding a channel belongs to the list of channels, a new rule to the rules.
          floatingActionButton: switch (_tab.index) {
            // While the feed is empty its own empty state carries the button, so the
            // same words do not appear twice on one screen.
            FeedEditorScreen.channelsTab when sources.isNotEmpty =>
              FloatingActionButton.extended(
                onPressed: () => _pick(sources),
                icon: const Icon(Icons.add),
                label: Text(l10n.feedEditorAddChannel),
              ),
            FeedEditorScreen.rulesTab => FloatingActionButton.extended(
              onPressed: () => openRuleEditor(
                context,
                db: widget.db,
                gateway: widget.gateway,
                feedId: widget.feedId,
              ),
              icon: const Icon(Icons.add),
              label: Text(l10n.feedEditorNewRule),
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
              StreamBuilder<Feed?>(
                stream: _feedStream,
                builder: (context, feedSnap) {
                  // The feed shows the same here as in its timeline; an edited filter
                  // (or another channel) starts the tabs over.
                  final filter = FeedFilter.decode(feedSnap.data?.filterJson);
                  return SharedMediaTabs(
                    key: ValueKey('${chatIds.join(",")}:${filter.encode()}'),
                    gateway: widget.gateway,
                    chatIds: chatIds,
                    filter: filter,
                    titles: {for (final s in sources) s.chatId: s.title},
                    onShowInChat: feedSnap.data == null
                        ? null
                        : (post) => unawaited(
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => TimelineScreen(
                                  db: widget.db,
                                  gateway: widget.gateway,
                                  feed: feedSnap.data,
                                  focusChatId: post.chatId,
                                  focusMessageId: post.messageId,
                                ),
                              ),
                            ),
                          ),
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
    final l10n = context.l10n;
    final rules = [
      for (final r in await widget.db.allRules())
        if (r.feedId == widget.feedId && r.scopeChatId == s.chatId) r,
    ];
    if (!mounted) return;
    if (rules.isNotEmpty) {
      final names = rules
          .map((r) => l10n.feedEditorQuotedRuleName(r.name))
          .join(', ');
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.feedEditorRemoveChannelTitle(s.title)),
          content: Text(
            rules.length == 1
                ? l10n.feedEditorRemoveChannelOneRule(names)
                : l10n.feedEditorRemoveChannelRules(names),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.commonCancel),
            ),
            DestructiveButton(
              onPressed: () => Navigator.pop(context, true),
              label: l10n.feedEditorRemoveChannel,
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
          content: Text(l10n.feedEditorChannelRemoved(s.title)),
          action: SnackBarAction(
            label: l10n.commonUndo,
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
        final l10n = context.l10n;
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
              Expanded(
                child: EmptyState(
                  icon: Icons.playlist_add,
                  title: l10n.feedEditorNoChannelsTitle,
                  message: l10n.feedEditorNoChannelsMessage,
                  actionLabel: l10n.feedEditorAddChannel,
                  onAction: () => unawaited(_pick(sources)),
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
                  ? Text(l10n.feedEditorChannelLeft)
                  : (s.username == null ? null : Text('@${s.username}')),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: l10n.feedEditorRemoveChannel,
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => unawaited(
                      _removeSource(s, [for (final x in sources) x.chatId]),
                    ),
                  ),
                  // Where to take hold, as on the feeds list: dragging a row by itself
                  // fights with the tap that opens it.
                  ReorderableDragStartListener(
                    index: i,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.drag_handle),
                    ),
                  ),
                ],
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
            title: Text(context.l10n.filterTileTitle),
            subtitle: Text(filter.describeIn(context.l10n)),
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

  /// The words the posts must match, edited as a rule's condition.
  late final _words = ConditionController(widget.initial.text);

  @override
  void dispose() {
    _words.dispose();
    super.dispose();
  }

  /// Closes with the filter, the words included; a condition that cannot be read keeps
  /// the sheet open and says why under the field.
  void _apply() {
    final words = _words.condition();
    if (words == null) return;
    Navigator.pop(
      context,
      _f.copyWith(text: ConditionController.isMatchAll(words) ? null : words),
    );
  }

  static const _videoLengths = [0, 30, 60, 120, 300, 600, 1800];
  static const _textLengths = [0, 50, 100, 280, 500, 1000];

  static String _duration(AppLocalizations l10n, int s) => s == 0
      ? l10n.filterVideoAnyLength
      : s < 60
      ? l10n.filterFromSeconds(s)
      : l10n.filterFromMinutes(s ~/ 60);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final mediaPossible = _f.media != MediaPresence.textOnly;
    final textPossible = _f.media != MediaPresence.withMedia;
    final videoPossible =
        mediaPossible &&
        (_f.kinds.isEmpty || _f.kinds.contains(MediaKind.video));
    Widget label(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(text, style: theme.textTheme.titleSmall),
    );
    // The sheet ends where the keyboard of the words' fields begins, so the field being
    // typed in scrolls into view above it. The buttons stay under the list, which scrolls.
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Text(
                    l10n.filterSheetTitle,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                label(l10n.filterPosts),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SegmentedButton<MediaPresence>(
                    segments: [
                      ButtonSegment(
                        value: MediaPresence.any,
                        label: Text(l10n.filterPostsAll),
                      ),
                      ButtonSegment(
                        value: MediaPresence.withMedia,
                        label: Text(l10n.filterPostsWithMedia),
                      ),
                      ButtonSegment(
                        value: MediaPresence.textOnly,
                        label: Text(l10n.filterPostsTextOnly),
                      ),
                    ],
                    selected: {_f.media},
                    onSelectionChanged: (s) =>
                        setState(() => _f = _f.copyWith(media: s.first)),
                  ),
                ),
                label(l10n.filterMediaTypes),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    l10n.filterMediaTypesNote,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final kind in MediaKind.values)
                        FilterChip(
                          label: Text(kind.chipLabelIn(l10n)),
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
                  title: Text(l10n.filterVideoLength),
                  trailing: DropdownMenu<int>(
                    enabled: videoPossible,
                    initialSelection: _videoLengths.contains(_f.minVideoSeconds)
                        ? _f.minVideoSeconds
                        : 0,
                    width: 180,
                    onSelected: (v) => setState(
                      () => _f = _f.copyWith(minVideoSeconds: v ?? 0),
                    ),
                    dropdownMenuEntries: [
                      for (final s in _videoLengths)
                        DropdownMenuEntry(value: s, label: _duration(l10n, s)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  enabled: textPossible,
                  title: Text(l10n.filterTextPosts),
                  trailing: DropdownMenu<int>(
                    enabled: textPossible,
                    initialSelection: _textLengths.contains(_f.minTextLength)
                        ? _f.minTextLength
                        : 0,
                    width: 180,
                    onSelected: (v) =>
                        setState(() => _f = _f.copyWith(minTextLength: v ?? 0)),
                    dropdownMenuEntries: [
                      for (final n in _textLengths)
                        DropdownMenuEntry(
                          value: n,
                          label: n == 0
                              ? l10n.filterTextAnyLength
                              : l10n.filterFromCharacters(n),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: ConditionEditor(
                    controller: _words,
                    title: Text(
                      l10n.filterTextContent,
                      style: theme.textTheme.titleSmall,
                    ),
                    note: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        l10n.filterTextContentNote,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
                CheckboxListTile(
                  value: _f.wholePost,
                  enabled: mediaPossible,
                  onChanged: !mediaPossible
                      ? null
                      : (v) => setState(
                          () => _f = _f.copyWith(wholePost: v ?? true),
                        ),
                  title: Text(l10n.filterWholePost),
                  subtitle: Text(l10n.filterWholePostNote),
                ),
                CheckboxListTile(
                  value: _f.minimize,
                  onChanged: (v) =>
                      setState(() => _f = _f.copyWith(minimize: v)),
                  title: Text(l10n.filterShowMinimized),
                  subtitle: Text(l10n.filterShowMinimizedNote),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    l10n.filterHiddenCountAsRead,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                TextButton(
                  onPressed: () {
                    _words.clear();
                    setState(() => _f = FeedFilter.none);
                  },
                  child: Text(l10n.filterShowEverything),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.commonCancel),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _apply, child: Text(l10n.commonApply)),
              ],
            ),
          ),
        ],
      ),
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
    final l10n = context.l10n;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      builder: (context, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: l10n.feedEditorSearchJoinedChannels,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          if (widget.channels.any((c) => _tagsOf(c).isNotEmpty))
            CheckboxListTile(
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(l10n.feedEditorHideChannelsInFeeds),
              value: _hideInFeeds,
              onChanged: (v) => _setHideInFeeds(v ?? false),
            ),
          Expanded(
            child: shown.isEmpty
                ? Center(
                    child: Text(
                      widget.channels.isEmpty
                          ? l10n.feedEditorAllChannelsInFeed
                          : _query.trim().isEmpty
                          ? l10n.feedEditorRestInOtherFeeds(
                              l10n.feedEditorHideChannelsInFeeds,
                            )
                          : l10n.feedEditorNoChannelMatches(_query),
                      textAlign: TextAlign.center,
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
                            if (c.memberCount > 0)
                              Text(formatCount(c.memberCount)),
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
                          ? l10n.feedEditorTickChannels
                          : l10n.feedEditorChannelsTicked(_picked.length),
                    ),
                  ),
                  FilledButton(
                    onPressed: _picked.isEmpty
                        ? null
                        : () => Navigator.pop(context, [
                            for (final c in widget.channels)
                              if (_picked.contains(c.chatId)) c,
                          ]),
                    child: Text(l10n.commonAdd),
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

/// A feed filter in the interface language; [FeedFilter.describe] says it in English.
extension FeedFilterWords on FeedFilter {
  /// Short description for lists, e.g. "with media · photos, videos · videos from 1 min".
  String describeIn(AppLocalizations l10n) {
    if (isEmpty) return l10n.filterDescribeEverything;
    final words = text;
    return [
      if (media == MediaPresence.withMedia) l10n.filterDescribeWithMedia,
      if (media == MediaPresence.textOnly) l10n.filterDescribeTextOnly,
      if (kinds.isNotEmpty)
        [
          for (final k in MediaKind.values)
            if (kinds.contains(k)) k.labelIn(l10n),
        ].join(', '),
      if (minVideoSeconds > 0)
        minVideoSeconds % 60 == 0
            ? l10n.filterDescribeVideosFromMinutes(minVideoSeconds ~/ 60)
            : l10n.filterDescribeVideosFromSeconds(minVideoSeconds),
      if (minTextLength > 0) l10n.filterDescribeTextFrom(minTextLength),
      if (words != null) l10n.filterDescribeText(RuleParser.format(words)),
      if (!wholePost) l10n.filterDescribeMatchingParts,
      if (minimize) l10n.filterDescribeRestMinimized,
    ].join(' · ');
  }
}

/// What each kind of media is called in a feed's filter, in the interface language.
extension MediaKindWords on MediaKind {
  /// The word mid-line, e.g. "photos".
  String labelIn(AppLocalizations l10n) => switch (this) {
    MediaKind.photo => l10n.filterKindPhotos,
    MediaKind.video => l10n.filterKindVideos,
    MediaKind.gif => l10n.filterKindGifs,
    MediaKind.audio => l10n.filterKindAudio,
    MediaKind.voice => l10n.filterKindVoice,
    MediaKind.document => l10n.filterKindFiles,
    MediaKind.other => l10n.filterKindOther,
  };

  /// The same word to start a line with, as the filter's chips show it.
  String chipLabelIn(AppLocalizations l10n) {
    final label = labelIn(l10n);
    return label[0].toUpperCase() + label.substring(1);
  }
}
