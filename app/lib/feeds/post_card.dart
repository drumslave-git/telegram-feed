import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../home/channel_list.dart' show ChannelAvatar;
import '../media/media_viewer.dart';
import 'album_layout.dart';
import 'bubble_text.dart';
import 'formatted_text.dart';
import 'media_view.dart';

/// Colours of the chat the official app draws: a tinted backdrop with bubbles on it.
final class ChatColors {
  const ChatColors._({
    required this.background,
    required this.bubble,
    required this.ownBubble,
    required this.pill,
    required this.onPill,
  });

  factory ChatColors.of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    return ChatColors._(
      background: dark
          ? scheme.surfaceContainerLowest
          : Color.alphaBlend(
              scheme.primary.withValues(alpha: 0.14),
              scheme.surfaceContainerHighest,
            ),
      bubble: dark
          ? scheme.surfaceContainerHigh
          : scheme.surfaceContainerLowest,
      ownBubble: dark ? scheme.primaryContainer : const Color(0xFFEFFDDE),
      pill: Colors.black.withValues(alpha: dark ? 0.45 : 0.28),
      onPill: Colors.white,
    );
  }

  final Color background;
  final Color bubble;

  /// Bubble of the account's own comments (Telegram's green in the light theme).
  final Color ownBubble;

  /// Date labels and the share button float on the backdrop in a see-through dark shape.
  final Color pill;
  final Color onPill;
}

/// The seven name colours Telegram gives chats and users, picked by their id.
Color peerColor(int id, Brightness brightness) {
  const light = [
    Color(0xFFCC5049),
    Color(0xFFD67722),
    Color(0xFF955CDB),
    Color(0xFF40A920),
    Color(0xFF309EBA),
    Color(0xFF368AD1),
    Color(0xFFC7508B),
  ];
  const dark = [
    Color(0xFFFF8E86),
    Color(0xFFFFA357),
    Color(0xFFB18FFF),
    Color(0xFF6FD565),
    Color(0xFF5BCBE3),
    Color(0xFF69B5F5),
    Color(0xFFFF7FD5),
  ];
  // Channels and supergroups: the id without the -100 prefix, as the official apps count.
  final bare = id < -1000000000000 ? -id - 1000000000000 : id.abs();
  return (brightness == Brightness.dark ? dark : light)[bare % 7];
}

