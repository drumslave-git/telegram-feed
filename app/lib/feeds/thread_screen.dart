import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'bubble_text.dart';
import 'formatted_text.dart';
import 'open_links.dart';
import 'post_card.dart';
import 'text_scale.dart';

/// Comments on a post from the channel's discussion group, with a reply composer.
class ThreadScreen extends StatefulWidget {
  const ThreadScreen({
    super.key,
    required this.gateway,
    required this.post,
    required this.channelTitle,
    this.channelPhoto,
    this.item,
  });
  final TelegramGateway gateway;
  final Post post;
  final String channelTitle;
  final FileRef? channelPhoto;

  /// The timeline row of [post]; with it the header shows the whole album.
  final TimelineItem? item;

  @override
  State<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<ThreadScreen> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  Thread? _thread;
  bool _loading = true;
  bool _noThread = false;
  bool _sending = false;
  bool _exhausted = false;
  String? _error;
  final _comments = <Comment>[]; // oldest first
  StreamSubscription<Comment>? _live;

  /// Search inside the thread (H-27): open, the words, what was found (newest first).
  bool _searchOpen = false;
  final _queryCtl = TextEditingController();
  Timer? _debounce;
  List<Comment>? _found;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  void _openSearch() => setState(() => _searchOpen = true);

  void _closeSearch() {
    _debounce?.cancel();
    _queryCtl.clear();
    setState(() {
      _searchOpen = false;
      _found = null;
    });
  }

