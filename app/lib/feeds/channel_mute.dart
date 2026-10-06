import 'dart:async';

import 'package:flutter/material.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../l10n/l10n.dart';

/// Whether channels are muted in Telegram, as this app last set them. The bar under a
/// channel's timeline and the switch on its info screen show the same state;
/// [Channel.isMuted] is what the list knew when it was read.
abstract final class ChannelMutes {
  static final changes = ValueNotifier<Map<int, bool>>(const {});

  static bool of(Channel channel) =>
      changes.value[channel.chatId] ?? channel.isMuted;

  /// Mutes or unmutes [chatId] in Telegram; the state goes back when Telegram refuses,
  /// and the error is rethrown.
  static Future<void> set(
    TelegramGateway gateway,
    int chatId, {
    required bool muted,
  }) async {
    final before = changes.value;
    changes.value = {...before, chatId: muted};
    try {
      await gateway.setChannelMuted(chatId, muted: muted);
    } on Object {
      changes.value = before;
      rethrow;
    }
  }

  /// [set], with a snack bar of [context] when Telegram refuses.
  static Future<void> setOrSay(
    BuildContext context,
    TelegramGateway gateway,
    int chatId, {
    required bool muted,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      await set(gateway, chatId, muted: muted);
    } on Object catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.channelMuteFailed('$e'))),
      );
    }
  }
}

/// The official app's bar under a channel's chat for a subscriber: MUTE, or UNMUTE for
/// a channel muted in Telegram.
class ChannelMuteBar extends StatelessWidget {
  const ChannelMuteBar({
    super.key,
    required this.gateway,
    required this.channel,
  });
  final TelegramGateway gateway;
  final Channel channel;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: ChannelMutes.changes,
    builder: (context, _, _) {
      final muted = ChannelMutes.of(channel);
      final l10n = context.l10n;
      return Material(
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          top: false,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: SizedBox(
              height: 48,
              width: double.infinity,
              child: TextButton(
                style: TextButton.styleFrom(
                  shape: const RoundedRectangleBorder(),
                ),
                onPressed: () => unawaited(
                  ChannelMutes.setOrSay(
                    context,
                    gateway,
                    channel.chatId,
                    muted: !muted,
                  ),
                ),
                child: Text(muted ? l10n.channelUnmute : l10n.channelMute),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// The switch on a channel's info screen: on while Telegram notifies for the channel.
class ChannelNotificationsSwitch extends StatelessWidget {
  const ChannelNotificationsSwitch({
    super.key,
    required this.gateway,
    required this.channel,
  });
  final TelegramGateway gateway;
  final Channel channel;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: ChannelMutes.changes,
    builder: (context, _, _) {
      final muted = ChannelMutes.of(channel);
      final l10n = context.l10n;
      return SwitchListTile(
        secondary: Icon(
          muted
              ? Icons.notifications_off_outlined
              : Icons.notifications_outlined,
        ),
        title: Text(l10n.channelInfoNotifications),
        subtitle: Text(
          muted ? l10n.channelInfoMutedNote : l10n.channelInfoUnmutedNote,
        ),
        value: !muted,
        onChanged: (on) => unawaited(
          ChannelMutes.setOrSay(context, gateway, channel.chatId, muted: !on),
        ),
      );
    },
  );
}
