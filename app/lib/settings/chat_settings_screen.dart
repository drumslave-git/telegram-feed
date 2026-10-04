import 'dart:async';

import 'package:app_db/app_db.dart';
import 'package:core/core.dart' show TimelineItem;
import 'package:flutter/material.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../app_name.dart';
import '../feeds/post_card.dart'
    show ChatColors, PostCard, defaultQuickReaction, standardReactions;
import '../feeds/text_scale.dart';
import '../l10n/l10n.dart';
import 'settings_tiles.dart';

/// How posts look: the text size of posts and the theme, the official app's Chat Settings.
class ChatSettingsScreen extends StatelessWidget {
  const ChatSettingsScreen({
    super.key,
    required this.db,
    required this.gateway,
  });
  final AppDatabase db;

  /// For the preview's post, which is drawn as the timeline draws one.
  final TelegramGateway gateway;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.chatSettingsTitle)),
      body: ListView(
        children: [
          SettingsHeader(l10n.chatSettingsTextSize),
          StreamBuilder<String?>(
            stream: db.watchSetting(SettingKeys.postTextScale),
            builder: (context, snap) => _TextSize(
              db: db,
              gateway: gateway,
              factor: PostTextScale.parse(snap.data),
            ),
          ),
          const Divider(),
          StreamBuilder<String?>(
            stream: db.watchSetting(SettingKeys.quickReaction),
            builder: (context, snap) {
              final quick = (snap.data ?? '').isEmpty
                  ? defaultQuickReaction
                  : snap.data!;
              return ListTile(
                title: Text(l10n.chatSettingsQuickReaction),
                subtitle: Text(l10n.chatSettingsQuickReactionInfo),
                trailing: Text(quick, style: const TextStyle(fontSize: 24)),
                onTap: () async {
                  final picked = await showDialog<String>(
                    context: context,
                    builder: (context) => SimpleDialog(
                      title: Text(l10n.chatSettingsQuickReaction),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Wrap(
                            children: [
                              for (final e in standardReactions)
                                InkResponse(
                                  onTap: () => Navigator.pop(context, e),
                                  radius: 22,
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: e == quick
                                          ? Theme.of(context)
                                                .colorScheme
                                                .primaryContainer
                                          : null,
                                    ),
                                    child: Text(
                                      e,
                                      style: const TextStyle(fontSize: 24),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                  if (picked != null) {
                    await db.setSetting(SettingKeys.quickReaction, picked);
                  }
                },
              );
            },
          ),
          const Divider(),
          SettingsHeader(l10n.chatSettingsTheme),
          StreamBuilder<String?>(
            stream: db.watchSetting(SettingKeys.themeMode),
            builder: (context, snap) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'system',
                    label: Text(l10n.chatSettingsThemeSystem),
                    icon: const Icon(Icons.brightness_auto),
                  ),
                  ButtonSegment(
                    value: 'light',
                    label: Text(l10n.chatSettingsThemeLight),
                    icon: const Icon(Icons.light_mode),
                  ),
                  ButtonSegment(
                    value: 'dark',
                    label: Text(l10n.chatSettingsThemeDark),
                    icon: const Icon(Icons.dark_mode),
                  ),
                ],
                selected: {snap.data ?? 'system'},
                onSelectionChanged: (s) =>
                    db.setSetting(SettingKeys.themeMode, s.first),
              ),
            ),
          ),
          SettingsFooter(l10n.chatSettingsThemeFooter),
        ],
      ),
    );
  }
}

/// The text size of posts: the slider from 12 to 30 with the size beside it, and under it
/// a post as the timeline draws one, which follows the slider while it moves, as the
/// official app's preview does. The size is written once the finger lifts: a write on
/// every tick sent the whole app through the database and back twenty times a drag.
class _TextSize extends StatefulWidget {
  const _TextSize({
    required this.db,
    required this.gateway,
    required this.factor,
  });
  final AppDatabase db;
  final TelegramGateway gateway;

  /// The saved value, which the slider follows while it is not being dragged.
  final double factor;

  @override
  State<_TextSize> createState() => _TextSizeState();
}

class _TextSizeState extends State<_TextSize> {
  int? _dragging;

  /// The post of the preview. Its time is the moment the screen opened.
  late final _sample = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final size = _dragging ?? PostTextScale.sizeOf(widget.factor);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Expanded(
                child: Slider(
                  value: size.toDouble(),
                  min: PostTextScale.minSize.toDouble(),
                  max: PostTextScale.maxSize.toDouble(),
                  divisions: PostTextScale.maxSize - PostTextScale.minSize,
                  label: '$size',
                  onChanged: (v) => setState(() => _dragging = v.round()),
                  onChangeEnd: (v) {
                    unawaited(
                      widget.db.setSetting(
                        SettingKeys.postTextScale,
                        PostTextScale.factorOf(v.round()).toStringAsFixed(4),
                      ),
                    );
                    setState(() => _dragging = null);
                  },
                ),
              ),
              SizedBox(
                width: 40,
                child: Text(
                  '$size',
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
        // A post on the timeline's backdrop, at the size the slider stands on.
        ColoredBox(
          color: ChatColors.of(context).background,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: PostTextScale.preview(
              factor: PostTextScale.factorOf(size),
              child: IgnorePointer(
                child: PostCard(
                  item: TimelineItem(
                    Post(
                      chatId: 1,
                      messageId: 1,
                      date: _sample,
                      text: l10n.chatSettingsTextSizePreview,
                      views: 1,
                    ),
                  ),
                  channelTitle: appName,
                  gateway: widget.gateway,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
