import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

/// The unread counter of a feed, a folder tab or a channel row, in the accent colour as
/// the official app draws it, never the error red. Past a thousand it says "999+", where
/// the official app prints the whole number.
class UnreadBadge extends StatelessWidget {
  const UnreadBadge(this.count, {super.key});
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: context.l10n.homeUnreadBadge(count),
      child: ExcludeSemantics(
        child: Badge(
          label: Text(count > 999 ? '999+' : '$count'),
          backgroundColor: scheme.primary,
          textColor: scheme.onPrimary,
        ),
      ),
    );
  }
}
