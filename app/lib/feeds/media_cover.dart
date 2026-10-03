import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../l10n/l10n.dart';

/// A picture or a video the reader is not shown at once, as in the official app: one its
/// author put under a spoiler is blurred until it is tapped, and one Telegram marks as
/// content for adults is blurred under an "18+" label and asks before it shows.
///
/// The media itself is built underneath and blurred where it stands, so nothing moves when
/// the cover goes. What was uncovered stays so until the app is closed.
class CoveredMedia extends StatefulWidget {
  const CoveredMedia({
    super.key,
    required this.fileId,
    required this.cover,
    required this.child,
    this.radius = 0,
  });

  /// The file of the media: what the reader has uncovered is remembered by it.
  final int fileId;
  final MediaCover cover;
  final double radius;
  final Widget child;

  static final _uncovered = <int>{};

  /// Covers everything again, for tests.
  @visibleForTesting
  static void coverAll() => _uncovered.clear();

  @override
  State<CoveredMedia> createState() => _CoveredMediaState();
}

class _CoveredMediaState extends State<CoveredMedia> {
  bool get _shown =>
      widget.cover == MediaCover.none ||
      CoveredMedia._uncovered.contains(widget.fileId);

  Future<void> _uncover() async {
    if (widget.cover == MediaCover.sensitive) {
      final l10n = context.l10n;
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.mediaSensitiveLabel),
          content: Text(l10n.mediaSensitiveQuestion),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.mediaSensitiveView),
            ),
          ],
        ),
      );
      if (!(yes ?? false) || !mounted) return;
    }
    setState(() => CoveredMedia._uncovered.add(widget.fileId));
  }

  @override
  Widget build(BuildContext context) {
    if (_shown) return widget.child;
    final l10n = context.l10n;
    final sensitive = widget.cover == MediaCover.sensitive;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        // There, so the cover has its size and something to blur, but out of reach.
        ExcludeSemantics(child: IgnorePointer(child: widget.child)),
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.radius),
            child: BackdropFilter(
              // Strong enough to leave colours and no shapes.
              filter: ImageFilter.blur(sigmaX: 44, sigmaY: 44),
              child: Semantics(
                button: true,
                label: sensitive
                    ? l10n.mediaCoverSensitive
                    : l10n.mediaCoverSpoiler,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => unawaited(_uncover()),
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.3),
                    child: Center(
                      child: sensitive
                          ? DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 5,
                                ),
                                child: ExcludeSemantics(
                                  child: Text(
                                    l10n.mediaSensitiveLabel,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            )
                          : const Icon(
                              Icons.visibility_off_outlined,
                              color: Colors.white70,
                              size: 28,
                            ),
                    ),
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
