import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../host/haptics.dart';
import '../l10n/l10n.dart';
import 'post_menu.dart';
import 'sticker_view.dart';

/// Asks "Do you want to open …?" before a link that does not show where it leads, as the
/// official app does; true when the reader says yes.
Future<bool> confirmOpenLink(BuildContext context, String url) async {
  final l10n = context.l10n;
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.linkOpenTitle),
      content: Text(l10n.linkOpenQuestion(url)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.commonOpen),
        ),
      ],
    ),
  );
  return yes ?? false;
}

/// A post's text with Telegram's formatting: bold, italic, underline, strikethrough,
/// monospace, quotes, spoilers (hidden until tapped), links and mentions that open,
/// hashtags that search and phone numbers that call. Entities may nest and overlap; the
/// text is cut at every boundary and each piece gets the styles of all entities covering
/// it. A monospace block ends with the copy button the official app puts in its corner.
///
/// As in the official app: a link hidden behind other words asks before it opens, a long
/// press on a link offers to open it or copy it, and a tap on inline code copies it.
class FormattedText extends StatefulWidget {
  const FormattedText({
    super.key,
    required this.text,
    required this.entities,
    required this.style,
    this.onOpenLink,
    this.onOpenHashtag,
    this.gateway,
    this.canCopy = true,
  });
  final String text;
  final List<TextEntity> entities;
  final TextStyle style;

  /// False for a post of a channel that protects its content: a block of code then has
  /// no copy button.
  final bool canCopy;

  /// Links are plain coloured text without it.
  final void Function(String url)? onOpenLink;

  /// A tap on a hashtag or a cashtag, with the tag as it stands in the text. Tags are
  /// plain coloured text without it.
  final void Function(String tag)? onOpenHashtag;

  /// Fetches the stickers of custom emoji; without it they stay the plain emoji.
  final TelegramGateway? gateway;

  @override
  State<FormattedText> createState() => FormattedTextState();
}

class FormattedTextState extends State<FormattedText> {
  final _recognizers = <GestureRecognizer>[];

  /// Stickers of the custom emoji in this text, once TDLib has named them.
  Map<String, StickerMedia> _emoji = const {};

