import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../host/haptics.dart';
import '../feeds/media_view.dart' show Downloaded, MediaMiniature, PhotoView;
import '../feeds/post_card.dart' show formatTime, peerColor;
import '../l10n/l10n.dart';
import '../widgets/error_state.dart';
import '../widgets/skeleton_list.dart';
import 'unread_badge.dart';

/// Channels as the official app lists chats: photo, title, newest post, time, unread count.
/// Used by the folder tabs and, with a search box, by "All channels".
class ChannelList extends StatefulWidget {
  const ChannelList({
    super.key,
    required this.channels,
    required this.gateway,
    required this.onOpen,
    this.onMenu,
    this.header,
    this.searchable = false,
    this.onRefresh,
    this.emptyText,
    this.feedsByChat = const {},
    this.loading = false,
    this.error,
  });
  final List<Channel> channels;
  final TelegramGateway gateway;
  final void Function(Channel channel) onOpen;

  /// Long press on a row: the menu of H-15, at the point the finger was on.
  final void Function(Channel channel, Offset at)? onMenu;

  /// A row above the channels, which the list scrolls with them (the Archive of H-30).
  final Widget? header;
  final bool searchable;
  final Future<void> Function()? onRefresh;

  /// What an empty list says; "No channels here." when not given.
  final String? emptyText;

  /// True while the channels are still coming: a spinner instead of [emptyText].
  final bool loading;

  /// A failed reload while channels are shown: a banner with Retry above them.
  final String? error;

  /// Names of the feeds each channel belongs to, by chat id ([AppDatabase.feedNamesByChat]).
  final Map<int, List<String>> feedsByChat;

  @override
  State<ChannelList> createState() => _ChannelListState();
}

class _ChannelListState extends State<ChannelList>
    with AutomaticKeepAliveClientMixin {
  String _query = '';

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final q = _query.trim().toLowerCase();
    final shown = [
      for (final c in widget.channels)
        if (q.isEmpty ||
            c.title.toLowerCase().contains(q) ||
            (c.username?.toLowerCase().contains(q) ?? false))
          c,
    ];
    if (widget.loading && widget.channels.isEmpty) {
      return const SkeletonList();
    }
    // Nothing to show and a failed load: the whole tab says so and offers the retry,
    // instead of hiding the code in the "no channels" line.
    if (widget.channels.isEmpty && widget.error != null) {
      return ErrorState(
        what: context.l10n.channelsLoadFailed,
        message: widget.error,
        onRetry: widget.onRefresh == null
            ? null
            : () => unawaited(widget.onRefresh!()),
      );
    }
    Widget list = shown.isEmpty
        ? ListView(
            children: [
              // The way to the archive stays when everything is in it, and when the
              // search box finds nothing here.
              ?widget.header,
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  q.isEmpty
                      ? widget.emptyText ?? context.l10n.channelsEmpty
                      : context.l10n.channelsNoMatch(_query),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          )
        : ListView.builder(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            itemCount: shown.length + (widget.header == null ? 0 : 1),
            itemBuilder: (context, row) {
              if (widget.header != null && row == 0) return widget.header!;
              final i = widget.header == null ? row : row - 1;
              return ChannelTile(
                key: ValueKey(shown[i].chatId),
                channel: shown[i],
                gateway: widget.gateway,
                feeds: widget.feedsByChat[shown[i].chatId] ?? const [],
                onTap: () => widget.onOpen(shown[i]),
                onMenu: widget.onMenu == null
                    ? null
                    : (at) => widget.onMenu!(shown[i], at),
              );
            },
          );
    if (widget.onRefresh != null) {
      list = RefreshIndicator(onRefresh: widget.onRefresh!, child: list);
    }
    final error = widget.error;
    final banner = error == null
        ? null
        : MaterialBanner(
            content: Text(
              telegramErrorLine(
                error,
                what: context.l10n.channelsRefreshFailed,
                l10n: context.l10n,
              ),
            ),
            actions: [
              TextButton(
                onPressed: widget.onRefresh == null
                    ? null
                    : () => unawaited(widget.onRefresh!()),
                child: Text(context.l10n.commonRetry),
              ),
            ],
          );
    if (!widget.searchable) {
      return banner == null
          ? list
          : Column(
              children: [
                banner,
                Expanded(child: list),
              ],
            );
    }
    return Column(
      children: [
        ?banner,
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: context.l10n.channelsSearchHint,
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(child: list),
      ],
    );
  }
}

