import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../home/channel_list.dart' show ChannelAvatar;
import '../l10n/l10n.dart';
import '../media/media_viewer.dart';
import 'album_layout.dart';
import 'bubble_text.dart';
import 'formatted_text.dart';
import 'link_preview.dart';
import 'media_view.dart';
import 'post_menu.dart';
import 'reaction_glyph.dart';
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
      // Dark enough for white letters on the light backdrop as well.
      pill: Colors.black.withValues(alpha: dark ? 0.45 : 0.45),
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
  const ChatPill(this.label, {super.key, this.onTap, this.tapLabel});
  final String label;

  /// Day pills lead to the calendar and the line of a pin to the pinned post; the other
  /// pills are labels only.
  final VoidCallback? onTap;

  /// What a screen reader says of a pill that can be tapped; a day pill's words when null.
  final String? tapLabel;

  @override
  Widget build(BuildContext context) {
    final colors = ChatColors.of(context);
    final pill = Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      constraints: const BoxConstraints(minHeight: 32),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
          ? Semantics(header: true, child: pill)
          : Semantics(
              button: true,
              label: tapLabel ?? context.l10n.postDayJumpToDate(label),
              child: GestureDetector(
                onTap: onTap,
                behavior: HitTestBehavior.opaque,
                child: pill,
              ),
            ),
    );
  }
}

