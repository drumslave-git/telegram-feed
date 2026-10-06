import 'dart:async';

import '../feeds/channel_mute.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../feeds/formatted_text.dart';
import '../feeds/media_view.dart' show PhotoView;
import '../feeds/open_links.dart';
import '../feeds/shared_media.dart';
import '../l10n/l10n.dart';
import '../media/media_viewer.dart';
import '../widgets/error_state.dart';
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
    this.share = shareWithSystemSheet,
    this.onShowInChat,
    this.notifications = true,
  });

  /// Whether the screen has the Notifications switch: Saved Messages is no channel to
  /// mute.
  final bool notifications;

  /// Goes to a post of the channel: "Show in chat" of a shared media item. The screen
  /// that opened this one knows how; without it the items have no menu.
  final void Function(Post post)? onShowInChat;

  final TelegramGateway gateway;
  final Channel channel;

  /// Hands the channel's link to Android's share sheet; a test takes its place.
  final Future<void> Function(String text, {required String subject}) share;

  static Future<void> shareWithSystemSheet(
    String text, {
    required String subject,
  }) async {
    await SharePlus.instance.share(ShareParams(text: text, subject: subject));
  }

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
    final copied = context.l10n.channelInfoLinkCopied;
    await Clipboard.setData(ClipboardData(text: link));
    messenger.showSnackBar(SnackBar(content: Text(copied)));
  }

  /// Every photo the channel has had, the current one first; the one photo the channel
  /// list knows while Telegram has not told more, and nothing for a channel without one.
  List<PhotoMedia> get _photos {
    final all = _info?.photos ?? const <PhotoMedia>[];
    if (all.isNotEmpty) return all;
    final one = _info?.bigPhoto ?? widget.channel.photo;
    return one == null
        ? const []
        : [
            PhotoMedia(sizes: [one]),
          ];
  }

  /// The channel's pictures on the whole screen, at the one that was tapped. Without a
  /// photo the tap does nothing, so the initials are not a button that only apologises.
  void _openPhoto([int index = 0]) {
    final photos = _photos;
    if (photos.isEmpty) return;
    unawaited(
      MediaViewerScreen.open(
        context,
        items: photos,
        gateway: widget.gateway,
        initialIndex: index.clamp(0, photos.length - 1),
        details: [
          for (final _ in photos)
            ViewerDetail(channel: widget.channel.title, date: 0),
        ],
      ),
    );
  }

  /// The photo has been pulled down into the gallery of all the channel's photos, as
  /// wide as the screen; the page it stands on.
  bool _gallery = false;
  int _page = 0;

  final _smallHeader = GlobalKey();

  /// Back to the small photo. The gallery is taller than what replaces it, so the screen
  /// is brought back to its top, where that photo stands.
  void _closeGallery() {
    setState(() => _gallery = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final header = _smallHeader.currentContext;
      if (header == null || !mounted) return;
      unawaited(Scrollable.ensureVisible(header));
    });
  }

  /// A pull down at the top of the screen opens the gallery, as in the official app.
  bool _onOverscroll(OverscrollNotification n) {
    if (!_gallery &&
        n.metrics.axis == Axis.vertical &&
        n.overscroll < 0 &&
        n.dragDetails != null &&
        _photos.isNotEmpty) {
      setState(() => _gallery = true);
    }
    return false;
  }

  Future<void> _openLink(String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    if (await launchFirst([Uri.tryParse(url)])) return;
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.timelineNoAppForLink(url))),
    );
  }

  Future<void> _copyDescription(String text) async {
    final messenger = ScaffoldMessenger.of(context);
    final copied = context.l10n.timelineTextCopied;
    await Clipboard.setData(ClipboardData(text: text));
    messenger.showSnackBar(SnackBar(content: Text(copied)));
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
            child: Text(context.l10n.commonClose),
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
    final l10n = context.l10n;
    // The count in full, with the digits grouped as the language groups them.
    final subscribers = members > 0
        ? l10n.channelInfoSubscribers(
            members,
            NumberFormat.decimalPattern(
              l10n.localeName == 'en' ? 'en_US' : l10n.localeName,
            ).format(members),
          )
        : l10n.channelInfoChannel;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.channelInfoTitle),
        actions: [
          if (link != null)
            IconButton(
              tooltip: l10n.channelInfoQrCode,
              icon: const Icon(Icons.qr_code),
              onPressed: () => _showQr(link),
            ),
        ],
      ),
      body: NotificationListener<OverscrollNotification>(
        onNotification: _onOverscroll,
        child: SharedMediaTabs(
          gateway: widget.gateway,
          chatIds: [channel.chatId],
          titles: {channel.chatId: channel.title},
          onShowInChat: widget.onShowInChat,
          header: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_gallery && _photos.isNotEmpty)
                _PhotoGallery(
                  photos: _photos,
                  page: _page,
                  gateway: widget.gateway,
                  title: channel.title,
                  subtitle: subscribers,
                  onPage: (i) => setState(() => _page = i),
                  onOpen: _openPhoto,
                  onClose: _closeGallery,
                )
              else
                Padding(
                  key: _smallHeader,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        // The photo opens full screen, as in the official app.
                        onTap: _openPhoto,
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
                              subscribers,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              // The small header ends with room under it; the gallery ends at its edge.
              if (_gallery && _photos.isNotEmpty) const SizedBox(height: 12),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: ErrorState(
                    what: l10n.channelInfoLoadFailed,
                    message: _error,
                    compact: true,
                    onRetry: () {
                      setState(() => _error = null);
                      unawaited(_load());
                    },
                  ),
                ),
              if ((info?.description ?? '').isNotEmpty)
                // Links, mentions and tags in it open as in a post; a long press copies it.
                GestureDetector(
                  onLongPress: () =>
                      unawaited(_copyDescription(info.description)),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: FormattedText(
                      text: info!.description,
                      entities: info.descriptionEntities,
                      onOpenLink: (url) => unawaited(_openLink(url)),
                      gateway: widget.gateway,
                      style:
                          Theme.of(context).textTheme.bodyMedium ??
                          const TextStyle(),
                    ),
                  ),
                )
              // Two grey lines while the description is on its way, so the rows below do not
              // jump down the moment it arrives.
              else if (info == null && _error == null)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: _DescriptionSkeleton(),
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
                  // The link is for passing on: a tap opens the share sheet, as in the
                  // official app.
                  onTap: () =>
                      unawaited(widget.share(link, subject: channel.title)),
                  trailing: IconButton(
                    tooltip: l10n.commonCopyLink,
                    icon: const Icon(Icons.copy),
                    onPressed: () => unawaited(_copyLink(link)),
                  ),
                ),
              // Mute and unmute in Telegram, as the official app's Notifications switch.
              if (widget.notifications)
                ChannelNotificationsSwitch(
                  gateway: widget.gateway,
                  channel: channel,
                ),
              if (_similar.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: Text(
                    l10n.channelInfoSimilarChannels,
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
                      // The app never joins a channel, so a suggestion opens in Telegram;
                      // the little arrow says so, and a channel without a public link is
                      // dimmed because nothing can open it.
                      final url = (c.username ?? '').isEmpty
                          ? null
                          : 'https://t.me/${c.username}';
                      return SizedBox(
                        width: 88,
                        child: Opacity(
                          opacity: url == null ? 0.5 : 1,
                          child: InkWell(
                            onTap: url == null
                                ? null
                                : () => unawaited(
                                    launchFirst([Uri.tryParse(url)]),
                                  ),
                            child: Column(
                              children: [
                                const SizedBox(height: 6),
                                Stack(
                                  children: [
                                    ChannelAvatar(
                                      photo: c.photo,
                                      title: c.title,
                                      colorId: c.chatId,
                                      gateway: widget.gateway,
                                      radius: 24,
                                    ),
                                    if (url != null)
                                      Positioned(
                                        right: 0,
                                        bottom: 0,
                                        child: _OpenBadge(),
                                      ),
                                  ],
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
                        ),
                      );
                    },
                  ),
                ),
              ],
              const Divider(height: 1),
            ],
          ),
        ),
      ),
    );
  }
}

