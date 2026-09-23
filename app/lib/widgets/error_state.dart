import 'package:flutter/material.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

/// The sentence for a code Telegram's API returns, or null when the app has none.
String? _known(String message) {
  if (message.startsWith('Too Many Requests') ||
      message.startsWith('FLOOD_WAIT')) {
    return 'Telegram is rate-limiting this account. Wait a minute and try again.';
  }
  return switch (message) {
    'PHONE_NUMBER_INVALID' => 'That phone number is not valid.',
    'PHONE_NUMBER_BANNED' => 'Telegram has banned that phone number.',
    'PHONE_NUMBER_FLOOD' =>
      'That number has asked for too many codes today. Try again tomorrow.',
    'PHONE_NUMBER_OCCUPIED' =>
      'That number already belongs to another account.',
    'PHONE_CODE_INVALID' || 'PHONE_CODE_EMPTY' => 'Wrong code.',
    'PHONE_CODE_EXPIRED' => 'The code expired. Ask for a new one.',
    'PASSWORD_HASH_INVALID' => 'Wrong password.',
    'PASSWORD_RECOVERY_NA' => 'This account has no recovery email, so the password cannot be reset here.',
    'API_ID_INVALID' =>
      'This build has no valid Telegram api_id/api_hash (see README).',
    'CHAT_ID_INVALID' ||
    'CHANNEL_INVALID' ||
    'PEER_ID_INVALID' => 'Telegram does not know that channel any more.',
    'CHANNEL_PRIVATE' =>
      'That channel is private now, or the account has left it.',
    'MESSAGE_ID_INVALID' || 'MSG_ID_INVALID' => 'That post no longer exists.',
    'CHAT_WRITE_FORBIDDEN' ||
    'CHAT_SEND_PLAIN_FORBIDDEN' ||
    'CHAT_ADMIN_REQUIRED' =>
      'This channel does not let the account write here.',
    'USER_BANNED_IN_CHANNEL' => 'The account is banned in that channel.',
    'REACTION_INVALID' => 'This channel does not allow that reaction.',
    'client closed' ||
    'Request aborted' => 'The connection to Telegram closed. Try again.',
    _ => null,
  };
}

/// One line for a snackbar: the sentence for a code the app knows, otherwise what the
/// app was doing with the code in brackets, so nothing is lost when reporting it.
String telegramErrorLine(Object error, {required String what}) {
  final message = error is TelegramException ? error.message : '$error';
  return _known(message) ?? '$what ($message)';
}

/// Shows [telegramErrorLine] on [messenger], with an optional Retry action.
void showTelegramError(
  ScaffoldMessengerState messenger,
  Object error, {
  required String what,
  VoidCallback? onRetry,
}) {
  messenger.showSnackBar(
    SnackBar(
      content: Text(telegramErrorLine(error, what: what)),
      action: onRetry == null
          ? null
          : SnackBarAction(label: 'Retry', onPressed: onRetry),
    ),
  );
}

/// What went wrong, in the app's own words, with the code underneath and a way to try
/// again. Every screen that can fail to load uses it, so failures read the same way.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.what,
    this.message,
    this.onRetry,
    this.compact = false,
  });

  /// Plain sentence for what the app could not do, e.g. "Could not load the channels."
  final String what;

  /// The raw message from Telegram, shown small underneath.
  final String? message;
  final VoidCallback? onRetry;

  /// A single line with a Retry link, for a list footer instead of a whole screen.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final raw = message;
    final known = raw == null ? null : _known(raw);
    if (compact) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              known ?? what,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              known ?? what,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            if (raw != null) ...[
              const SizedBox(height: 8),
              Text(
                raw,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