/// What a double tap sends until the reader picks another quick reaction in Chat settings.
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
    this.onDelete,
    this.onReact,
    this.availableReactions,
    this.onOpenThread,
    this.onOpenLink,
    this.onOpenHashtag,
    this.onAutoplaySettings,
    this.onOpenForward,
    this.onOpenReply,
    this.onOpenChannel,
    this.onQuickReact,
    this.justReacted,
    this.reactions,
    this.onSelect,
    this.onSelectStart,
    this.onSelectDrag,
    this.onMinimize,
    this.selecting = false,
    this.selected = false,
    this.onViewerMedia,
    this.onMoreViewerMedia,
    this.onViewerDetails,
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

  /// Deletes the post; only in Saved Messages.
  final VoidCallback? onDelete;

  /// Tap on a reaction: adds it, or removes it when already chosen.
  final void Function(String emoji, bool remove)? onReact;

  /// Emoji the account may react with; asked when the menu opens.
  final Future<List<String>> Function()? availableReactions;
  final VoidCallback? onOpenThread;

  /// Tap on a link, a mention or an e-mail address in the text.
  final void Function(String url)? onOpenLink;

  /// A tap on a hashtag in the text: the timeline searches for it.
  final void Function(String tag)? onOpenHashtag;

  /// Menu entry of posts with a video: the autoplay switch and limits.
  final VoidCallback? onAutoplaySettings;

  /// Tap on the "Forwarded from" line: opens the original post where the app can.
  final VoidCallback? onOpenForward;

  /// The emoji the reader has just reacted with: its pill pops once.
  final String? justReacted;

  /// Tap on the quote block: jumps to the post this one answers.
  final VoidCallback? onOpenReply;

  /// The reactions to draw instead of the post's own: the reader's tap, shown before
  /// Telegram confirms it.
  final List<Reaction>? reactions;

  /// A tap on the channel's name or photo: its info. Set in a feed, where posts of several
  /// channels mix; a channel's own timeline has its info in the app bar.
  final VoidCallback? onOpenChannel;

  /// Double tap on the bubble: sends the quick reaction, as the official app does.
  final VoidCallback? onQuickReact;

  /// Every tap while the timeline is selecting: picks the row, or lets it go.
  final VoidCallback? onSelect;

  /// A long press: the timeline starts selecting with this row, as in the official app.
  final VoidCallback? onSelectStart;

  /// The finger of that long press moved, to this point of the screen: the rows it passes
  /// are picked too.
  final void Function(Offset at)? onSelectDrag;

  /// "Minimize" in the menu of a post the feed's filter leaves out, opened from its line:
  /// folds it into that line again.
  final VoidCallback? onMinimize;

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

  /// Saving from inside the viewer, by the index of the picture.
  final void Function(int index)? onViewerSave;

  bool get _hasMenu =>
      onOpenInTelegram != null ||
      onShare != null ||
      onCopyLink != null ||
      onCopyText != null ||
      onMinimize != null ||
      onSave != null ||
      onDelete != null ||
      availableReactions != null;

  /// The menu, where the post was touched: the reactions in a strip of their own, the
  /// lines under it.
  Future<void> _menu(BuildContext context, Offset at) async {
    final l10n = context.l10n;
    final protected = item.isProtected;
    final action = await showPostMenu(
      context,
      at: at,
      strip: availableReactions == null || onReact == null
          ? null
          : (close) => _ReactionStrip(
              load: availableReactions!,
              gateway: gateway,
              chosen: {
                for (final r in reactions ?? item.reactionPost.reactions)
                  if (r.chosen) r.emoji,
              },
              onPick: (emoji, remove) => close(() => onReact!(emoji, remove)),
            ),
      entries: [
        if (onOpenThread != null)
          PostMenuEntry(
            icon: Icons.forum_outlined,
            label: l10n.commonComments,
            onSelected: onOpenThread,
          ),
        if (onCopyText != null && item.text.isNotEmpty && !protected)
          PostMenuEntry(
            icon: Icons.content_copy,
            label: l10n.postCopyText,
            onSelected: onCopyText,
          ),
        if (onCopyLink != null)
          PostMenuEntry(
            icon: Icons.link,
            label: l10n.commonCopyLink,
            onSelected: onCopyLink,
          ),
        if (onShare != null && !protected)
          PostMenuEntry(
            icon: Icons.share_outlined,
            label: l10n.commonShare,
            onSelected: onShare,
          ),
        if (onSave != null && !protected)
          PostMenuEntry(
            icon: Icons.bookmark_add_outlined,
            label: l10n.postSaveToSavedMessages,
            onSelected: onSave,
          ),
        if (onMinimize != null)
          PostMenuEntry(
            icon: Icons.unfold_less,
            label: l10n.postMinimize,
            onSelected: onMinimize,
          ),
        if (onAutoplaySettings != null &&
            item.allPosts.any((p) => p.media is VideoMedia))
          PostMenuEntry(
            icon: Icons.play_circle_outline,
            label: l10n.postAutoplaySettings,
            onSelected: onAutoplaySettings,
          ),
        // In the error colour, as the official app draws Delete.
        if (onDelete != null)
          PostMenuEntry(
            icon: Icons.delete_outline,
            label: l10n.commonDelete,
            onSelected: onDelete,
            destructive: true,
          ),
        // Why Copy, Share and Save are missing, in the official app's words.
        if (protected)
          PostMenuEntry(icon: Icons.lock_outline, label: l10n.postProtected),
        // Last, behind a line: it leaves the app, and it is the rarest of them.
        if (onOpenInTelegram != null)
          PostMenuEntry(
            icon: Icons.open_in_new,
            label: l10n.commonOpenInTelegram,
            onSelected: onOpenInTelegram,
            dividerAbove: true,
          ),
      ],
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
      onOpenHashtag: onOpenHashtag,
      onOpenForward: onOpenForward,
      onOpenReply: onOpenReply,
      onOpenChannel: selecting ? null : onOpenChannel,
      reactions: reactions ?? item.reactionPost.reactions,
      justReacted: justReacted,
      onQuickReact: onQuickReact,
      onViewerMedia: onViewerMedia,
      onMoreViewerMedia: onMoreViewerMedia,
      onViewerDetails: onViewerDetails,
      onViewerSave: onViewerSave,
    );
    // The bubble has the row to itself: the channel's photo sits in its title line and
    // sharing is in the menu, so nothing beside it takes width from text and pictures.
    final buttons = item.allPosts
        .map((p) => p.buttons)
        .firstWhere((b) => b.isNotEmpty, orElse: () => const []);
    final card = Padding(
      padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: colors.bubble,
            elevation: 0.5,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(14)),
            ),
            clipBehavior: Clip.antiAlias,
            // A tap opens the menu where it landed, as in the official app; two taps in
            // a row send the quick reaction instead, so the menu waits a moment for the
            // second one.
            child: _BubbleTaps(
              onMenu: _hasMenu && !selecting
                  ? (at) => _menu(context, at)
                  : null,
              onDoubleTap: selecting ? null : onQuickReact,
              // Every bubble takes the whole row, whatever it holds, so the posts line up.
              child: SizedBox(width: double.infinity, child: bubble),
            ),
          ),
          if (buttons.isNotEmpty)
            PostButtons(rows: buttons, onOpenLink: onOpenLink),
        ],
      ),
    );
    final scheme = Theme.of(context).colorScheme;
    // One detector for both states of the row, so that the long press that starts the
    // selection is still the one being followed when the row has become a selectable one:
    // its drag picks the rows the finger passes.
    return Semantics(
      selected: selecting ? selected : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // While the timeline selects, the row answers nothing but the tap that picks it.
        onTap: selecting ? onSelect : null,
        onLongPressStart: onSelectStart == null
            ? null
            : (_) => onSelectStart!(),
        onLongPressMoveUpdate: onSelectDrag == null
            ? null
            : (d) => onSelectDrag!(d.globalPosition),
        child: !selecting
            ? card
            // The check sits in a gutter on the left, as the official app does, so it
            // never lies on the words or the picture it belongs to.
            : ColoredBox(
                color: selected
                    ? scheme.primary.withValues(alpha: 0.12)
                    : Colors.transparent,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(
                        selected
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: scheme.primary,
                      ),
                    ),
                    Expanded(child: IgnorePointer(child: card)),
                  ],
                ),
              ),
      ),
    );
  }
}

