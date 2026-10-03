import 'dart:async';

import 'package:flutter/material.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../home/channel_list.dart' show ChannelAvatar;
import '../l10n/l10n.dart';
import 'media_view.dart';
import 'open_links.dart';

/// A place in a post, as the official app draws it: Telegram's picture of the map around
/// it with a pin in the middle, and under it the name and the address of a venue. A tap
/// opens the place in the phone's map app.
class LocationView extends StatefulWidget {
  const LocationView({super.key, required this.place, required this.gateway});
  final LocationMedia place;
  final TelegramGateway gateway;

  @override
  State<LocationView> createState() => _LocationViewState();
}

class _LocationViewState extends State<LocationView> {
  /// The map's picture, asked for once the width is known.
  Future<FileRef>? _map;
  int _asked = 0;

  Future<void> _open() async {
    final p = widget.place;
    final at = '${p.latitude},${p.longitude}';
    final name = p.title.isEmpty ? '' : '(${Uri.encodeComponent(p.title)})';
    final opened = await launchFirst([
      Uri.parse('geo:$at?q=$at$name'),
      Uri.parse('https://maps.google.com/?q=$at'),
    ]);
    if (!opened && mounted) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(context.l10n.mediaNoMapApp)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = widget.place;
    final l10n = context.l10n;
    return Semantics(
      button: true,
      label: p.isVenue ? l10n.mediaVenueOpens : l10n.mediaLocationOpens,
      child: InkWell(
        onTap: () => unawaited(_open()),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AspectRatio(
                aspectRatio: 2,
                child: LayoutBuilder(
                  builder: (context, box) {
                    final width = box.maxWidth.round();
                    if (_map == null || _asked != width) {
                      _asked = width;
                      _map = widget.gateway.mapThumbnail(
                        p.latitude,
                        p.longitude,
                        width: width,
                        height: width ~/ 2,
                      );
                    }
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(color: scheme.surfaceContainerHighest),
                        FutureBuilder<FileRef>(
                          future: _map,
                          builder: (context, map) {
                            final file = map.data;
                            if (file == null) return const SizedBox.shrink();
                            return Downloaded(
                              key: ValueKey(file.id),
                              file: file,
                              gateway: widget.gateway,
                              placeholder: const SizedBox.shrink(),
                              builder: (context, path) => SizedFileImage(
                                path: path,
                                width: file.width,
                                height: file.height,
                              ),
                            );
                          },
                        ),
                        // The pin stands on the place with its point, so it is lifted by
                        // half its height.
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 32),
                            child: Icon(
                              Icons.location_on,
                              size: 36,
                              color: scheme.error,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            if (p.isVenue)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (p.title.isNotEmpty)
                      Text(
                        p.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (p.address.isNotEmpty)
                      Text(
                        p.address,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A shared contact: the disc with its initials, the name and the phone number. A tap
/// dials the number.
class ContactView extends StatelessWidget {
  const ContactView({super.key, required this.contact, required this.gateway});
  final ContactMedia contact;
  final TelegramGateway gateway;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = contact.name.isEmpty ? contact.phone : contact.name;
    final digits = contact.phone.replaceAll(RegExp(r'[^0-9+]'), '');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: ChannelAvatar(
        photo: null,
        title: name,
        gateway: gateway,
        colorId: contact.userId == 0 ? null : contact.userId,
        radius: 20,
      ),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: contact.phone.isEmpty || contact.name.isEmpty
          ? null
          : Text(contact.phone, style: TextStyle(color: scheme.primary)),
      onTap: digits.isEmpty
          ? null
          : () => unawaited(launchFirst([Uri(scheme: 'tel', path: digits)])),
    );
  }
}

/// A game: its title, what it says about itself and its picture. The app does not talk to
/// the game's bot, so there is nothing to play here.
class GameView extends StatelessWidget {
  const GameView({super.key, required this.game, required this.gateway});
  final GameMedia game;
  final TelegramGateway gateway;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final photo = game.photo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          context.l10n.mediaGame,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: scheme.primary,
          ),
        ),
        if (game.title.isNotEmpty)
          Text(
            game.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        if (game.description.isNotEmpty)
          Text(
            game.description,
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, height: 1.25),
          ),
        if (photo != null && photo.sizes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: PhotoView(
              file: pickPhotoSize(
                photo.sizes,
                MediaQuery.sizeOf(context).width,
                pixelRatio: MediaQuery.devicePixelRatioOf(context),
              ),
              gateway: gateway,
              miniature: photo.miniature,
            ),
          ),
      ],
    );
  }
}

/// A checklist: its title, its tasks with a tick on the ones that are done, and how many
/// of them are. The app ticks nothing itself.
class ChecklistView extends StatelessWidget {
  const ChecklistView({super.key, required this.list});
  final ChecklistMedia list;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = list.tasks.where((t) => t.done).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (list.title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              list.title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        for (final task in list.tasks)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Semantics(
              checked: task.done,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    task.done
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: task.done ? scheme.primary : scheme.outline,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      task.text,
                      style: const TextStyle(fontSize: 15, height: 1.25),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (list.tasks.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              context.l10n.mediaChecklistDone(done, list.tasks.length),
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}
