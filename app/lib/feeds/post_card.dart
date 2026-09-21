import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../home/channel_list.dart' show ChannelAvatar;
import '../media/media_viewer.dart';
import 'album_layout.dart';
import 'bubble_text.dart';
import 'formatted_text.dart';
import 'link_preview.dart';
import 'media_view.dart';
import 'text_scale.dart';

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

  /// Date labels float on the backdrop in a see-through dark shape.
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
  const ChatPill(this.label, {super.key, this.onTap});
  final String label;

  /// Day pills lead to the calendar; the other pills are labels only.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = ChatColors.of(context);
    final pill = Container(
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
    );
    return Center(
      child: onTap == null
          ? pill
          : GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: pill,
            ),
    );
  }
}

/// What a double tap sends until the reader has reacted with something else.
const defaultQuickReaction = '\u{1F44D}';

/// One timeline row, looking like a post in the official app, except that the bubble has
/// the whole width: the channel's name with its photo at the right end of that line, the
/// media (albums as a mosaic), the text, views and time in the bottom right corner,
/// reactions and the comments bar. A long press on the bubble opens the menu with reactions
/// and actions, sharing among them; a double tap sends the quick reaction.
class PostCard extends StatelessWidget {
  const PostCard({
    super.key,
    required this.item,
    required this.channelTitle,
    required this.gateway,
    this.channelPhoto,
    this.onOpenInTelegram,
    this.onShare,
    this.onCopyLink,
    this.onCopyText,
    this.onSave,
    this.onReact,
    this.availableReactions,
    this.onOpenThread,
    this.onOpenLink,
    this.onAutoplaySettings,
    this.onOpenForward,
    this.onOpenReply,
    this.onQuickReact,
    this.onSelect,
    this.selecting = false,
    this.selected = false,
    this.onViewerMedia,
    this.onMoreViewerMedia,
    this.onViewerDetails,
    this.onViewerShare,
    this.onViewerSave,
  });
  final TimelineItem item;
  final String channelTitle;
  final FileRef? channelPhoto;
  final TelegramGateway gateway;
  final VoidCallback? onOpenInTelegram;
  final VoidCallback? onShare;
  final VoidCallback? onCopyLink;

  /// Copies the post's text; absent on a post without words.
  final VoidCallback? onCopyText;

  /// Forwards the post into the account's Saved Messages.
  final VoidCallback? onSave;

  /// Tap on a reaction: adds it, or removes it when already chosen.
  final void Function(String emoji, bool remove)? onReact;

  /// Emoji the account may react with; asked when the menu opens.
  final Future<List<String>> Function()? availableReactions;
  final VoidCallback? onOpenThread;

  /// Tap on a link, a mention or an e-mail address in the text.
  final void Function(String url)? onOpenLink;

  /// Menu entry of posts with a video: the autoplay switch and limits.
  final VoidCallback? onAutoplaySettings;

  /// Tap on the "Forwarded from" line: opens the original post where the app can.
  final VoidCallback? onOpenForward;

  /// Tap on the quote block: jumps to the post this one answers.
  final VoidCallback? onOpenReply;

  /// Double tap on the bubble: sends the quick reaction, as the official app does.
  final VoidCallback? onQuickReact;

  /// "Select" in the menu, and every tap while the timeline is selecting.
  final VoidCallback? onSelect;

  /// The timeline is choosing posts: a tap anywhere on the row picks this one, and nothing
  /// else in it answers.
  final bool selecting;
  final bool selected;

  /// All the media the timeline holds, for the viewer to page through; without it the
  /// viewer shows the post's own album alone.
  final List<Media> Function()? onViewerMedia;

  /// Loads the timeline's next page and answers with all of its media again.
  final Future<List<Media>> Function()? onMoreViewerMedia;

  /// The channel, the day and the caption of each item in the viewer.
  final List<ViewerDetail> Function()? onViewerDetails;