/// The link buttons a channel puts under a post, as the official app draws them: rows of
/// see-through dark buttons as wide as the bubble, each with the arrow of a link in its
/// corner. A tap asks before it opens the link, since the button does not show where it
/// leads; a link into Telegram opens at once.
class PostButtons extends StatelessWidget {
  const PostButtons({super.key, required this.rows, required this.onOpenLink});
  final List<List<UrlButton>> rows;
  final void Function(String url)? onOpenLink;

  Future<void> _open(BuildContext context, UrlButton button) async {
    final open = onOpenLink;
    if (open == null) return;
    if (!FormattedTextState.hidesTarget(button.url, button.text)) {
      return open(button.url);
    }
    if (await confirmOpenLink(context, button.url)) open(button.url);
  }

  @override
  Widget build(BuildContext context) {
    final colors = ChatColors.of(context);
    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, button) in row.indexed) ...[
                    if (i > 0) const SizedBox(width: 3),
                    Expanded(
                      child: Semantics(
                        button: true,
                        link: true,
                        child: Material(
                          color: colors.pill,
                          borderRadius: BorderRadius.circular(8),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: onOpenLink == null
                                ? null
                                : () => unawaited(_open(context, button)),
                            child: Stack(
                              children: [
                                Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 11,
                                    ),
                                    child: Text(
                                      button.text,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: colors.onPill,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: Icon(
                                    Icons.north_east,
                                    size: 11,
                                    color: colors.onPill,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// The taps on a bubble: one opens the menu at the point it landed, two in a row send the
/// quick reaction. The menu waits for the time a second tap may take, as the official app
/// does when a quick reaction is set; links, pictures, pills and the comments bar inside
/// the bubble answer their own taps at once and never come here.
class _BubbleTaps extends StatefulWidget {
  const _BubbleTaps({
    required this.onMenu,
    required this.onDoubleTap,
    required this.child,
  });
  final void Function(Offset at)? onMenu;
  final VoidCallback? onDoubleTap;
  final Widget child;

  @override
  State<_BubbleTaps> createState() => _BubbleTapsState();
}

class _BubbleTapsState extends State<_BubbleTaps> {
  /// How long a second tap may take, Android's double-tap timeout.
  static const _window = Duration(milliseconds: 300);
  static const _slop = 48.0;
  Offset _at = Offset.zero;
  Offset? _first;
  Timer? _pending;

  @override
  void dispose() {
    _pending?.cancel();
    super.dispose();
  }

  void _onTap() {
    final at = _at;
    final menu = widget.onMenu;
    final twice = widget.onDoubleTap;
    if (twice == null) {
      menu?.call(at);
      return;
    }
    final first = _first;
    if (_pending != null && first != null && (at - first).distance < _slop) {
      _pending!.cancel();
      _pending = null;
      _first = null;
      twice();
      return;
    }
    _pending?.cancel();
    _first = at;
    _pending = Timer(_window, () {
      _pending = null;
      _first = null;
      if (mounted) menu?.call(at);
    });
  }

  @override
  Widget build(BuildContext context) =>
      widget.onMenu == null && widget.onDoubleTap == null
      ? widget.child
      : InkWell(
          onTapUp: (d) => _at = d.globalPosition,
          onTap: _onTap,
          child: widget.child,
        );
}

/// A post the feed's filter leaves out, in a feed that shows such posts minimized: a slim
/// bubble of one line with the channel's name in its colour, the beginning of the words
/// (or what the post carries) and the time. A tap opens the whole post in its place.
class MinimizedPost extends StatelessWidget {
  const MinimizedPost({
    super.key,
    required this.item,
    required this.channelTitle,
    this.onOpen,
  });
  final TimelineItem item;
  final String channelTitle;

  /// Opens the post; null while the timeline selects, where this row takes no part.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = ChatColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final l10n = context.l10n;
    final words = postLabel(
      item.textPost,
      l10n.mediaWords,
    ).replaceAll(RegExp(r'\s+'), ' ').trim();
    final time = formatTime(
      DateTime.fromMillisecondsSinceEpoch(item.head.date * 1000),
      context,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
      child: Material(
        color: colors.bubble,
        elevation: 0.5,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Semantics(
          button: onOpen != null,
          label: l10n.postMinimizedSemantics(channelTitle, words, time),
          excludeSemantics: true,
          child: InkWell(
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
              child: Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: channelTitle,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: peerColor(item.chatId, scheme.brightness),
                            ),
                          ),
                          const TextSpan(text: '  '),
                          TextSpan(
                            text: words,
                            style: TextStyle(color: muted),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(time, style: TextStyle(fontSize: 12, color: muted)),
                  const SizedBox(width: 4),
                  Icon(Icons.unfold_more, size: 16, color: muted),
                ],
              ),
            ),
          ),
        ),
      ),
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
    this.onTap,
  });
  final String name;

  /// Opens the channel's info; null where the name only labels the post.
  final VoidCallback? onTap;

  /// Chat or user id; picks the colour of the name ([peerColor]).
  final int colorId;
  final FileRef? photo;
  final TelegramGateway gateway;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: peerColor(
                colorId,
                Theme.of(context).colorScheme.brightness,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        ChannelAvatar(photo: photo, title: name, gateway: gateway, radius: 12),
      ],
    );
    final tap = onTap;
    if (tap == null) return row;
    return Semantics(
      button: true,
      label: context.l10n.postChannelInfoOf(name),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: tap,
        child: row,
      ),
    );
  }
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
    final l10n = context.l10n;
    final name = origin.title.isEmpty ? l10n.postHiddenAccount : origin.title;
    // The words around the name, wherever the language puts it; the name itself is bold.
    const mark = '\u0000';
    final around = l10n.postForwardedFrom(mark).split(mark);
    final row = Text.rich(
      TextSpan(
        children: [
          if (around.first.isNotEmpty) TextSpan(text: around.first),
          TextSpan(
            text: name,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (around.length > 1 && around.last.isNotEmpty)
            TextSpan(text: around.last),
          if (origin.signature.isNotEmpty)
            TextSpan(text: ' (${origin.signature})'),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 13,
        // The accent colour where the original can be opened, as in the official app:
        // a grey line looks like a label and hides that it leads somewhere.
        color: onTap == null ? scheme.onSurfaceVariant : scheme.primary,
      ),
    );
    return onTap == null
        ? row
        : Semantics(
            button: true,
            label: l10n.postForwardedFromOpen(name),
            child: GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: row,
            ),
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
    final l10n = context.l10n;
    final accent = peerColor(colorId, scheme.brightness);
    final name = reply.title.isEmpty ? channelTitle : reply.title;
    final photo = reply.photo;
    // What the answered post said, else what it carried, else that it was a post.
    final said = reply.text.isEmpty
        ? l10n.mediaPreview(reply.media, channel: name)
        : reply.text;
    final block = Material(
      color: accent.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: onTap != null,
        label: onTap == null
            ? l10n.postInReplyTo(name)
            : l10n.postInReplyToOpen(name),
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
                        said.isEmpty ? l10n.mediaPost : said,
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
    required this.onOpenHashtag,
    required this.onOpenForward,
    required this.onOpenReply,
    required this.onOpenChannel,
    required this.reactions,
    required this.onQuickReact,
    this.justReacted,
    required this.onViewerMedia,
    required this.onMoreViewerMedia,
    required this.onViewerDetails,
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
  final void Function(String tag)? onOpenHashtag;
  final VoidCallback? onOpenForward;
  final VoidCallback? onOpenReply;
  final VoidCallback? onOpenChannel;
  final List<Reaction> reactions;
  final VoidCallback? onQuickReact;
  final String? justReacted;
  final List<Media> Function()? onViewerMedia;
  final Future<List<Media>> Function()? onMoreViewerMedia;
  final List<ViewerDetail> Function()? onViewerDetails;
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
    final text = item.text;
    // Only a text post carries a link preview, so it never belongs to an album.
    final preview = item.textPost.linkPreview;
    // The author put the words over the picture: they come first, and the picture is the
    // last thing in the bubble.
    final captionAbove =
        item.textPost.captionAbove && text.isNotEmpty && visual.isNotEmpty;
    // Nothing under the pictures: the footer goes on top of them, as in Telegram.
    final footerOnMedia =
        (text.isEmpty || captionAbove) &&
        reactions.isEmpty &&
        other.isEmpty &&
        visual.isNotEmpty;
    final footer = PostFooter(
      post: item.head,
      color: footerOnMedia ? Colors.white : scheme.onSurfaceVariant,
    );

    void open(Media m) {
      // The viewer pages through the media of the whole timeline when it can (H-21), so
      // this post's album is only where it starts.
      final around = onViewerMedia?.call();
      final whole = around != null && around.contains(m);
      final items = whole ? around : visual;
      MediaViewerScreen.open(
        context,
        items: items,
        gateway: gateway,
        initialIndex: items.indexOf(m),
        onNeedOlder: whole ? onMoreViewerMedia : null,
        newestFirst: whole,
        details: whole ? onViewerDetails?.call() ?? const [] : const [],
        onDetails: whole ? onViewerDetails : null,
        onSave: whole ? onViewerSave : null,
      );
    }

    // The post this picture belongs to and its place in it: the viewer works the same
    // name out from the details it is handed, so the picture flies between them.
    final postKey = '${item.chatId}:${item.head.messageId}';
    Widget? pictures;
    if (visual.length == 1) {
      pictures = MediaView(
        media: visual.single,
        gateway: gateway,
        radius: 0,
        onOpen: () => open(visual.single),
        heroTag: mediaHeroTag(postKey, 0),
      );
    } else if (visual.length > 1) {
      pictures = AlbumMosaic(
        media: visual,
        gateway: gateway,
        onOpen: open,
        heroTagOf: (i) => mediaHeroTag(postKey, i),
      );
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

    /// The quick reaction is sent by a double tap. On the words and the rest of the bubble
    /// the taps are counted by `_BubbleTaps`, which also opens the menu. The pictures of a
    /// post without words take a recognizer of their own: a picture answers its own tap,
    /// and without the recognizer the first tap would open the viewer before the second
    /// one could arrive.
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
            onTap: onOpenChannel,
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
        if (captionAbove)
          Padding(
            padding: const EdgeInsets.fromLTRB(_side, 0, _side, 6),
            child: _text(context, text),
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
        // Room under a picture that ends the bubble with reactions after it.
        if (captionAbove && !footerOnMedia) const SizedBox(height: 4),
        for (final m in other)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _side),
            child: MediaView(media: m, gateway: gateway),
          ),
        if (card != null && preview!.aboveText) card,
        if (text.isNotEmpty && !captionAbove)
          Padding(
            padding: const EdgeInsets.fromLTRB(_side, 6, _side, 6),
            child: reactions.isEmpty && !footerUnderCard
                ? BubbleText(text: _text(context, text), footer: footer)
                : _text(context, text),
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
                        gateway: gateway,
                        pop: r.emoji == justReacted,
                        // The paid reaction costs Stars: it is shown, not sent.
                        onTap: onReact == null || r.emoji == paidReaction
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
          CommentsBar(
            count: item.threadPost.replyCount,
            commenters: item.threadPost.recentCommenters,
            unread: item.threadPost.hasUnreadComments,
            gateway: gateway,
            onTap: onOpenThread!,
          ),
      ],
    );
  }

  /// The post's own words, at the reader's text size. The footer, the reaction pills and
  /// the comments bar keep the size of the rest of the app, as in the official one.
  Widget _text(BuildContext context, String text) => PostTextScale.wrap(
    context,
    FormattedText(
      text: text,
      entities: item.textPost.entities,
      onOpenLink: onOpenLink,
      onOpenHashtag: onOpenHashtag,
      gateway: gateway,
      canCopy: !item.isProtected,
      style: TextStyle(
        fontSize: emojiOnlySize(text, item.textPost.entities) ?? 16,
        height: 1.3,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    ),
  );
}

final _emojiGrapheme = RegExp(
  r'^(?:\p{Extended_Pictographic}|\p{Regional_Indicator}|[0-9#*]\uFE0F?\u20E3)',
  unicode: true,
);

/// How many emoji a text consists of when it consists of nothing else (white space
/// aside); 0 for any other text.
int emojiOnlyCount(String text) {
  var count = 0;
  for (final grapheme in text.characters) {
    if (grapheme.trim().isEmpty) continue;
    if (!_emojiGrapheme.hasMatch(grapheme)) return 0;
    count++;
  }
  return count;
}

/// The size a post of nothing but emoji is drawn at, as the official app sizes it: the
/// fewer there are the larger they get, and custom emoji alone get larger still. Null
/// for a post with words, or with formatting other than custom emoji.
double? emojiOnlySize(String text, List<TextEntity> entities) {
  final count = emojiOnlyCount(text);
  if (count == 0) return null;
  if (entities.any((e) => e.kind != TextEntityKind.customEmoji)) return null;
  // The official sizes, in steps: shares of 120 dp.
  const sizes = [81.6, 55.2, 40.8, 33.6, 26.4, 22.8];
  final custom = entities.length == count;
  final step = switch (count) {
    1 || 2 => custom ? 0 : 2,
    3 => custom ? 1 : 3,
    4 => custom ? 2 : 4,
    5 => custom ? 3 : 5,
    6 => custom ? 4 : 5,
    _ => 5,
  };
  return sizes[step];
}

/// The pin of a pinned post, views, the author's signature, "edited" and the time. A channel's post carries no read mark, as in the official
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
        if (post.isPinned) ...[
          Icon(
            Icons.push_pin,
            size: 13,
            color: color,
            semanticLabel: context.l10n.postPinned,
          ),
          const SizedBox(width: 4),
        ],
        if (post.views > 0) ...[
          Icon(Icons.visibility_outlined, size: 14, color: color),
          const SizedBox(width: 3),
          Text(formatCount(post.views), style: style),
          const SizedBox(width: 6),
        ],
        // A long name gives way: the time is always all there.
        if (post.signature.isNotEmpty)
          Flexible(
            child: Text(
              '${post.signature}, ',
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (post.editDate > 0) ...[
          Text(context.l10n.postEdited, style: style),
          const SizedBox(width: 4),
        ],
        Text(formatTime(date, context), style: style),
      ],
    );
  }
}

