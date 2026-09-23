import 'package:flutter/material.dart';

/// Grey rows in the shape of the list that is coming, instead of a spinner in the middle
/// of an empty screen: the layout does not jump when the real rows arrive.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.rows = 7, this.leadingCircle = true});

  final int rows;

  /// A round stand-in for a channel photo; feeds have a square icon instead.
  final bool leadingCircle;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface
        .withValues(alpha: 0.08);
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
    );
    return ExcludeSemantics(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: rows,
        itemBuilder: (context, i) => ListTile(
          leading: leadingCircle
              ? CircleAvatar(radius: 22, backgroundColor: color)
              : bar(40, 40),
          title: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            // Rows of slightly different width read as a list, not as a table.
            child: bar(120 + (i % 3) * 40, 14),
          ),
          subtitle: bar(200 - (i % 4) * 30, 12),
        ),
      ),
    );
  }
}