  /// Share and save from inside the viewer, by the index of the picture.
  final void Function(int index)? onViewerShare;
  final void Function(int index)? onViewerSave;

  bool get _hasMenu =>
      onOpenInTelegram != null ||
      onShare != null ||
      onCopyLink != null ||
      onCopyText != null ||
      onSelect != null ||
      onSave != null ||
      availableReactions != null;

  Future<void> _menu(BuildContext context) async {
    final action = await showModalBottomSheet<VoidCallback>(
      context: context,
      showDragHandle: true,
      // Scrollable: with the reactions on top the entries do not all fit on a short screen.
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
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
              if (onSelect != null)
                ListTile(
                  leading: const Icon(Icons.checklist),
                  title: const Text('Select'),
                  onTap: () => Navigator.pop(context, onSelect),
                ),
              if (onCopyText != null && item.text.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.content_copy),
                  title: const Text('Copy text'),
                  onTap: () => Navigator.pop(context, onCopyText),
                ),
              if (onCopyLink != null)
                ListTile(
                  leading: const Icon(Icons.link),
                  title: const Text('Copy link'),
                  onTap: () => Navigator.pop(context, onCopyLink),
                ),
              if (onSave != null)
                ListTile(
                  leading: const Icon(Icons.bookmark_add_outlined),
                  title: const Text('Save to Saved Messages'),
                  onTap: () => Navigator.pop(context, onSave),
                ),
              if (onAutoplaySettings != null &&
                  item.allPosts.any((p) => p.media is VideoMedia))
                ListTile(
                  leading: const Icon(Icons.play_circle_outline),
                  title: const Text('Autoplay and download settings'),
                  onTap: () => Navigator.pop(context, onAutoplaySettings),
                ),
            ],
          ),
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
      channelPhoto: channelPhoto,
      gateway: gateway,
      onReact: onReact,
      onOpenThread: onOpenThread,
      onOpenLink: onOpenLink,
      onOpenForward: onOpenForward,
      onOpenReply: onOpenReply,
      onQuickReact: onQuickReact,
      onViewerMedia: onViewerMedia,
      onMoreViewerMedia: onMoreViewerMedia,
      onViewerDetails: onViewerDetails,
      onViewerShare: onViewerShare,
      onViewerSave: onViewerSave,
    );
    // The bubble has the row to itself: the channel's photo sits in its title line and
    // sharing is in the menu, so nothing beside it takes width from text and pictures.
    // Everything in it follows the reader's text size.
    final card = PostTextScale.wrap(
      context,
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Material(
            color: colors.bubble,
            elevation: 0.5,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(14)),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              // A long press opens the menu, as in the official app: a plain tap cannot do
              // that and leave room for the double tap that sends the quick reaction,
              // because the menu would swallow the second tap.
              onLongPress: _hasMenu ? () => _menu(context) : null,
              // Text alone makes a bubble as wide as it needs; media fills the row, and so
              // does a link preview, whose card and picture would otherwise be squeezed into
              // the width of the words above it.
              child: media.isEmpty && item.textPost.linkPreview == null
                  ? IntrinsicWidth(child: bubble)
                  : SizedBox(width: double.infinity, child: bubble),
            ),
          ),
        ),
      ),
    );
    if (!selecting) return card;
    // While the timeline selects, the row answers nothing but the tap that picks it.
    return Stack(
      children: [
        card,
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onSelect,
            child: ColoredBox(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                        .withValues(alpha: 0.18)
                  : Colors.transparent,
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The first line of a bubble: the coloured name, and the photo at its right end.
class BubbleTitle extends StatelessWidget {
  const BubbleTitle({
    super.key,
    required this.name,
    required this.colorId,
    required this.photo,
    required this.gateway,
  });
  final String name;

  /// Chat or user id; picks the colour of the name ([peerColor]).
  final int colorId;
  final FileRef? photo;
  final TelegramGateway gateway;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: peerColor(colorId, Theme.of(context).colorScheme.brightness),
          ),
        ),
      ),
      const SizedBox(width: 8),
      ChannelAvatar(photo: photo, title: name, gateway: gateway, radius: 12),
    ],
  );
}