/// A reaction with its count, filled when this account chose it.
class ReactionPill extends StatelessWidget {
  const ReactionPill({
    super.key,
    required this.reaction,
    this.onTap,
    this.gateway,
    this.pop = false,
  });
  final Reaction reaction;
  final VoidCallback? onTap;

  /// The reader has just set this reaction: the pill swells and settles, once.
  final bool pop;

  /// Loads the sticker of a custom-emoji reaction.
  final TelegramGateway? gateway;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chosen = reaction.chosen;
    // An emoji is a character of the pill's text; a custom emoji and the star are drawn.
    final plain =
        reaction.emoji != paidReaction &&
        customReactionId(reaction.emoji) == null;
    final style = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: chosen ? scheme.onPrimary : scheme.primary,
    );
    // A painted box and a tap, not a Material with an ink well: a post can carry a dozen
    // pills and a screen several posts, and each Material brings focus, hover, ink and
    // semantics layers that make a new row slow to build while the list scrolls.
    final pill = DecoratedBox(
      decoration: BoxDecoration(
        color: chosen ? scheme.primary : scheme.primary.withValues(alpha: 0.12),
        borderRadius: const BorderRadius.all(Radius.circular(14)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 32),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: plain
              ? Text(
                  '${reaction.emoji} ${formatCount(reaction.count)}',
                  softWrap: false,
                  style: style,
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ReactionGlyph(
                      reaction.emoji,
                      size: 13,
                      gateway: gateway,
                      color: chosen ? scheme.onPrimary : null,
                    ),
                    Text(
                      ' ${formatCount(reaction.count)}',
                      softWrap: false,
                      style: style,
                    ),
                  ],
                ),
        ),
      ),
    );
    final tap = onTap;
    if (tap == null) return pill;
    final shown = pop ? ReactionPop(child: pill) : pill;
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: tap,
        behavior: HitTestBehavior.opaque,
        child: shown,
      ),
    );
  }
}

