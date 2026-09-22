import 'package:flutter/material.dart';

/// The unread counter of a feed, a folder tab or a channel row, drawn as the official app
/// draws it: the accent colour, never the error red, and "999+" past a thousand.
class UnreadBadge extends StatelessWidget {
  const UnreadBadge(this.count, {super.key});
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '$count unread',
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