  /// Offsets of the spoilers the user has uncovered.
  final _revealed = <int>{};

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadCustomEmoji());
  }

  @override
  void didUpdateWidget(FormattedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _revealed.clear();
    if (oldWidget.entities != widget.entities) {
      unawaited(_loadCustomEmoji());
    }
  }

  /// One request for all the custom emoji of this text; the gateway keeps what it learns,
  /// so the same emoji in the next post costs nothing.
  Future<void> _loadCustomEmoji() async {
    final gateway = widget.gateway;
    if (gateway == null) return;
    final ids = {
      for (final e in widget.entities)
        if (e.kind == TextEntityKind.customEmoji && e.customEmojiId != null)
          e.customEmojiId!,
    };
    if (ids.isEmpty) return;
    try {
      final found = await gateway.customEmoji(ids.toList());
      if (mounted && found.isNotEmpty) setState(() => _emoji = found);
    } on TelegramException {
      // The plain emoji of the text stays.
    }
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

  /// A tap that says where it landed, for a menu that opens there.
  TapGestureRecognizer _onTapAt(void Function(Offset at) action) {
    final r = TapGestureRecognizer()..onTapUp = (d) => action(d.globalPosition);
    _recognizers.add(r);
    return r;
  }

  /// A link: a tap opens it, a long press offers to open or copy it.
  GestureRecognizer _onLink(String url, String shown) {
    final r = TapOrHoldRecognizer(
      onTap: () => unawaited(_openLink(url, shown)),
      onHold: (at) => unawaited(_linkMenu(url, at)),
    );
    _recognizers.add(r);
    return r;
  }

  /// Whether the link stands behind other words than its own address, so that the reader
  /// cannot see where it leads: it is then asked about, as the official app does. Links
  /// into Telegram and addresses that are no web pages are not.
  static bool hidesTarget(String url, String shown) {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return false;
    }
    final host = uri.host.toLowerCase();
    const telegram = ['t.me', 'telegram.me', 'telegram.dog', 'telegra.ph'];
    if (telegram.any((h) => host == h || host.endsWith('.$h'))) return false;
    String bare(String s) => s
        .trim()
        .toLowerCase()
        .replaceFirst(RegExp(r'^https?://'), '')
        .replaceFirst(RegExp(r'/$'), '');
    return bare(shown) != bare(url);
  }

  Future<void> _openLink(String url, String shown) async {
    final open = widget.onOpenLink;
    if (open == null) return;
    if (!hidesTarget(url, shown)) return open(url);
    if (await confirmOpenLink(context, url)) open(url);
  }

  Future<void> _copy(String text, String said) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    await Clipboard.setData(ClipboardData(text: text));
    messenger?.showSnackBar(SnackBar(content: Text(said)));
  }

  Future<void> _linkMenu(String url, Offset at) async {
    final l10n = context.l10n;
    final action = await showPostMenu(
      context,
      at: at,
      entries: [
        PostMenuEntry(icon: Icons.link, label: url),
        PostMenuEntry(
          icon: Icons.open_in_new,
          label: l10n.commonOpen,
          onSelected: () => widget.onOpenLink?.call(url),
        ),
        PostMenuEntry(
          icon: Icons.content_copy,
          label: l10n.commonCopyLink,
          onSelected: () => unawaited(_copy(url, l10n.timelineLinkCopied(url))),
        ),
      ],
    );
    action?.call();
  }

  Future<void> _phoneMenu(String tel, String shown, Offset at) async {
    final l10n = context.l10n;
    final action = await showPostMenu(
      context,
      at: at,
      entries: [
        PostMenuEntry(icon: Icons.phone_outlined, label: shown),
        PostMenuEntry(
          icon: Icons.call,
          label: l10n.phoneCall,
          onSelected: () => widget.onOpenLink?.call(tel),
        ),
        PostMenuEntry(
          icon: Icons.content_copy,
          label: l10n.phoneCopy,
          onSelected: () => unawaited(_copy(shown, l10n.phoneCopied)),
        ),
      ],
    );
    action?.call();
  }

  /// The quotes and code blocks of the text that are drawn as blocks of their own: in the
  /// order of the text, none inside another (one that is keeps its inline look).
  static List<TextEntity> blocksOf(List<TextEntity> entities) {
    final blocks =
        [
          for (final e in entities)
            if (e.kind == TextEntityKind.quote || e.kind == TextEntityKind.pre)
              e,
        ]..sort(
          (a, b) => a.offset != b.offset ? a.offset - b.offset : b.end - a.end,
        );
    final out = <TextEntity>[];
    for (final e in blocks) {
      if (out.isEmpty || e.offset >= out.last.end) out.add(e);
    }
    return out;
  }

  /// Offsets of the expandable quotes the reader has opened.
  final _opened = <int>{};

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final text = widget.text;
    final entities = [
      for (final e in widget.entities)
        if (e.length > 0 && e.offset >= 0 && e.end <= text.length) e,
    ];
    if (entities.isEmpty) return Text(text, style: widget.style);
    final blocks = blocksOf(entities);
    if (blocks.isEmpty) {
      return Text.rich(
        TextSpan(children: _spans(context, entities, 0, text.length)),
        style: widget.style,
      );
    }
    // Words, block, words: a column. The line break that parts a block from the words
    // around it is the block's own edge and is not drawn a second time.
    final children = <Widget>[];
    void words(
      int from,
      int to, {
      required bool afterBlock,
      required bool beforeBlock,
    }) {
      if (afterBlock && from < to && text[from] == '\n') from++;
      if (beforeBlock && from < to && text[to - 1] == '\n') to--;
      if (from >= to) return;
      children.add(
        Text.rich(
          TextSpan(children: _spans(context, entities, from, to)),
          style: widget.style,
        ),
      );
    }

    var at = 0;
    for (final block in blocks) {
      words(at, block.offset, afterBlock: at > 0, beforeBlock: true);
      var end = block.end;
      while (end > block.offset && text[end - 1] == '\n') {
        end--;
      }
      final spans = _spans(context, entities, block.offset, end, inside: block);
      final plain = text.substring(block.offset, end);
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: block.kind == TextEntityKind.pre
              ? CodeBlock(
                  spans: spans,
                  plain: plain,
                  language: block.language,
                  style: widget.style,
                  canCopy: widget.canCopy,
                )
              : QuoteBlock(
                  spans: spans,
                  plain: plain,
                  style: widget.style,
                  expandable: block.expandable,
                  open: _opened.contains(block.offset),
                  onToggle: () => setState(() {
                    if (!_opened.remove(block.offset)) {
                      _opened.add(block.offset);
                    }
                  }),
                ),
        ),
      );
      at = block.end;
    }
    words(at, text.length, afterBlock: true, beforeBlock: false);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  /// The pieces of the text between [from0] and [to0], each with the styles of all the
  /// entities that cover it. [inside] is the block the range stands in, which draws itself.
  List<InlineSpan> _spans(
    BuildContext context,
    List<TextEntity> entities,
    int from0,
    int to0, {
    TextEntity? inside,
  }) {
    final text = widget.text;
    final scheme = Theme.of(context).colorScheme;
    final cuts = <int>{from0, to0};
    for (final e in entities) {
      if (e.offset > from0 && e.offset < to0) cuts.add(e.offset);
      if (e.end > from0 && e.end < to0) cuts.add(e.end);
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
      TextEntity? emoji;
      TextEntity? hashtag;
      TextEntity? phone;
      TextEntity? code;
      for (final e in entities) {
        if (e.offset > from || e.end < to) continue;
        // The block these pieces stand in draws itself around them.
        if (identical(e, inside)) continue;
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
            if (e.kind == TextEntityKind.code) code = e;
          case TextEntityKind.quote:
            style = style.copyWith(
              fontStyle: FontStyle.italic,
              color: scheme.onSurfaceVariant,
            );
          case TextEntityKind.tag:
            style = style.copyWith(color: scheme.primary);
          case TextEntityKind.hashtag:
            style = style.copyWith(color: scheme.primary);
            hashtag = e;
          case TextEntityKind.phone:
            style = style.copyWith(color: scheme.primary);
            phone = e;
          case TextEntityKind.link:
            style = style.copyWith(color: scheme.primary);
            link = e;
          case TextEntityKind.spoiler:
            spoiler = e;
          case TextEntityKind.customEmoji:
            emoji ??= e;
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
        recognizer = _onLink(link!.url!, text.substring(link.offset, link.end));
      } else if (hashtag != null && widget.onOpenHashtag != null) {
        final tag = text.substring(hashtag.offset, hashtag.end);
        recognizer = _onTap(() => widget.onOpenHashtag!(tag));
      } else if (phone?.url != null && widget.onOpenLink != null) {
        final tel = phone!.url!;
        final shown = text.substring(phone.offset, phone.end);
        recognizer = _onTapAt((at) => unawaited(_phoneMenu(tel, shown, at)));
      } else if (code != null && widget.canCopy) {
        // A tap on inline code copies it, as in the official app.
        final piece = text.substring(code.offset, code.end);
        recognizer = _onTap(
          () => unawaited(_copy(piece, context.l10n.timelineCodeCopied)),
        );
      }
      final sticker = _emoji[emoji?.customEmojiId];
      if (sticker != null && !hidden) {
        // The sticker takes the place of the plain emoji the text carries, at the size of
        // a line of that text.
        final side = (widget.style.fontSize ?? 16) * 1.25;
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: SizedBox(
              width: side,
              height: side,
              child: StickerView(
                sticker: sticker,
                gateway: widget.gateway!,
                side: side,
              ),
            ),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: text.substring(from, to),
            style: style,
            recognizer: recognizer,
            semanticsLabel: hidden ? context.l10n.timelineSpoiler : null,
          ),
        );
      }
      // The end of a monospace block: its own copy button, as in the official app.
      for (final e in entities) {
        if (e.kind != TextEntityKind.pre ||
            e.end != to ||
            !widget.canCopy ||
            identical(e, inside)) {
          continue;
        }
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _CopyBlock(text: text.substring(e.offset, e.end)),
          ),
        );
      }
    }
    return spans;
  }
}

