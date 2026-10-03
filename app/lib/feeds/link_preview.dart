import 'package:flutter/material.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../l10n/l10n.dart';
import 'media_view.dart';
import 'post_card.dart' show peerColor;

/// The card of a post that carries a link, drawn like the official app's: an accent bar in
/// the channel's colour, the site, the title (or the author), up to six lines of
/// description, and the picture — wide under the text or as a small square beside it, as
/// TDLib asks. A link into Telegram ends with a line that says what it opens. A tap anywhere on it opens the
/// link; the app has no player or reader of its own, so even a video link goes out.
class LinkPreviewCard extends StatelessWidget {
  const LinkPreviewCard({
    super.key,
    required this.preview,
    required this.colorId,
    required this.gateway,
    this.onOpen,
  });
  final LinkPreview preview;

  /// Chat id of the channel; picks the accent colour, as the name above does.
  final int colorId;
  final TelegramGateway gateway;
  final VoidCallback? onOpen;

  /// Side of the small picture, which the official app puts beside the text.
  static const _smallSide = 56.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = peerColor(colorId, scheme.brightness);
    final photo = preview.photo;
    final wide = photo != null && preview.largeMedia;
    final picture = photo == null ? null : _picture(context, photo, wide: wide);

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (preview.siteName.isNotEmpty)
          Text(
            preview.siteName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: accent,
            ),
          ),
        if (preview.title.isNotEmpty)
          Text(
            preview.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
        // The author stands where the title would, when there is none: as the official
        // app draws it.
        if (preview.title.isEmpty && preview.author.isNotEmpty)
          Text(
            preview.author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
        if (preview.description.isNotEmpty)
          Text(
            preview.description,
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              height: 1.25,
              color: scheme.onSurface,
            ),
          ),
        // A preview without any words of its own still says where it leads.
        if (preview.siteName.isEmpty &&
            preview.title.isEmpty &&
            preview.author.isEmpty &&
            preview.description.isEmpty &&
            preview.displayUrl.isNotEmpty)
          Text(
            preview.displayUrl,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, color: accent),
          ),
      ],
    );

    final l10n = context.l10n;
    final button = switch (preview.kind) {
      LinkKind.web => null,
      LinkKind.channel => l10n.linkViewChannel,
      LinkKind.group => l10n.linkViewGroup,
      LinkKind.message => l10n.linkViewMessage,
      LinkKind.user => l10n.linkSendMessage,
      LinkKind.bot => l10n.linkOpenBot,
      LinkKind.background => l10n.linkViewBackground,
      LinkKind.theme => l10n.linkViewTheme,
      LinkKind.stickers => l10n.linkViewStickers,
      LinkKind.videoChat => l10n.linkJoinVideoChat,
      LinkKind.story => l10n.linkViewStory,
      LinkKind.boost => l10n.linkBoost,
      LinkKind.chatFolder => l10n.linkViewChatFolder,
      LinkKind.webApp => l10n.linkOpenApp,
    };

    final body = wide
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (preview.photoAbove) ...[
                picture!,
                const SizedBox(height: 6),
                text,
              ] else ...[
                text,
                const SizedBox(height: 6),
                picture!,
              ],
            ],
          )
        : picture == null
        ? text
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: text),
              const SizedBox(width: 8),
              picture,
            ],
          );

    return Material(
      color: accent.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        // The accent is a border, not a child of a row: a bar that stretches would need a
        // height, and the card takes the height of its words and its picture.
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: accent, width: 3)),
          ),
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: button == null
              ? body
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    body,
                    const SizedBox(height: 6),
                    // What the link leads to inside Telegram. The whole card is the
                    // button, so this only says it.
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: Text(
                          button,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: accent,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  /// The card's picture: the width of the card when TDLib asks for large media, a small
  /// square otherwise. A link to a video carries a play badge and its length.
  Widget _picture(
    BuildContext context,
    PhotoMedia photo, {
    required bool wide,
  }) {
    final file = wide
        ? pickPhotoSize(
            photo.sizes,
            MediaQuery.sizeOf(context).width,
            pixelRatio: MediaQuery.devicePixelRatioOf(context),
          )
        : photo.sizes.first;
    final picture = PhotoView(
      file: file,
      gateway: gateway,
      onTap: onOpen,
      fill: !wide,
      radius: wide ? 8 : 6,
    );
    final sized = wide
        ? picture
        : SizedBox(width: _smallSide, height: _smallSide, child: picture);
    if (!preview.isVideo) return sized;
    return Stack(
      alignment: Alignment.center,
      children: [
        sized,
        Container(
          decoration: const BoxDecoration(
            color: Colors.black45,
            shape: BoxShape.circle,
          ),
          padding: EdgeInsets.all(wide ? 8 : 2),
          child: Icon(
            Icons.play_arrow,
            color: Colors.white,
            size: wide ? 28 : 18,
          ),
        ),
        if (wide && preview.durationSeconds > 0)
          Positioned(
            left: 6,
            bottom: 6,
            child: MediaBadge(formatDuration(preview.durationSeconds)),
          ),
      ],
    );
  }
}