class ChannelTile extends StatelessWidget {
  const ChannelTile({
    super.key,
    required this.channel,
    required this.gateway,
    required this.onTap,
    this.onMenu,
    this.feeds = const [],
  });
  final Channel channel;
  final TelegramGateway gateway;
  final VoidCallback onTap;

  /// Long press: the row's menu, at the point the finger was on.
  final void Function(Offset at)? onMenu;

  /// Names of the feeds this channel is in; shown as tags under the newest post.
  final List<String> feeds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final c = channel;
    final album = c.lastMessageAlbum;
    final pictures = [
      for (final media in album)
        if (media is PhotoMedia || media is VideoMedia) media,
    ];
    final words = c.lastMessageText.isNotEmpty;
    // An album without words says how many it holds and of what; a single post what it
    // carries.
    final label = album.length > 1
        ? albumLabel(album, l10n)
        : l10n.mediaPreview(c.lastMessageMedia, channel: c.title);
    final tile = ListTile(
      onTap: onTap,
      // Always two lines: the preview line stays even when there is nothing to preview,
      // and the feed tags share it, so rows keep one height as channels join feeds.
      leading: ChannelAvatar(
        photo: c.photo,
        title: c.title,
        colorId: c.chatId,
        gateway: gateway,
      ),
      title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Row(
        children: [
          // Up to three pictures of the newest post, as the official app's rows show.
          for (final media in pictures.take(3))
            Padding(
              padding: const EdgeInsets.only(right: 3),
              child: RowThumbnail(media: media, gateway: gateway),
            ),
          if (pictures.isNotEmpty) const SizedBox(width: 2),
          Expanded(
            child: Text(
              // A post without words is named by what it carries, in the accent colour.
              words ? c.lastMessageText : label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: words ? null : TextStyle(color: theme.colorScheme.primary),
            ),
          ),
          if (feeds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: FeedTags(names: feeds),
            ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (c.lastMessageDate > 0)
            Text(
              formatListDate(
                DateTime.fromMillisecondsSinceEpoch(c.lastMessageDate * 1000),
                context: context,
              ),
              style: theme.textTheme.labelSmall,
            ),
          if (c.unreadCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: UnreadBadge(c.unreadCount, muted: c.isMuted),
            ),
        ],
      ),
    );
    if (onMenu == null) return tile;
    // The menu opens under the finger, which a ListTile's own long press cannot report.
    return GestureDetector(
      onLongPressStart: (d) {
        Haptics.longPress();
        onMenu!(d.globalPosition);
      },
      child: tile,
    );
  }
}

/// "3 photos", "2 videos", "4 files", "2 music files": what an album holds when all its
/// parts are of one kind, "5 media" when they are not.
String albumLabel(List<Media> album, AppLocalizations l10n) {
  final n = album.length;
  if (album.every((m) => m is PhotoMedia)) return l10n.channelsAlbumPhotos(n);
  if (album.every((m) => m is VideoMedia)) return l10n.channelsAlbumVideos(n);
  if (album.every((m) => m is DocumentMedia)) return l10n.channelsAlbumFiles(n);
  if (album.every((m) => m is AudioMedia)) return l10n.channelsAlbumMusic(n);
  return l10n.channelsAlbumMedia(n);
}

/// A picture of a channel's newest post in its row: a small rounded square. Telegram's
/// own tiny preview is drawn where the post has one, so a list of channels downloads
/// nothing for it; a video carries a play mark; covered media stays blurred.
class RowThumbnail extends StatelessWidget {
  const RowThumbnail({super.key, required this.media, required this.gateway});
  final Media media;
  final TelegramGateway gateway;

  static const side = 20.0;

