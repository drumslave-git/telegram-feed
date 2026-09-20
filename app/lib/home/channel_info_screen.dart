import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/services.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../feeds/open_links.dart';
import '../feeds/post_card.dart' show formatCount;
import '../feeds/shared_media.dart';
import '../media/media_viewer.dart';
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
    unawaited(_loadSimilar());
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

  /// The channel's own picture on the whole screen; a channel without one says so.
  void _openPhoto(FileRef? photo) {
    if (photo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This channel has no photo.')),
      );
      return;
    }
    unawaited(
      MediaViewerScreen.open(
        context,
        items: [
          PhotoMedia(sizes: [photo]),
        ],
        gateway: widget.gateway,
        details: [ViewerDetail(channel: widget.channel.title, date: 0)],
      ),
    );
  }

  /// Channels Telegram suggests; loaded once with the info.
  List<Channel> _similar = const [];

  Future<void> _loadSimilar() async {
    try {
      final similar = await widget.gateway.similarChannels(
        widget.channel.chatId,
      );
      if (mounted) setState(() => _similar = similar);
    } on TelegramException {
      // No suggestions, no section.
    }
  }

  /// The channel's link as a QR code, which the official app shows for sharing it.
  void _showQr(String link) => unawaited(
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.channel.title),
        content: SizedBox(
          width: 240,
          height: 280,
          child: Column(
            children: [
              Expanded(
                child: QrImageView(data: link, backgroundColor: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(link, textAlign: TextAlign.center),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final channel = widget.channel;
    final info = _info;
    final members = info?.memberCount ?? channel.memberCount;
    final link = _link;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Channel info'),
        actions: [
          if (link != null)
            IconButton(
              tooltip: 'QR code',
              icon: const Icon(Icons.qr_code),
              onPressed: () => _showQr(link),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  // The photo opens full screen, as in the official app.
                  onTap: () => _openPhoto(info?.bigPhoto ?? channel.photo),
                  child: ChannelAvatar(
                    photo: info?.bigPhoto ?? channel.photo,
                    title: channel.title,
                    gateway: widget.gateway,
                    radius: 32,
                  ),
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
          if (_similar.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text(
                'Similar channels',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            SizedBox(
              height: 104,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _similar.length,
                itemBuilder: (context, i) {
                  final c = _similar[i];
                  // The app never joins a channel, so a suggestion opens in Telegram.
                  final url = (c.username ?? '').isEmpty
                      ? null
                      : 'https://t.me/${c.username}';
                  return SizedBox(
                    width: 88,
                    child: InkWell(
                      onTap: url == null
                          ? null
                          : () => unawaited(launchFirst([Uri.tryParse(url)])),
                      child: Column(
                        children: [
                          const SizedBox(height: 6),
                          ChannelAvatar(
                            photo: c.photo,
                            title: c.title,
                            gateway: widget.gateway,
                            radius: 24,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            c.title,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
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
