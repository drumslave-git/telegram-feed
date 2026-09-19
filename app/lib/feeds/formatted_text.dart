import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

/// A post's text with Telegram's formatting: bold, italic, underline, strikethrough,
/// monospace, quotes, spoilers (hidden until tapped), links and mentions that open, and
/// coloured hashtags. Entities may nest and overlap; the text is cut at every boundary and
/// each piece gets the styles of all entities covering it.
class FormattedText extends StatefulWidget {
  const FormattedText({
    super.key,
    required this.text,
    required this.entities,
    required this.style,
    this.onOpenLink,
  });
  final String text;
  final List<TextEntity> entities;
  final TextStyle style;

  /// Links are plain coloured text without it.
  final void Function(String url)? onOpenLink;

  @override
  State<FormattedText> createState() => _FormattedTextState();
}

class _FormattedTextState extends State<FormattedText> {
  final _recognizers = <TapGestureRecognizer>[];

  /// Offsets of the spoilers the user has uncovered.
  final _revealed = <int>{};

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void didUpdateWidget(FormattedText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _revealed.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  TapGestureRecognizer _onTap(VoidCallback action) {
    final r = TapGestureRecognizer()..onTap = action;
    _recognizers.add(r);
    return r;
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final text = widget.text;
    final entities = [
      for (final e in widget.entities)
        if (e.length > 0 && e.offset >= 0 && e.end <= text.length) e,
    ];
    if (entities.isEmpty) return Text(text, style: widget.style);

    final scheme = Theme.of(context).colorScheme;
    final cuts = <int>{0, text.length};
    for (final e in entities) {
      cuts
        ..add(e.offset)
        ..add(e.end);
    }
    final bounds = cuts.toList()..sort();
    final spans = <InlineSpan>[];
    for (var i = 0; i + 1 < bounds.length; i++) {
      final from = bounds[i];
      final to = bounds[i + 1];
      var style = const TextStyle();
      final decorations = <TextDecoration>[];
      TextEntity? link;
      TextEntity? spoiler;
      for (final e in entities) {
        if (e.offset > from || e.end < to) continue;
        switch (e.kind) {
          case TextEntityKind.bold:
            style = style.copyWith(fontWeight: FontWeight.w700);
          case TextEntityKind.italic:
            style = style.copyWith(fontStyle: FontStyle.italic);
          case TextEntityKind.underline:
            decorations.add(TextDecoration.underline);
          case TextEntityKind.strikethrough:
            decorations.add(TextDecoration.lineThrough);
          case TextEntityKind.code || TextEntityKind.pre:
            style = style.copyWith(
              fontFamily: 'monospace',
              backgroundColor: scheme.surfaceContainerHighest,
            );
          case TextEntityKind.quote:
            style = style.copyWith(
              fontStyle: FontStyle.italic,
              color: scheme.onSurfaceVariant,
            );
          case TextEntityKind.tag:
            style = style.copyWith(color: scheme.primary);
          case TextEntityKind.link:
            style = style.copyWith(color: scheme.primary);
            link = e;
          case TextEntityKind.spoiler:
            spoiler = e;
        }
      }
      if (decorations.isNotEmpty) {
        style = style.copyWith(decoration: TextDecoration.combine(decorations));
      }
      GestureRecognizer? recognizer;
      final hidden = spoiler != null && !_revealed.contains(spoiler.offset);
      if (hidden) {
        // Covered: the glyphs take their space but show as a block until tapped.
        final cover = scheme.onSurfaceVariant.withValues(alpha: 0.35);
        style = style.copyWith(
          color: Colors.transparent,
          backgroundColor: cover,
          decoration: TextDecoration.none,
        );
        final offset = spoiler.offset;
        recognizer = _onTap(() => setState(() => _revealed.add(offset)));
      } else if (link?.url != null && widget.onOpenLink != null) {
        final url = link!.url!;
        recognizer = _onTap(() => widget.onOpenLink!(url));
      }
      spans.add(
        TextSpan(
          text: text.substring(from, to),
          style: style,
          recognizer: recognizer,
          semanticsLabel: hidden ? 'spoiler' : null,
        ),
      );
    }
    return Text.rich(TextSpan(children: spans), style: widget.style);
  }
}