/// A centred label floating on the chat backdrop: the day, the beginning of the feed.
class ChatPill extends StatelessWidget {
  const ChatPill(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = ChatColors.of(context);
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: colors.pill,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: colors.onPill,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// One timeline row, looking like a post in the official app: the channel's photo, and a
/// bubble with the channel's name, the media (albums as a mosaic), the text, views and time
/// in the bottom right corner, reactions and the comments bar. A tap or a long press on the
/// bubble opens the menu with reactions and actions; the round button beside it shares.
class PostCard extends StatelessWidget {
  const PostCard({
    super.key,
    required this.item,
    required this.channelTitle,
    required this.gateway,
    this.channelPhoto,
    this.unread = false,
    this.onOpenInTelegram,
    this.onShare,
    this.onCopyLink,
    this.onReact,
    this.availableReactions,
    this.onOpenThread,
    this.onOpenLink,
  });
  final TimelineItem item;
  final String channelTitle;
  final FileRef? channelPhoto;
  final TelegramGateway gateway;
  final bool unread;
  final VoidCallback? onOpenInTelegram;
  final VoidCallback? onShare;
  final VoidCallback? onCopyLink;

  /// Tap on a reaction: adds it, or removes it when already chosen.
  final void Function(String emoji, bool remove)? onReact;

  /// Emoji the account may react with; asked when the menu opens.
  final Future<List<String>> Function()? availableReactions;
  final VoidCallback? onOpenThread;

  /// Tap on a link, a mention or an e-mail address in the text.
  final void Function(String url)? onOpenLink;

  bool get _hasMenu =>
      onOpenInTelegram != null ||
      onShare != null ||
      onCopyLink != null ||
      availableReactions != null;

  Future<void> _menu(BuildContext context) async {
    final action = await showModalBottomSheet<VoidCallback>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (availableReactions != null && onReact != null)
              _ReactionStrip(
                load: availableReactions!,
                chosen: {
                  for (final r in item.head.reactions)
                    if (r.chosen) r.emoji,
                },
                onPick: (emoji, remove) =>
                    Navigator.pop(context, () => onReact!(emoji, remove)),
              ),
            if (onOpenInTelegram != null)
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: const Text('Open in Telegram'),
                onTap: () => Navigator.pop(context, onOpenInTelegram),
              ),
            if (onOpenThread != null)
              ListTile(
                leading: const Icon(Icons.forum_outlined),
                title: const Text('Comments'),
                onTap: () => Navigator.pop(context, onOpenThread),
              ),
            if (onShare != null)
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: const Text('Share'),
                onTap: () => Navigator.pop(context, onShare),
              ),
            if (onCopyLink != null)
              ListTile(
                leading: const Icon(Icons.link),
                title: const Text('Copy link'),
                onTap: () => Navigator.pop(context, onCopyLink),
              ),
          ],
        ),
      ),
    );
    action?.call();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ChatColors.of(context);
    // Albums: parts in message order (oldest first) so the layout matches Telegram.
    final media = [
      for (final p in item.allPosts.reversed)
        if (p.media != null) p.media!,
    ];
    final bubble = _Bubble(
      item: item,
      media: media,
      channelTitle: channelTitle,
      gateway: gateway,
      unread: unread,
      onReact: onReact,
      onOpenThread: onOpenThread,
      onOpenLink: onOpenLink,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ChannelAvatar(
            photo: channelPhoto,
            title: channelTitle,
            gateway: gateway,
            radius: 18,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Material(
              color: colors.bubble,
              elevation: 0.5,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                  // The corner by the avatar, where Telegram draws the tail.
                  bottomLeft: Radius.circular(4),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _hasMenu ? () => _menu(context) : null,
                onLongPress: _hasMenu ? () => _menu(context) : null,
                // Text alone makes a bubble as wide as it needs; media fills the row.
                child: media.isEmpty
                    ? IntrinsicWidth(child: bubble)
                    : SizedBox(width: double.infinity, child: bubble),
              ),
            ),
          ),
          const SizedBox(width: 6),
          if (onShare != null)
            Tooltip(
              message: 'Share',
              child: Material(
                color: colors.pill,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onShare,
                  child: SizedBox.square(
                    dimension: 32,
                    child: Transform.flip(
                      flipX: true,
                      child: Icon(Icons.reply, size: 20, color: colors.onPill),
                    ),
                  ),
                ),
              ),
            )
          else
            const SizedBox(width: 32),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.item,
    required this.media,
    required this.channelTitle,
    required this.gateway,
    required this.unread,
    required this.onReact,
    required this.onOpenThread,
    required this.onOpenLink,
  });
  final TimelineItem item;
  final List<Media> media;
  final String channelTitle;
  final TelegramGateway gateway;
  final bool unread;
  final void Function(String emoji, bool remove)? onReact;
  final VoidCallback? onOpenThread;
  final void Function(String url)? onOpenLink;

  static const _side = 10.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final visual = MediaViewerScreen.viewable(media);
    final other = [
      for (final m in media)
        if (m is! PhotoMedia && m is! VideoMedia) m,
    ];
    final reactions = item.head.reactions;
    final text = item.text;
    // Nothing under the pictures: the footer goes on top of them, as in Telegram.
    final footerOnMedia =
        text.isEmpty && reactions.isEmpty && other.isEmpty && visual.isNotEmpty;
    final footer = PostFooter(
      post: item.head,
      unread: unread,
      color: footerOnMedia ? Colors.white : scheme.onSurfaceVariant,
    );

    void open(Media m) => MediaViewerScreen.open(
      context,
      items: visual,
      gateway: gateway,
      initialIndex: visual.indexOf(m),
    );

    Widget? pictures;
    if (visual.length == 1) {
      pictures = MediaView(
        media: visual.single,
        gateway: gateway,
        radius: 0,
        onOpen: () => open(visual.single),
      );
    } else if (visual.length > 1) {
      pictures = AlbumMosaic(media: visual, gateway: gateway, onOpen: open);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(_side, 6, _side, 4),
          child: Text(
            channelTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: peerColor(item.chatId, scheme.brightness),
            ),
          ),
        ),
        if (pictures != null)
          footerOnMedia
              ? Stack(
                  children: [
                    pictures,
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: MediaBadge('', child: footer),
                    ),
                  ],
                )
              : pictures,
        for (final m in other)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _side),
            child: MediaView(media: m, gateway: gateway),
          ),
        if (text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(_side, 6, _side, 6),
            child: reactions.isEmpty
                ? BubbleText(text: _text(context, text), footer: footer)
                : _text(context, text),
          ),
        if (reactions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(_side, 2, _side, 6),
            // The pills use the whole width. The footer goes to the bottom right corner;
            // an unseen copy of it at the end of the pills keeps that corner free, on the
            // last row when there is room and on a row of its own otherwise.
            child: Stack(
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  children: [
                    for (final r in reactions)
                      ReactionPill(
                        reaction: r,
                        onTap: onReact == null
                            ? null
                            : () => onReact!(r.emoji, r.chosen),
                      ),
                    ExcludeSemantics(
                      child: IgnorePointer(
                        child: Opacity(opacity: 0, child: footer),
                      ),
                    ),
                  ],
                ),
                Positioned(right: 0, bottom: 0, child: footer),
              ],
            ),
          ),
        if (text.isEmpty && reactions.isEmpty && !footerOnMedia)
          Padding(
            padding: const EdgeInsets.fromLTRB(_side, 2, _side, 6),
            child: Align(alignment: Alignment.centerRight, child: footer),
          ),
        if (onOpenThread != null)
          _CommentsBar(count: item.head.replyCount, onTap: onOpenThread!),
      ],
    );
  }

  Widget _text(BuildContext context, String text) => FormattedText(
    text: text,
    entities: item.textPost.entities,
    onOpenLink: onOpenLink,
    style: TextStyle(
      fontSize: 16,
      height: 1.3,
      color: Theme.of(context).colorScheme.onSurface,
    ),
  );
}