/// The frame of a quote or a code block, as the official app draws them: a tinted,
/// rounded box with a bar of the accent colour down its left side.
class _BlockFrame extends StatelessWidget {
  const _BlockFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: ColoredBox(
        color: accent.withValues(alpha: 0.1),
        child: Stack(
          children: [
            child,
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 3,
              child: ColoredBox(color: accent),
            ),
          ],
        ),
      ),
    );
  }
}

/// A quote in a post. An expandable one that is longer than three lines shows those three
/// until it is tapped, with an arrow in its corner that says which way it goes.
class QuoteBlock extends StatelessWidget {
  const QuoteBlock({
    super.key,
    required this.spans,
    required this.plain,
    required this.style,
    this.expandable = false,
    this.open = false,
    this.onToggle,
  });
  final List<InlineSpan> spans;

  /// The quote's words without their formatting: what its length is measured by.
  final String plain;
  final TextStyle style;
  final bool expandable;
  final bool open;
  final VoidCallback? onToggle;

  /// The lines a closed quote shows.
  static const closedLines = 3;

  static const _padding = EdgeInsets.fromLTRB(11, 5, 26, 5);

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return LayoutBuilder(
      builder: (context, constraints) {
        var long = false;
        if (expandable) {
          final painter = TextPainter(
            text: TextSpan(
              text: plain,
              style: DefaultTextStyle.of(context).style.merge(style),
            ),
            maxLines: closedLines,
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout(maxWidth: constraints.maxWidth - _padding.horizontal);
          long = painter.didExceedMaxLines;
          painter.dispose();
        }
        final closed = long && !open;
        final frame = _BlockFrame(
          child: Stack(
            children: [
              Padding(
                padding: _padding,
                child: SizedBox(
                  width: double.infinity,
                  child: Text.rich(
                    TextSpan(children: spans),
                    style: style,
                    maxLines: closed ? closedLines : null,
                    overflow: closed ? TextOverflow.ellipsis : null,
                  ),
                ),
              ),
              Positioned(
                top: 5,
                right: 6,
                child: Icon(Icons.format_quote, size: 14, color: accent),
              ),
              if (long)
                Positioned(
                  bottom: 2,
                  right: 4,
                  child: Icon(
                    open ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: accent,
                    semanticLabel: open
                        ? context.l10n.quoteCollapse
                        : context.l10n.quoteExpand,
                  ),
                ),
            ],
          ),
        );
        if (!long) return frame;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onToggle,
          child: frame,
        );
      },
    );
  }
}

