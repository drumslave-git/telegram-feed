import 'package:flutter/material.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../l10n/l10n.dart';

/// An app-bar title that says what TDLib is doing whenever it is not connected, the way
/// the official app replaces the chat's name with "Connecting...". A dead connection would
/// otherwise look like an empty feed.
class ConnectionTitle extends StatelessWidget {
  const ConnectionTitle({
    super.key,
    required this.gateway,
    required this.title,
  });
  final TelegramGateway gateway;

  /// What the bar says while the connection is ready.
  final Widget title;

  static String? words(ConnectionStatus status, AppLocalizations l10n) =>
      switch (status) {
        ConnectionStatus.ready => null,
        ConnectionStatus.waitingForNetwork => l10n.homeWaitingForNetwork,
        ConnectionStatus.connecting => l10n.homeConnecting,
        ConnectionStatus.connectingToProxy => l10n.homeConnectingToProxy,
        ConnectionStatus.updating => l10n.homeUpdating,
      };

  @override
  Widget build(BuildContext context) => StreamBuilder<ConnectionStatus>(
    stream: gateway.connection,
    builder: (context, snap) {
      final said = words(snap.data ?? ConnectionStatus.ready, context.l10n);
      if (said == null) return title;
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DefaultTextStyle.merge(
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            child: title,
          ),
          Text(
            said,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.normal,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    },
  );
}
