import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../feeds/open_links.dart';
import '../feeds/post_card.dart' show formatCount;
import '../feeds/shared_media.dart';
import 'channel_list.dart' show ChannelAvatar;

/// What the official app shows behind a channel's title: the photo, the name, how many
/// people read it, its description and link, and the shared media tabs.
///
/// Notifications are not here: this app has its own rules (founder decision 2026-09-19),
/// and it never joins or leaves a channel.
class ChannelInfoScreen extends StatefulWidget {
  const ChannelInfoScreen({
    super.key,
    required this.gateway,
    required this.channel,
  });

  final TelegramGateway gateway;
  final Channel channel;

  @override
  State<ChannelInfoScreen> createState() => _ChannelInfoScreenState();
}

class _ChannelInfoScreenState extends State<ChannelInfoScreen> {
  ChannelInfo? _info;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final info = await widget.gateway.channelInfo(widget.channel.chatId);
      if (mounted) setState(() => _info = info);
    } on TelegramException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// `t.me/<username>` for a public channel, the invite link for a private one.
  String? get _link {
    final username = widget.channel.username;
    if (username != null && username.isNotEmpty) {
      return 'https://t.me/$username';
    }
    final invite = _info?.inviteLink ?? '';
    return invite.isEmpty ? null : invite;
  }

  Future<void> _copyLink(String link) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: link));
    messenger.showSnackBar(SnackBar(content: Text('Link copied: $link')));
  }

  @override
  Widget build(BuildContext context) {
    final channel = widget.channel;
    final info = _info;
    final members = info?.memberCount ?? channel.memberCount;
    final link = _link;
    return Scaffold(
      appBar: AppBar(title: const Text('Channel info')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ChannelAvatar(
                  photo: info?.bigPhoto ?? channel.photo,
                  title: channel.title,
                  gateway: widget.gateway,
                  radius: 32,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        channel.title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        members > 0
                            ? '${formatCount(members)} subscriber${members == 1 ? '' : 's'}'
                            : 'Channel',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Telegram: $_error'),
            ),
          if ((info?.description ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SelectableText(info!.description),
            ),
          if (link != null)
            ListTile(
              leading: const Icon(Icons.link),
              // Public channels are known by their username, private ones by the link.
              title: Text(
                channel.username == null || channel.username!.isEmpty
                    ? link
                    : '@${channel.username}',
              ),
              subtitle: Text(link),
              onTap: () => unawaited(launchFirst([Uri.tryParse(link)])),
              onLongPress: () => unawaited(_copyLink(link)),
              trailing: IconButton(
                tooltip: 'Copy link',
                icon: const Icon(Icons.copy),
                onPressed: () => unawaited(_copyLink(link)),
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: SharedMediaTabs(
              gateway: widget.gateway,
              chatIds: [channel.chatId],
            ),
          ),
        ],
      ),
    );
  }
}