/// A block of code in a post: its language over it when the author named one, the copy
/// button in its corner, and the code in a monospace face.
class CodeBlock extends StatelessWidget {
  const CodeBlock({
    super.key,
    required this.spans,
    required this.plain,
    required this.style,
    this.language,
    this.canCopy = true,
  });
  final List<InlineSpan> spans;
  final String plain;
  final TextStyle style;
  final String? language;
  final bool canCopy;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final named = language != null && language!.isNotEmpty;
    final code = Text.rich(
      TextSpan(children: spans),
      style: style.copyWith(
        fontFamily: 'monospace',
        fontSize: (style.fontSize ?? 16) - 2,
      ),
    );
    return _BlockFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (named)
            ColoredBox(
              color: accent.withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(11, 3, 4, 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        language!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: accent,
                        ),
                      ),
                    ),
                    if (canCopy) _CopyBlock(text: plain),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(11, 5, 6, 5),
            child: named || !canCopy
                ? code
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: code),
                      _CopyBlock(text: plain),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Copies a monospace block. The button is part of the text, so it sits where the block
/// ends instead of floating over it.
class _CopyBlock extends StatelessWidget {
  const _CopyBlock({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: InkWell(
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: text));
        if (!context.mounted) return;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(context.l10n.timelineCodeCopied)),
        );
      },
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(
          Icons.content_copy,
          size: 15,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          semanticLabel: context.l10n.timelineCopyCode,
        ),
      ),
    ),
  );
}

/// A recognizer for a piece of text that answers a tap and a long press. A span takes one
/// recognizer only, and its paragraph knows a tap recognizer when it meets one (for the
/// screen reader's "activate"), so this is a tap recognizer that brings a long press along.

class TapOrHoldRecognizer extends TapGestureRecognizer {
  TapOrHoldRecognizer({
    required VoidCallback onTap,
    required void Function(Offset at) onHold,
  }) {
    this.onTap = onTap;
    _hold.onLongPressStart = (d) {
      Haptics.longPress();
      onHold(d.globalPosition);
    };
  }
  final _hold = LongPressGestureRecognizer();

  /// What a long press at [at] does: a test cannot aim at a piece of text.
  @visibleForTesting
  void holdForTest(Offset at) =>
      _hold.onLongPressStart!(LongPressStartDetails(globalPosition: at));

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _hold.addPointer(event);
  }

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }
}