/// The bar under a post that opens its comments, as the official app draws it: the photos
/// of up to three people who commented last (the bubbles icon when there are none), the
/// exact number of comments, and a dot when there are comments the reader has not seen.
class CommentsBar extends StatelessWidget {
  const CommentsBar({
    super.key,
    required this.count,
    required this.onTap,
    required this.gateway,
    this.commenters = const [],
    this.unread = false,
  });
  final int count;
  final List<Commenter> commenters;
  final bool unread;
  final TelegramGateway gateway;
  final VoidCallback onTap;

  static const _avatar = 12.0;

  /// How far each photo covers the one before it.
  static const _overlap = 7.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final bubble = ChatColors.of(context).bubble;
    final faces = count == 0
        ? const <Commenter>[]
        : commenters.take(3).toList();
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
                if (faces.isEmpty)
                  Icon(Icons.forum_outlined, size: 18, color: scheme.primary)
                else
                  // The first is the newest and lies on top, as in the official app.
                  ExcludeSemantics(
                    child: SizedBox(
                      width:
                          2 * _avatar +
                          (faces.length - 1) * (2 * _avatar - _overlap) +
                          3,
                      height: 2 * _avatar + 3,
                      child: Stack(
                        children: [
                          for (var i = faces.length - 1; i >= 0; i--)
                            Positioned(
                              left: i * (2 * _avatar - _overlap),
                              top: 0,
                              // A rim in the bubble's colour parts the photos.
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: bubble,
                                  shape: BoxShape.circle,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(1.5),
                                  child: ChannelAvatar(
                                    photo: faces[i].photo,
                                    title: faces[i].name,
                                    gateway: gateway,
                                    colorId: faces[i].id,
                                    radius: _avatar,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                // The words and their dot keep together at the left; the arrow has the
                // right edge.
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          count > 0
                              ? l10n.postCommentCount(count, '$count')
                              : l10n.postLeaveComment,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                      if (unread && count > 0) ...[
                        const SizedBox(width: 6),
                        Semantics(
                          label: l10n.postCommentsUnread,
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    ],
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
    required this.gateway,
  });
  final Future<List<String>> Function() load;
  final TelegramGateway gateway;
  final Set<String> chosen;
  final void Function(String emoji, bool remove) onPick;

  @override
  State<_ReactionStrip> createState() => _ReactionStripState();
}

class _ReactionStripState extends State<_ReactionStrip> {
  late final Future<List<String>> _emoji = widget.load();

  /// The arrow was tapped: the strip has become the panel of all reactions.
  bool _all = false;

  static const _cell = 38.0;

  /// How many cells fit in the strip, the arrow among them.
  static const _shown = 6;

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
                ? context.l10n.postReactionsLoadFailed
                : context.l10n.postReactionsNotAllowed,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        );
      }
      Widget cell(String e) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 6),
        child: Material(
          color: widget.chosen.contains(e)
              ? scheme.primaryContainer
              : Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => widget.onPick(e, widget.chosen.contains(e)),
            child: SizedBox.square(
              dimension: _cell,
              child: Center(
                child: ReactionGlyph(e, size: 26, gateway: widget.gateway),
              ),
            ),
          ),
        ),
      );
      if (_all) {
        // Every reaction the channel allows, in rows; more than five rows scroll.
        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 5 * (_cell + 12) + 8),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Wrap(children: [for (final e in emoji) cell(e)]),
          ),
        );
      }
      // The first few, and the arrow that opens the rest, as in the official app.
      final few = emoji.length > _shown ? emoji.take(_shown - 1) : emoji;
      return SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              for (final e in few) cell(e),
              if (emoji.length > few.length)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 1,
                    vertical: 6,
                  ),
                  child: Material(
                    color: scheme.surfaceContainerHighest,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => setState(() => _all = true),
                      child: SizedBox.square(
                        dimension: _cell,
                        child: Icon(
                          Icons.expand_more,
                          semanticLabel: context.l10n.postReactionsAll,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// Lets a reaction pill swell and settle once, when the reader has just set it.
class ReactionPop extends StatefulWidget {
  const ReactionPop({super.key, required this.child});
  final Widget child;

  @override
  State<ReactionPop> createState() => _ReactionPopState();
}

class _ReactionPopState extends State<ReactionPop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  )..forward();
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.3,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 40,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.3,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeIn)),
      weight: 60,
    ),
  ]).animate(_pop);

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ScaleTransition(scale: _scale, child: widget.child);
}

