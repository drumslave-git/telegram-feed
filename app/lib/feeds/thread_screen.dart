import 'dart:async';

import 'package:flutter/material.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

/// Comments on a post from the channel's discussion group, with a reply composer.
class ThreadScreen extends StatefulWidget {
  const ThreadScreen({
    super.key,
    required this.gateway,
    required this.post,
    required this.channelTitle,
  });
  final TelegramGateway gateway;
  final Post post;
  final String channelTitle;

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

  @override
  void initState() {
    super.initState();
    unawaited(_open());
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
    _live?.cancel();
    final t = _thread;
    if (t != null) unawaited(widget.gateway.closeThread(t));
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.channelTitle.isEmpty
              ? 'Comments'
              : 'Comments · ${widget.channelTitle}',
        ),
      ),
      body: Column(
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
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: _comments.length + 2,
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.channelTitle,
                                  style: theme.textTheme.labelLarge,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  widget.post.text,
                                  maxLines: 8,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (!_exhausted && _thread != null)
                                  TextButton(
                                    onPressed: _loading ? null : _loadOlder,
                                    child: Text(
                                      _loading
                                          ? 'Loading…'
                                          : 'Load older comments',
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      }
                      if (i == _comments.length + 1) {
                        return _comments.isEmpty && !_loading
                            ? const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(child: Text('No comments yet.')),
                              )
                            : const SizedBox(height: 8);
                      }
                      final c = _comments[i - 1];
                      return Align(
                        alignment: c.isOutgoing
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 320),
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: c.isOutgoing
                                ? theme.colorScheme.primaryContainer
                                : theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (c.author.isNotEmpty)
                                Text(
                                  c.author,
                                  style: theme.textTheme.labelMedium,
                                ),
                              Text(c.text),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (_thread != null)
            SafeArea(
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
        ],
      ),
    );
  }
}
