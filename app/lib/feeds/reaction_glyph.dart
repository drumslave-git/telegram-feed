import 'dart:async';

import 'package:flutter/material.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'sticker_view.dart';

/// What a reaction looks like: its emoji, the sticker of a custom emoji, or the star of the
/// paid reaction (`Reaction.emoji` names which).
class ReactionGlyph extends StatefulWidget {
  const ReactionGlyph(
    this.reaction, {
    super.key,
    required this.size,
    this.gateway,
    this.color,
  });
  final String reaction;

  /// The font size of a plain emoji; a sticker and the star are drawn as large as that
  /// emoji comes out.
  final double size;

  /// Loads the sticker of a custom emoji; without it the place stays empty.
  final TelegramGateway? gateway;

  /// The colour of the star on a pill that is not filled.
  final Color? color;

  @override
  State<ReactionGlyph> createState() => _ReactionGlyphState();
}

class _ReactionGlyphState extends State<ReactionGlyph> {
  /// Stickers of custom emoji by id: a pill built again while the list scrolls has its
  /// sticker at once.
  static final _known = <String, StickerMedia>{};

  StickerMedia? _sticker;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ReactionGlyph old) {
    super.didUpdateWidget(old);
    if (old.reaction != widget.reaction) _load();
  }

  void _load() {
    final id = customReactionId(widget.reaction);
    _sticker = id == null ? null : _known[id];
    final gateway = widget.gateway;
    if (id == null || _sticker != null || gateway == null) return;
    unawaited(
      gateway
          .customEmoji([id])
          .then((found) {
            final sticker = found[id];
            if (sticker == null) return;
            _known[id] = sticker;
            if (mounted && customReactionId(widget.reaction) == id) {
              setState(() => _sticker = sticker);
            }
          })
          .catchError((Object _) {
            // The place stays empty; the count beside it still says there is one.
          }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final side = widget.size * 1.25;
    if (widget.reaction == paidReaction) {
      return Icon(
        Icons.star_rounded,
        size: side,
        color: widget.color ?? const Color(0xFFF5A623),
      );
    }
    if (customReactionId(widget.reaction) == null) {
      return Text(widget.reaction, style: TextStyle(fontSize: widget.size));
    }
    final sticker = _sticker;
    return SizedBox.square(
      dimension: side,
      child: sticker == null || widget.gateway == null
          ? null
          : StickerView(sticker: sticker, gateway: widget.gateway!, side: side),
    );
  }
}
