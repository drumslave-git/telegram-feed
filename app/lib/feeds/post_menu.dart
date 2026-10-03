import 'package:flutter/material.dart';

/// One line of a post's menu.
class PostMenuEntry {
  const PostMenuEntry({
    required this.icon,
    required this.label,
    this.onSelected,
    this.destructive = false,
    this.dividerAbove = false,
  });
  final IconData icon;
  final String label;

  /// Null for a line that only says something (why Copy and Share are missing).
  final VoidCallback? onSelected;

  /// Drawn in the error colour, as the official app draws Delete.
  final bool destructive;

  /// Set apart from the lines above it.
  final bool dividerAbove;
}

/// Opens a post's menu the way the official app does: a popup at the point that was
/// touched, over a dimmed screen, with the reactions in a strip of their own above the
/// lines. Completes with the chosen line's action, or null when the menu was dismissed.
///
/// [strip] is given a callback that closes the menu with an action of its own (a reaction
/// that was picked).
Future<VoidCallback?> showPostMenu(
  BuildContext context, {
  required Offset at,
  required List<PostMenuEntry> entries,
  Widget Function(void Function(VoidCallback action) close)? strip,
}) => showGeneralDialog<VoidCallback>(
  context: context,
  barrierDismissible: true,
  barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
  barrierColor: Colors.black26,
  transitionDuration: const Duration(milliseconds: 150),
  pageBuilder: (context, _, _) => SafeArea(
    child: CustomSingleChildLayout(
      delegate: _AtPoint(at, MediaQuery.paddingOf(context)),
      child: _PostMenu(entries: entries, strip: strip),
    ),
  ),
  transitionBuilder: (context, animation, _, child) => FadeTransition(
    opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
    child: child,
  ),
);

/// Puts the menu where the finger was: its top at that height and the point inside its
/// width, moved up and sideways as far as it takes to stay on the screen.
class _AtPoint extends SingleChildLayoutDelegate {
  _AtPoint(this.at, this.padding);
  final Offset at;
  final EdgeInsets padding;

  static const _margin = 8.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(
        Size(
          constraints.maxWidth - 2 * _margin,
          constraints.maxHeight - 2 * _margin,
        ),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    // The layout is inside the safe area; the touch was measured on the whole screen.
    final local = at - Offset(padding.left, padding.top);
    final left = (local.dx - childSize.width / 2).clamp(
      _margin,
      (size.width - childSize.width - _margin).clamp(_margin, double.infinity),
    );
    final top = local.dy.clamp(
      _margin,
      (size.height - childSize.height - _margin).clamp(
        _margin,
        double.infinity,
      ),
    );
    return Offset(left, top);
  }

  @override
  bool shouldRelayout(_AtPoint old) => old.at != at || old.padding != padding;
}

class _PostMenu extends StatelessWidget {
  const _PostMenu({required this.entries, required this.strip});
  final List<PostMenuEntry> entries;
  final Widget Function(void Function(VoidCallback action) close)? strip;

  static const _width = 260.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    void close(VoidCallback action) => Navigator.pop(context, action);
    return SizedBox(
      width: _width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (strip != null) ...[
            Material(
              color: scheme.surfaceContainerHigh,
              elevation: 6,
              shape: const StadiumBorder(),
              clipBehavior: Clip.antiAlias,
              child: strip!(close),
            ),
            const SizedBox(height: 6),
          ],
          Flexible(
            child: Material(
              color: scheme.surfaceContainerHigh,
              elevation: 6,
              borderRadius: const BorderRadius.all(Radius.circular(12)),
              clipBehavior: Clip.antiAlias,
              // Scrollable: on a short screen the lines do not all fit.
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final e in entries) ...[
                      if (e.dividerAbove) const Divider(height: 1),
                      _line(context, e),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(BuildContext context, PostMenuEntry e) {
    final scheme = Theme.of(context).colorScheme;
    final action = e.onSelected;
    final color = e.destructive
        ? scheme.error
        : action == null
        ? scheme.onSurfaceVariant
        : scheme.onSurface;
    return InkWell(
      onTap: action == null ? null : () => Navigator.pop(context, action),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(e.icon, size: 22, color: color),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                e.label,
                style: TextStyle(fontSize: 16, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
