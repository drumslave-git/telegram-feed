import 'dart:math' as math;

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../l10n/l10n.dart';
import 'post_card.dart';

/// Height of [PinnedBar]; the floating day pill stands below it.
const pinnedBarHeight = 44.0;

/// The bar over a channel's timeline with one of its pinned posts, as in the official app:
/// a line at the left with a piece for every pinned post, the title with the post's number,
/// the post's first words, and at the right a button to the list of pinned posts, or a
/// cross that hides the bar when there is only one.
class PinnedBar extends StatelessWidget {
  const PinnedBar({
    super.key,
    required this.pins,
    required this.index,
    required this.onTap,
    required this.onHide,
    required this.onList,
  });

  /// The channel's pinned posts, newest first.
  final List<Post> pins;

  /// The one the bar shows.
  final int index;
  final VoidCallback onTap;
  final VoidCallback onHide;
  final VoidCallback onList;

  /// The title over a pinned post, as the official app words it: the newest is the pinned
  /// post, the older of two is the previous one, and the older ones of more are numbered
  /// from the oldest.
  static String titleOf(AppLocalizations l10n, int index, int total) {
    if (index <= 0) return l10n.timelinePinnedPost;
    if (total == 2) return l10n.timelinePreviousPinned;
    return l10n.timelinePinnedPostNumber(
      math.min(total - 1, math.max(1, total - index)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final at = index.clamp(0, pins.length - 1);
    final post = pins[at];
    return Material(
      // Opaque: posts used to shine through the bar and through its words.
      color: scheme.surfaceContainerHighest,
      child: SizedBox(
        height: pinnedBarHeight,
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.only(left: 12, right: 4),
                  child: Row(
                    children: [
                      _PinLine(
                        total: pins.length,
                        index: at,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              titleOf(l10n, at, pins.length),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: scheme.primary,
                              ),
                            ),
                            Text(
                              // One line: a pinned post may be a long one.
                              postLabel(
                                post,
                                l10n.mediaWords,
                              ).replaceAll(String.fromCharCode(10), ' '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: scheme.onSurfaceVariant,
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
            // Both buttons are as wide, so the words do not move when one pinned post
            // becomes several.
            if (pins.length > 1)
              IconButton(
                tooltip: l10n.timelinePinnedList,
                icon: const Icon(Icons.format_list_bulleted, size: 20),
                onPressed: onList,
              )
            else
              IconButton(
                tooltip: l10n.timelineHidePinned,
                icon: const Icon(Icons.close, size: 20),
                onPressed: onHide,
              ),
          ],
        ),
      ),
    );
  }
}

/// The line at the left of the bar: one piece per pinned post, at most three, the oldest
/// on top; the piece of the post on show is in full colour.
class _PinLine extends StatelessWidget {
  const _PinLine({
    required this.total,
    required this.index,
    required this.color,
  });
  final int total;
  final int index;
  final Color color;

  static const _height = 34.0;
  static const _gap = 2.0;

  @override
  Widget build(BuildContext context) {
    final pieces = math.min(total, 3);
    // Which piece is lit, counted from the top: the newest post is the lowest piece, the
    // oldest the highest, and with more posts than pieces every post in between is the
    // middle one.
    final lit = total <= 3
        ? total - 1 - index
        : index == 0
        ? 2
        : index == total - 1
        ? 0
        : 1;
    return SizedBox(
      width: 2,
      height: _height,
      child: Column(
        children: [
          for (var i = 0; i < pieces; i++) ...[
            if (i > 0) const SizedBox(height: _gap),
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: i == lit ? color : color.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The pinned posts of a channel, oldest on top like its timeline, as the official app
/// lists them. A tap on a post goes to it in the timeline (the screen closes with that
/// post), and the button at the bottom hides the pinned bar (it closes with `true`).
class PinnedPostsScreen extends StatelessWidget {
  const PinnedPostsScreen({
    super.key,
    required this.pins,
    required this.channelTitle,
    required this.gateway,
    this.channelPhoto,
  });

  /// Newest first.
  final List<Post> pins;
  final String channelTitle;
  final FileRef? channelPhoto;
  final TelegramGateway gateway;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.pinnedPostsTitle(pins.length))),
      backgroundColor: ChatColors.of(context).background,
      body: ListView.builder(
        reverse: true,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: pins.length,
        itemBuilder: (context, i) {
          final post = pins[i];
          return Semantics(
            button: true,
            label: l10n.pinnedPostsOpen,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(post),
              // The posts are shown, not used, here: whatever a post can do it does in
              // the timeline, one tap away.
              child: AbsorbPointer(
                child: PostCard(
                  item: TimelineItem(post),
                  channelTitle: channelTitle,
                  channelPhoto: channelPhoto,
                  gateway: gateway,
                ),
              ),
            ),
          );
        },
      ),
      // A bar of its own under the posts, as the official app's button stands.
      bottomNavigationBar: Material(
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          child: SizedBox(
            height: 48,
            child: TextButton(
              style: TextButton.styleFrom(
                shape: const RoundedRectangleBorder(),
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.pinnedPostsHide),
            ),
          ),
        ),
      ),
    );
  }
}
