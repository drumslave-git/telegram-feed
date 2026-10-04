import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

/// The unread counter of a feed, a folder tab or a channel row, in the accent colour as
/// the official app draws it, never the error red, and grey for a muted channel. The
/// number is printed whole, as the official app prints it.
class UnreadBadge extends StatelessWidget {
  const UnreadBadge(this.count, {super.key, this.muted = false});

  /// How many are unread; 0 for a channel that is only marked as unread, whose counter
  /// is drawn empty, as the official app draws it.
  final int count;

  /// The channel is muted in Telegram: its counter is grey.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: count > 0
          ? context.l10n.homeUnreadBadge(count)
          : context.l10n.channelsMarkedUnread,
      child: ExcludeSemantics(
        child: Badge(
          label: Text(count > 0 ? '$count' : ' '),
          backgroundColor: muted ? scheme.outline : scheme.primary,
          textColor: muted ? scheme.surface : scheme.onPrimary,
        ),
      ),
    );
  }
}