  void _onQuery(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(_search(value)),
    );
  }

  /// Telegram searches the thread itself, so a comment far above is found without loading
  /// everything in between.
  Future<void> _search(String value) async {
    final thread = _thread;
    final query = value.trim();
    if (thread == null) return;
    if (query.isEmpty) {
      setState(() => _found = null);
      return;
    }
    setState(() => _searching = true);
    try {
      final found = await widget.gateway.searchThread(thread, query: query);
      if (mounted) setState(() => _found = found);
    } on TelegramException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _open() async {
    try {
      final t = await widget.gateway.discussion(
        widget.post.chatId,
        widget.post.messageId,
      );
      if (!mounted) return;
      if (t == null) {
        setState(() {
          _noThread = true;
          _loading = false;
        });
        return;
      }
      _thread = t;
      _live = widget.gateway.comments.listen((c) {
        if (c.chatId != t.chatId || c.threadId != t.threadId) return;
        if (_comments.any((x) => x.messageId == c.messageId)) return;
        setState(() => _comments.add(c));
        _scrollToEnd();
      });
      await _loadOlder();
    } on TelegramException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadOlder() async {
    final t = _thread;
    if (t == null || _exhausted) return;
    setState(() => _loading = true);
    try {
      final oldest = _comments.isEmpty ? 0 : _comments.first.messageId;
      final page = await widget.gateway.threadHistory(
        t,
        fromMessageId: oldest,
        limit: 30,
      );
      if (!mounted) return;
      setState(() {
        if (page.isEmpty) _exhausted = true;
        // Page is newest first; prepend in chronological order.
        _comments.insertAll(
          0,
          page.reversed.where(
            (c) => !_comments.any((x) => x.messageId == c.messageId),
          ),
        );
        _loading = false;
      });
    } on TelegramException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  Future<void> _send() async {
    final t = _thread;
    final text = _composer.text.trim();
    if (t == null || text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.gateway.reply(t, text);
      _composer.clear();
    } on TelegramException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Telegram: ${e.message}')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openLink(String url) async {
    final messenger = ScaffoldMessenger.of(context);
    if (await launchFirst([Uri.tryParse(url)])) return;
    messenger.showSnackBar(SnackBar(content: Text('No app can open $url')));
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryCtl.dispose();
    _live?.cancel();
    final t = _thread;
    if (t != null) unawaited(widget.gateway.closeThread(t));
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ChatColors.of(context);
    final found = _found;
    return Scaffold(
      appBar: _searchOpen
          ? AppBar(
              leading: BackButton(onPressed: _closeSearch),
              titleSpacing: 0,
              title: TextField(
                controller: _queryCtl,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Search comments',
                  border: InputBorder.none,
                ),
                onChanged: _onQuery,
              ),
              actions: [
                if (_queryCtl.text.isNotEmpty)
                  IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _queryCtl.clear();
                      _onQuery('');
                    },
                  ),
              ],
            )
          : AppBar(
              title: Text(
                widget.channelTitle.isEmpty
                    ? 'Comments'
                    : 'Comments · ${widget.channelTitle}',
              ),
              actions: [
                if (!_noThread)
                  IconButton(
                    tooltip: 'Search comments',
                    icon: const Icon(Icons.search),
                    onPressed: _openSearch,
                  ),
              ],
            ),
      // The comments follow the reader's text size, like the posts.
      body: PostTextScale.wrap(
        context,
        ColoredBox(
          color: colors.background,
          child: Column(
            children: [
              Expanded(
                child: _noThread
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            'This channel has no discussion group, so posts cannot be commented on.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : _error != null && _comments.isEmpty
                    ? Center(child: Text('Telegram: $_error'))
                    // While searching, what was found takes the place of the thread.
                    : found != null
                    ? (found.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Text(
                                  _searching
                                      ? 'Searching…'
                                      : 'Nothing found for "${_queryCtl.text}".',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: found.length,
                              itemBuilder: (context, i) => CommentBubble(
                                comment: found[i],
                                gateway: widget.gateway,
                                onOpenLink: _openLink,
                              ),
                            ))
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _comments.length + 2,
                        itemBuilder: (context, i) {
                          if (i == 0) return _header();
                          if (i == _comments.length + 1) {
                            return _comments.isEmpty && !_loading
                                ? const ChatPill('No comments yet.')
                                : const SizedBox(height: 8);
                          }
                          return CommentBubble(
                            comment: _comments[i - 1],
                            gateway: widget.gateway,
                            onOpenLink: _openLink,
                          );
                        },
                      ),
              ),
              if (_thread != null)
                Material(
                  color: Theme.of(context).colorScheme.surface,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _composer,
                              minLines: 1,
                              maxLines: 4,
                              decoration: const InputDecoration(
                                hintText: 'Write a comment',
                                isDense: true,
                              ),
                              onSubmitted: (_) => _send(),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Send',
                            icon: const Icon(Icons.send),
                            onPressed: _sending ? null : _send,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The post the comments belong to, as it looks in the timeline, as the official app
  /// shows it on top of its comments.
  Widget _header() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PostCard(
        item: widget.item ?? TimelineItem(widget.post),
        channelTitle: widget.channelTitle,
        channelPhoto: widget.channelPhoto,
        gateway: widget.gateway,
        onOpenLink: _openLink,
      ),
      if (!_exhausted && _thread != null)
        Center(
          child: TextButton(
            onPressed: _loading ? null : _loadOlder,
            child: Text(_loading ? 'Loading…' : 'Load older comments'),
          ),
        )
      else if (_comments.isNotEmpty)
        const ChatPill('Discussion started'),
    ],
  );
}

/// One comment: a bubble with the coloured name, the author's photo at the right end of
/// that line, the text and the time. Own comments sit on the right without name and photo.
class CommentBubble extends StatelessWidget {
  const CommentBubble({
    super.key,
    required this.comment,
    required this.gateway,
    this.onOpenLink,
  });
  final Comment comment;
  final TelegramGateway gateway;
  final void Function(String url)? onOpenLink;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = ChatColors.of(context);
    final c = comment;
    final own = c.isOutgoing;
    final time = Text(
      formatTime(DateTime.fromMillisecondsSinceEpoch(c.date * 1000)),
      style: TextStyle(
        fontSize: 12,
        height: 1.2,
        color: scheme.onSurfaceVariant,
      ),
    );
    final bubble = Material(
      color: own ? colors.ownBubble : colors.bubble,
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(14),
          topRight: const Radius.circular(14),
          bottomLeft: const Radius.circular(14),
          bottomRight: Radius.circular(own ? 4 : 14),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        child: IntrinsicWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!own)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: BubbleTitle(
                    name: c.author,
                    colorId: c.authorId,
                    photo: c.authorPhoto,
                    gateway: gateway,
                  ),
                ),
              BubbleText(
                text: FormattedText(
                  text: c.text,
                  entities: c.entities,
                  onOpenLink: onOpenLink,
                  gateway: gateway,
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.3,
                    color: scheme.onSurface,
                  ),
                ),
                footer: time,
              ),
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(own ? 48 : 8, 3, own ? 8 : 48, 3),
      child: Align(
        alignment: own ? Alignment.centerRight : Alignment.centerLeft,
        child: bubble,
      ),
    );
  }
}