/// Views, "edited", the time and the unread dot. The dot has a slot of its own that stays
/// when the post is read, so nothing moves when it goes.
class PostFooter extends StatelessWidget {
  const PostFooter({
    super.key,
    required this.post,
    required this.unread,
    required this.color,
  });
  final Post post;
  final bool unread;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 12, color: color, height: 1.2);
    final date = DateTime.fromMillisecondsSinceEpoch(post.date * 1000);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (post.views > 0) ...[
          Icon(Icons.visibility_outlined, size: 14, color: color),
          const SizedBox(width: 3),
          Text(formatCount(post.views), style: style),
          const SizedBox(width: 6),
        ],
        if (post.editDate > 0) ...[
          Text('edited', style: style),
          const SizedBox(width: 4),
        ],
        Text(formatTime(date), style: style),
        SizedBox(
          width: 12,
          child: Align(
            alignment: Alignment.centerRight,
            child: AnimatedOpacity(
              opacity: unread ? 1 : 0,
              duration: const Duration(milliseconds: 250),
              child: Icon(
                Icons.circle,
                size: 8,
                color: Theme.of(context).colorScheme.primary,
                semanticLabel: unread ? 'unread' : null,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// An emoji with its count, filled when this account chose it.
class ReactionPill extends StatelessWidget {
  const ReactionPill({super.key, required this.reaction, this.onTap});
  final Reaction reaction;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chosen = reaction.chosen;
    return Material(
      color: chosen ? scheme.primary : scheme.primary.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            '${reaction.emoji} ${formatCount(reaction.count)}',
            softWrap: false,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: chosen ? scheme.onPrimary : scheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}

class _CommentsBar extends StatelessWidget {
  const _CommentsBar({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(height: 1, color: scheme.outlineVariant),
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 6, 9),
            child: Row(
              children: [
                Icon(Icons.forum_outlined, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    count > 0
                        ? '${formatCount(count)} comment${count == 1 ? '' : 's'}'
                        : 'Leave a comment',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, size: 20, color: scheme.primary),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The emoji the account may use, in one scrolling row at the top of the post menu.
class _ReactionStrip extends StatefulWidget {
  const _ReactionStrip({
    required this.load,
    required this.chosen,
    required this.onPick,
  });
  final Future<List<String>> Function() load;
  final Set<String> chosen;
  final void Function(String emoji, bool remove) onPick;

  @override
  State<_ReactionStrip> createState() => _ReactionStripState();
}

class _ReactionStripState extends State<_ReactionStrip> {
  late final Future<List<String>> _emoji = widget.load();

  @override
  Widget build(BuildContext context) => FutureBuilder<List<String>>(
    future: _emoji,
    builder: (context, snap) {
      final scheme = Theme.of(context).colorScheme;
      final emoji = snap.data;
      if (snap.connectionState != ConnectionState.done) {
        return const SizedBox(
          height: 56,
          child: Center(
            child: SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      }
      if (emoji == null || emoji.isEmpty) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text(
            snap.hasError
                ? 'Reactions could not be loaded.'
                : 'This channel does not allow reactions.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        );
      }
      return SizedBox(
        height: 56,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            for (final e in emoji)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                child: Material(
                  color: widget.chosen.contains(e)
                      ? scheme.primaryContainer
                      : Colors.transparent,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => widget.onPick(e, widget.chosen.contains(e)),
                    child: SizedBox.square(
                      dimension: 44,
                      child: Center(
                        child: Text(e, style: const TextStyle(fontSize: 26)),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

/// The photos and videos of an album in Telegram's mosaic ([layoutAlbum]).
class AlbumMosaic extends StatelessWidget {
  const AlbumMosaic({
    super.key,
    required this.media,
    required this.gateway,
    required this.onOpen,
  });
  final List<Media> media;
  final TelegramGateway gateway;
  final void Function(Media media) onOpen;

  static Size _sizeOf(Media m) => switch (m) {
    PhotoMedia(:final largest) => Size(
      largest.width.toDouble(),
      largest.height.toDouble(),
    ),
    VideoMedia(:final file) => Size(
      file.width.toDouble(),
      file.height.toDouble(),
    ),
    _ => Size.zero,
  };

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final rects = layoutAlbum([
        for (final m in media) _sizeOf(m),
      ], maxWidth: box.maxWidth);
      return SizedBox(
        width: box.maxWidth,
        height: albumHeight(rects),
        child: Stack(
          children: [
            for (final (i, m) in media.indexed)
              Positioned.fromRect(
                rect: rects[i],
                child: MediaView(
                  media: m,
                  gateway: gateway,
                  fill: true,
                  radius: 0,
                  onOpen: () => onOpen(m),
                ),
              ),
          ],
        ),
      );
    },
  );
}

/// 1234 → 1.2K, 3 400 000 → 3.4M, as the official app counts views and reactions.
String formatCount(int n) {
  String short(double v, String unit) {
    final s = v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return '${s.endsWith('.0') ? s.substring(0, s.length - 2) : s}$unit';
  }

  if (n >= 1000000) return short(n / 1000000, 'M');
  if (n >= 1000) return short(n / 1000, 'K');
  return '$n';
}

String formatTime(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// The label between two days of a chat: Today, Yesterday, September 17, March 3, 2025.
String formatDay(DateTime d, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final day = DateTime(d.year, d.month, d.day);
  // Rounded: a day with a clock change is 23 or 25 hours long.
  final days = (DateTime(n.year, n.month, n.day).difference(day).inHours / 24)
      .round();
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  final label = '${months[d.month - 1]} ${d.day}';
  return d.year == n.year ? label : '$label, ${d.year}';
}