/// The reactions Telegram offers everywhere, in its own order: what the quick reaction is
/// chosen from.
const standardReactions = [
  '👍',
  '👎',
  '❤',
  '🔥',
  '🥰',
  '👏',
  '😁',
  '🤔',
  '🤯',
  '😱',
  '🤬',
  '😢',
  '🎉',
  '🤩',
  '🤮',
  '💩',
  '🙏',
  '👌',
  '🕊',
  '🤡',
  '🥱',
  '🥴',
  '😍',
  '🐳',
  '❤‍🔥',
  '🌚',
  '🌭',
  '💯',
  '🤣',
  '⚡',
  '🍌',
  '🏆',
  '💔',
  '🤨',
  '😐',
  '🍓',
  '🍾',
  '💋',
  '🖕',
  '😈',
  '😴',
  '😭',
  '🤓',
  '👻',
  '👨‍💻',
  '👀',
  '🎃',
  '🙈',
  '😇',
  '😨',
  '🤝',
  '✍',
  '🤗',
  '🫡',
  '🎅',
  '🎄',
  '☃',
  '💅',
  '🤪',
  '🗿',
  '🆒',
  '💘',
  '🙉',
  '🦄',
  '😘',
  '💊',
  '🙊',
  '😎',
  '👾',
  '🤷‍♂',
  '🤷',
  '🤷‍♀',
  '😡',
];