/// "Forwarded from `<name>`", the line the official app draws above a forwarded post. The
/// signature of the original author follows the name, as it does there.
class ForwardedFrom extends StatelessWidget {
  const ForwardedFrom({super.key, required this.origin, this.onTap});
  final ForwardOrigin origin;

  /// Opens the original post, when it is one of a channel the account follows.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = origin.title.isEmpty ? 'a hidden account' : origin.title;
    final row = Text.rich(
      TextSpan(
        children: [
          const TextSpan(text: 'Forwarded from '),
          TextSpan(
            text: name,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (origin.signature.isNotEmpty)
            TextSpan(text: ' (${origin.signature})'),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
    );
    return onTap == null
        ? row
        : GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: row,
          );
  }
}

/// The post a post answers, as a quote block above the text: the accent bar, whose post it
/// was, and a line of what it said, with a small square of its picture. A tap jumps to it.
class RepliedPost extends StatelessWidget {
  const RepliedPost({
    super.key,
    required this.reply,
    required this.colorId,
    required this.channelTitle,
    required this.gateway,
    this.onTap,
  });
  final ReplyTarget reply;

  /// Chat id of the channel the post is in; picks the accent colour.
  final int colorId;

  /// Name for a reply inside the channel, where TDLib names nobody.
  final String channelTitle;
  final TelegramGateway gateway;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = peerColor(colorId, scheme.brightness);
    final name = reply.title.isEmpty ? channelTitle : reply.title;
    final photo = reply.photo;
    final block = Material(
      color: accent.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: accent, width: 3)),
          ),
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (photo != null) ...[
                SizedBox(
                  width: 32,
                  height: 32,
                  child: PhotoView(
                    file: photo.sizes.first,
                    gateway: gateway,
                    onTap: onTap,
                    fill: true,
                    radius: 4,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: accent,
                      ),
                    ),
                    Text(
                      reply.text.isEmpty ? 'Post' : reply.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                        // A quote the author picked out of the post is set apart.
                        fontStyle: reply.manualQuote
                            ? FontStyle.italic
                            : FontStyle.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return block;
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.item,
    required this.media,
    required this.channelTitle,
    required this.channelPhoto,
    required this.gateway,
    required this.onReact,
    required this.onOpenThread,
    required this.onOpenLink,
    required this.onOpenForward,
    required this.onOpenReply,
    required this.onQuickReact,
    required this.onViewerMedia,
    required this.onMoreViewerMedia,
    required this.onViewerDetails,
    required this.onViewerShare,
    required this.onViewerSave,
  });
  final TimelineItem item;
  final List<Media> media;
  final String channelTitle;
  final FileRef? channelPhoto;
  final TelegramGateway gateway;
  final void Function(String emoji, bool remove)? onReact;
  final VoidCallback? onOpenThread;
  final void Function(String url)? onOpenLink;
  final VoidCallback? onOpenForward;
  final VoidCallback? onOpenReply;
  final VoidCallback? onQuickReact;
  final List<Media> Function()? onViewerMedia;
  final Future<List<Media>> Function()? onMoreViewerMedia;
  final List<ViewerDetail> Function()? onViewerDetails;
  final void Function(int index)? onViewerShare;
  final void Function(int index)? onViewerSave;

  static const _side = 10.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final visual = MediaViewerScreen.viewable(media);
    // Everything the viewer does not take stands in the bubble as its own row: audio,
    // documents, stickers and round video messages.
    final other = [
      for (final m in media)
        if (!visual.contains(m)) m,
    ];
    final reactions = item.head.reactions;
    final text = item.text;
    // Only a text post carries a link preview, so it never belongs to an album.
    final preview = item.textPost.linkPreview;
    // Nothing under the pictures: the footer goes on top of them, as in Telegram.
    final footerOnMedia =
        text.isEmpty && reactions.isEmpty && other.isEmpty && visual.isNotEmpty;
    final footer = PostFooter(
      post: item.head,
      color: footerOnMedia ? Colors.white : scheme.onSurfaceVariant,
    );

    void open(Media m) {
      // The viewer pages through the media of the whole timeline when it can (H-21), so
      // this post's album is only where it starts.
      final around = onViewerMedia?.call() ?? visual;
      final items = around.contains(m) ? around : visual;
      final whole = identical(items, around);
      MediaViewerScreen.open(
        context,
        items: items,
        gateway: gateway,
        initialIndex: items.indexOf(m),
        onNeedOlder: whole ? onMoreViewerMedia : null,
        details: whole ? onViewerDetails?.call() ?? const [] : const [],
        onDetails: whole ? onViewerDetails : null,
        onShare: whole ? onViewerShare : null,
        onSave: whole ? onViewerSave : null,
      );
    }

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

    final card = preview == null
        ? null
        : Padding(
            padding: const EdgeInsets.fromLTRB(_side, 2, _side, 4),
            child: LinkPreviewCard(
              preview: preview,
              colorId: item.chatId,
              gateway: gateway,
              onOpen: onOpenLink == null
                  ? null
                  : () => onOpenLink!(preview.url),
            ),
          );
    // The footer lies on the last line of the text, unless the card comes after it: then it
    // goes under the card, where the official app puts it too.
    final footerUnderCard =
        card != null && !preview!.aboveText && reactions.isEmpty;

    /// The quick reaction is sent by a double tap on the words, and on the pictures of a
    /// post that has none. A recognizer over the whole bubble would hold the gesture arena
    /// for 300 ms and make every tap inside it — a reaction pill, the comments bar, a
    /// picture — answer late.
    Widget quickReactable(Widget child) => onQuickReact == null
        ? child
        : GestureDetector(onDoubleTap: onQuickReact, child: child);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(_side, 5, 6, 5),
          child: BubbleTitle(
            name: channelTitle,
            colorId: item.chatId,
            photo: channelPhoto,
            gateway: gateway,
          ),
        ),
        if (item.head.forwardedFrom != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(_side, 0, _side, 5),
            child: ForwardedFrom(
              origin: item.head.forwardedFrom!,
              onTap: onOpenForward,
            ),
          ),
        if (item.textPost.replyTo != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(_side, 0, _side, 5),
            child: RepliedPost(
              reply: item.textPost.replyTo!,
              colorId: item.chatId,
              channelTitle: channelTitle,
              gateway: gateway,
              onTap: onOpenReply,
            ),
          ),
        if (pictures != null)
          footerOnMedia
              ? quickReactable(
                  Stack(
                    children: [
                      pictures,
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: MediaBadge('', child: footer),
                      ),
                    ],
                  ),
                )
              : text.isEmpty
              ? quickReactable(pictures)
              : pictures,
        for (final m in other)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _side),
            child: MediaView(media: m, gateway: gateway),
          ),
        if (card != null && preview!.aboveText) card,
        if (text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(_side, 6, _side, 6),
            child: quickReactable(
              reactions.isEmpty && !footerUnderCard
                  ? BubbleText(text: _text(context, text), footer: footer)
                  : _text(context, text),
            ),
          ),
        if (card != null && !preview!.aboveText) card,
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
        if (footerUnderCard ||
            (text.isEmpty && reactions.isEmpty && !footerOnMedia))
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
    gateway: gateway,
    style: TextStyle(
      fontSize: 16,
      height: 1.3,
      color: Theme.of(context).colorScheme.onSurface,
    ),
  );
}

/// Views, "edited" and the time. A channel's post carries no read mark, as in the official
/// app: the "Unread posts" divider and the counters say what is new.
class PostFooter extends StatelessWidget {
  const PostFooter({super.key, required this.post, required this.color});
  final Post post;
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