  @override
  Widget build(BuildContext context) {
    final (miniature, covered, smallest) = switch (media) {
      PhotoMedia(:final miniature, :final cover, :final sizes) => (
        miniature,
        cover != MediaCover.none,
        sizes.isEmpty ? null : sizes.first,
      ),
      VideoMedia(:final miniature, :final cover) => (
        miniature,
        cover != MediaCover.none,
        null,
      ),
      _ => (null, false, null),
    };
    final Widget picture;
    if (miniature != null && covered) {
      picture = MediaMiniature(miniature);
    } else if (miniature != null) {
      picture = Image.memory(
        base64Decode(miniature),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black12),
      );
    } else if (smallest != null && !covered) {
      picture = PhotoView(
        file: smallest,
        gateway: gateway,
        fill: true,
        radius: 0,
      );
    } else {
      picture = const ColoredBox(color: Colors.black12);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox.square(
        dimension: side,
        child: Stack(
          fit: StackFit.expand,
          children: [
            picture,
            if (media is VideoMedia)
              const Center(
                child: Icon(Icons.play_arrow, size: 14, color: Colors.white),
              ),
          ],
        ),
      ),
    );
  }
}

/// The feeds a channel belongs to, as small chips. Channel lists carry them so that it is
/// visible at a glance what a channel is already read in.
class FeedTags extends StatelessWidget {
  const FeedTags({super.key, required this.names, this.max = 2});
  final List<String> names;

  /// Tags drawn before the rest becomes "+N".
  final int max;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = names.length > max ? names.take(max - 1).toList() : names;
    final rest = names.length - shown.length;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final n in [...shown, if (rest > 0) '+$rest'])
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: const BorderRadius.all(Radius.circular(6)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              child: Text(
                n,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Round photo of a channel or user; initials on a tinted disc until (or without) a photo.
class ChannelAvatar extends StatelessWidget {
  const ChannelAvatar({
    super.key,
    required this.photo,
    required this.title,
    required this.gateway,
    this.colorId,
    this.radius = 22,
  });
  final FileRef? photo;
  final String title;
  final TelegramGateway gateway;

  /// Chat id the disc takes its colour from, as the official app colours its avatars.
  /// Without one every disc is the theme's own tint.
  final int? colorId;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Up to two initials, as the official app draws them.
    final words = title.trim().split(RegExp(r'\s+'))
      ..removeWhere((w) => w.isEmpty);
    final letters = words.isEmpty
        ? '?'
        : words.length == 1
        ? words.first.characters.first.toUpperCase()
        : (words.first.characters.first + words[1].characters.first)
              .toUpperCase();
    final tint = colorId == null
        ? scheme.secondaryContainer
        : peerColor(colorId!, theme.brightness).withValues(alpha: 0.25);
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: tint,
      foregroundColor: colorId == null
          ? scheme.onSecondaryContainer
          : peerColor(colorId!, theme.brightness),
      child: Text(letters, style: TextStyle(fontSize: radius * 0.7)),
    );
    final file = photo;
    if (file == null) return fallback;
    return SizedBox.square(
      dimension: radius * 2,
      child: Downloaded(
        key: ValueKey(file.id),
        file: file,
        gateway: gateway,
        placeholder: fallback,
        builder: (context, path) => CircleAvatar(
          radius: radius,
          backgroundImage: ResizeImage(
            FileImage(File(path)),
            width: (radius * 2 * MediaQuery.devicePixelRatioOf(context)).ceil(),
            policy: ResizeImagePolicy.fit,
          ),
        ),
      ),
    );
  }
}

/// When a row of a list was posted, as the official app writes it
/// (`LocaleController.stringForMessageListDate`): the time for today, and for last night
/// while it is less than eight hours ago; the weekday within a week; "Sep 12" within a
/// year; "12.09.25" before that.
String formatListDate(DateTime d, {DateTime? now, BuildContext? context}) {
  final n = now ?? DateTime.now();
  // Where the app's strings are not loaded, neither is intl's date data of their
  // language: en_US needs none.
  final strings = context == null
      ? null
      : Localizations.of<AppLocalizations>(context, AppLocalizations);
  final locale = strings == null || strings.localeName == 'en'
      ? 'en_US'
      : strings.localeName;
  if (n.difference(d).abs() >= const Duration(days: 365)) {
    return DateFormat('dd.MM.yy').format(d);
  }
  // Rounded: a day with a clock change is 23 or 25 hours long.
  final days =
      (DateTime(
                n.year,
                n.month,
                n.day,
              ).difference(DateTime(d.year, d.month, d.day)).inHours /
              24)
          .round();
  if (days == 0 || (days == 1 && n.difference(d) < const Duration(hours: 8))) {
    return formatTime(d, context);
  }
  if (days >= 1 && days < 7) return DateFormat.E(locale).format(d);
  return DateFormat(strings?.listDatePattern ?? 'MMM dd', locale).format(d);
}