/// The photos and videos of an album in Telegram's mosaic ([layoutAlbum]).
class AlbumMosaic extends StatelessWidget {
  const AlbumMosaic({
    super.key,
    required this.media,
    required this.gateway,
    required this.onOpen,
    this.heroTagOf,
  });
  final List<Media> media;
  final TelegramGateway gateway;
  final void Function(Media media) onOpen;

  /// The name the cell at that place flies under into the viewer ([mediaHeroTag]).
  final String? Function(int index)? heroTagOf;

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
                  heroTag: heroTagOf?.call(i),
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
  // The official app's `formatShortNumber`: thousands become K and millions M, with one
  // decimal that is cut off, never rounded up, and left out when it is zero.
  if (n < 1000) return '$n';
  final unit = n >= 1000000 ? 'M' : 'K';
  final whole = n >= 1000000 ? n ~/ 1000000 : n ~/ 1000;
  final tenth = n >= 1000000 ? n % 1000000 ~/ 100000 : n % 1000 ~/ 100;
  return tenth == 0 ? '$whole$unit' : '$whole.$tenth$unit';
}

/// The phone's own clock: a reader who set 12 hours sees "7:09 PM", one who set 24
/// sees "19:09". Without a context (a pure unit test) it is the 24-hour form.
String formatTime(DateTime d, [BuildContext? context]) {
  final l10n = context == null
      ? null
      : Localizations.of<MaterialLocalizations>(context, MaterialLocalizations);
  if (l10n != null) {
    return l10n.formatTimeOfDay(
      TimeOfDay.fromDateTime(d),
      alwaysUse24HourFormat:
          MediaQuery.maybeOf(context!)?.alwaysUse24HourFormat ?? true,
    );
  }
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// The label between two days of a chat: Today, Yesterday, September 17, March 3, 2025,
/// in the language of [l10n]; English without it.
String formatDay(DateTime d, {DateTime? now, AppLocalizations? l10n}) {
  final words = l10n ?? _english;
  final n = now ?? DateTime.now();
  final day = DateTime(d.year, d.month, d.day);
  // Rounded: a day with a clock change is 23 or 25 hours long.
  final days = (DateTime(n.year, n.month, n.day).difference(day).inHours / 24)
      .round();
  if (days == 0) return words.postDayToday;
  if (days == 1) return words.postDayYesterday;
  final pattern = d.year == n.year
      ? words.postDayPattern
      : words.postDayYearPattern;
  // English is en_US, the one locale intl knows before the app's localizations load the
  // names of the months: a widget test on a bare MaterialApp formats days too.
  final locale = words.localeName == 'en' ? 'en_US' : words.localeName;
  return DateFormat(pattern, locale).format(d);
}

/// The day on a separator between posts and on the floating date, as the official app
/// writes it (`LocaleController.formatDateChat`): "October 3", with the year once the day
/// is a year or more away. It never says "Today" or "Yesterday".
String formatChatDay(DateTime d, {DateTime? now, AppLocalizations? l10n}) {
  final words = l10n ?? _english;
  final n = now ?? DateTime.now();
  final near = n.difference(d).abs() < const Duration(days: 365);
  final locale = words.localeName == 'en' ? 'en_US' : words.localeName;
  return DateFormat(
    near ? words.postDayPattern : words.postDayYearPattern,
    locale,
  ).format(d);
}

final AppLocalizations _english = lookupAppLocalizations(const Locale('en'));
