import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../l10n/l10n.dart';
import 'post_menu.dart';
import 'sticker_view.dart';

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
    if (yes ?? false) open(url);
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
      TextEntity? emoji;
      TextEntity? hashtag;
      TextEntity? phone;
      TextEntity? code;
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
        if (e.kind != TextEntityKind.pre || e.end != to || !widget.canCopy) {
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
    return Text.rich(TextSpan(children: spans), style: widget.style);
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
    _hold.onLongPressStart = (d) => onHold(d.globalPosition);
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
