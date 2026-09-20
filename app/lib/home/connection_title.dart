import 'package:flutter/material.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

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

  static String? words(ConnectionStatus status) => switch (status) {
    ConnectionStatus.ready => null,
    ConnectionStatus.waitingForNetwork => 'Waiting for network…',
    ConnectionStatus.connecting => 'Connecting…',
    ConnectionStatus.connectingToProxy => 'Connecting to proxy…',
    ConnectionStatus.updating => 'Updating…',
  };

  @override
  Widget build(BuildContext context) => StreamBuilder<ConnectionStatus>(
    stream: gateway.connection,
    builder: (context, snap) {
      final said = words(snap.data ?? ConnectionStatus.ready);
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
