import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

/// The unread counter of a feed, a folder tab or a channel row, in the accent colour as
/// the official app draws it, never the error red, and grey for a muted channel. The
/// number is printed whole, as the official app prints it.
class UnreadBadge extends StatelessWidget {
  const UnreadBadge(this.count, {super.key, this.muted = false});
  final int count;

  /// The channel is muted in Telegram: its counter is grey.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: context.l10n.homeUnreadBadge(count),
      child: ExcludeSemantics(
        child: Badge(
          label: Text('$count'),
          backgroundColor: muted ? scheme.outline : scheme.primary,
          textColor: muted ? scheme.surface : scheme.onPrimary,
        ),
      ),
    );
  }
}