/// Every photo of the channel, as wide as the screen, one swipe apart, with the name over
/// the lower edge and a mark for each photo along the upper one, as the official app
/// shows a profile's photos once the small one is pulled down. A tap opens the photo on
/// the whole screen.
class _PhotoGallery extends StatelessWidget {
  const _PhotoGallery({
    required this.photos,
    required this.page,
    required this.gateway,
    required this.title,
    required this.subtitle,
    required this.onPage,
    required this.onOpen,
    required this.onClose,
  });
  final List<PhotoMedia> photos;
  final int page;
  final TelegramGateway gateway;
  final String title;
  final String subtitle;
  final ValueChanged<int> onPage;
  final void Function(int index) onOpen;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AspectRatio(
      aspectRatio: 1,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            key: const ValueKey('channel-photos'),
            controller: PageController(initialPage: page),
            itemCount: photos.length,
            onPageChanged: onPage,
            // The page itself answers the tap, loaded or not.
            itemBuilder: (context, i) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onOpen(i),
              child: IgnorePointer(
                child: PhotoView(
                  // The largest size: the photo fills the width of the screen.
                  file: photos[i].sizes.last,
                  gateway: gateway,
                  fill: true,
                  radius: 0,
                  miniature: photos[i].miniature,
                ),
              ),
            ),
          ),
          // The name stays readable on any photo.
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black38, Colors.transparent, Colors.black54],
                  stops: [0, 0.3, 1],
                ),
              ),
            ),
          ),
          if (photos.length > 1)
            Positioned(
              left: 8,
              right: 8,
              top: 8,
              child: Semantics(
                label: l10n.channelInfoPhotoOf(page + 1, photos.length),
                child: Row(
                  children: [
                    for (var i = 0; i < photos.length; i++)
                      Expanded(
                        child: Container(
                          height: 2,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: i == page ? Colors.white : Colors.white38,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          Positioned(
            left: 16,
            right: 56,
            bottom: 12,
            child: IgnorePointer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(color: Colors.white),
                  ),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 4,
            bottom: 4,
            child: IconButton(
              tooltip: l10n.channelInfoCloseGallery,
              icon: const Icon(Icons.expand_less, color: Colors.white),
              onPressed: onClose,
            ),
          ),
        ],
      ),
    );
  }
}

/// The corner mark of a channel that opens in the official Telegram app.
class _OpenBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: scheme.surface, shape: BoxShape.circle),
      child: Icon(Icons.open_in_new, size: 12, color: scheme.onSurfaceVariant),
    );
  }
}

/// Grey lines standing in for a description that has not arrived yet.
class _DescriptionSkeleton extends StatelessWidget {
  const _DescriptionSkeleton();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface
        .withValues(alpha: 0.08);
    Widget line(double width) => Container(
      width: width,
      height: 12,
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
    );
    return ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [line(double.infinity), line(180)],
      ),
    );
  }
}
