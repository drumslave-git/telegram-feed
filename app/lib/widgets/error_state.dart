import 'package:flutter/material.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../l10n/l10n.dart';

/// The sentence for a code Telegram's API returns, or null when the app has none.
String? _known(String message, AppLocalizations l10n) {
  if (message.startsWith('Too Many Requests') ||
      message.startsWith('FLOOD_WAIT') ||
      message.startsWith('FLOOD_PREMIUM_WAIT')) {
    // Telegram says how long to wait, and so does the app.
    final wait = RegExp(r'(?:retry after |WAIT_)(\d+)')
        .firstMatch(message)
        ?.group(1);
    final seconds = int.tryParse(wait ?? '') ?? 0;
    return switch (seconds) {
      <= 0 => l10n.errorRateLimited,
      < 60 => l10n.errorFloodWaitSeconds(seconds),
      < 3600 => l10n.errorFloodWaitMinutes((seconds / 60).ceil()),
      _ => l10n.errorFloodWaitHours((seconds / 3600).ceil()),
    };
  }
  return switch (message) {
    'PHONE_NUMBER_INVALID' => l10n.errorPhoneNumberInvalid,
    'PHONE_NUMBER_BANNED' => l10n.errorPhoneNumberBanned,
    'PHONE_NUMBER_FLOOD' => l10n.errorPhoneNumberFlood,
    'PHONE_NUMBER_OCCUPIED' => l10n.errorPhoneNumberOccupied,
    'PHONE_CODE_INVALID' || 'PHONE_CODE_EMPTY' => l10n.errorCodeInvalid,
    'PHONE_CODE_EXPIRED' => l10n.errorCodeExpired,
    'PASSWORD_HASH_INVALID' => l10n.errorPasswordInvalid,
    'PASSWORD_RECOVERY_NA' => l10n.errorPasswordRecoveryUnavailable,
    'API_ID_INVALID' => l10n.errorApiIdInvalid,
    'CHAT_ID_INVALID' ||
    'CHANNEL_INVALID' ||
    'PEER_ID_INVALID' => l10n.errorChannelUnknown,
    'CHANNEL_PRIVATE' => l10n.errorChannelPrivate,
    'MESSAGE_ID_INVALID' || 'MSG_ID_INVALID' => l10n.errorPostGone,
    'CHAT_WRITE_FORBIDDEN' ||
    'CHAT_SEND_PLAIN_FORBIDDEN' ||
    'CHAT_ADMIN_REQUIRED' => l10n.errorWriteForbidden,
    'USER_BANNED_IN_CHANNEL' => l10n.errorBannedInChannel,
    'REACTION_INVALID' => l10n.errorReactionInvalid,
    'client closed' || 'Request aborted' => l10n.errorConnectionClosed,
    _ => null,
  };
}

/// One line for a snackbar: the sentence for a code the app knows, otherwise what the
/// app was doing with the code in brackets, so nothing is lost when reporting it. The
/// sentences are in the language of [l10n], English without one.
String telegramErrorLine(
  Object error, {
  required String what,
  AppLocalizations? l10n,
}) {
  final message = error is TelegramException ? error.message : '$error';
  return _known(message, l10n ?? lookupAppLocalizations(const Locale('en'))) ??
      '$what ($message)';
}

/// Shows [telegramErrorLine] on [messenger], with an optional Retry action, in the
/// language of the messenger's own context.
void showTelegramError(
  ScaffoldMessengerState messenger,
  Object error, {
  required String what,
  VoidCallback? onRetry,
}) {
  final l10n = messenger.mounted
      ? messenger.context.l10n
      : lookupAppLocalizations(const Locale('en'));
  messenger.showSnackBar(
    SnackBar(
      content: Text(telegramErrorLine(error, what: what, l10n: l10n)),
      action: onRetry == null
          ? null
          : SnackBarAction(label: l10n.commonRetry, onPressed: onRetry),
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
    final l10n = context.l10n;
    final known = raw == null ? null : _known(raw, l10n);
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
            TextButton(onPressed: onRetry, child: Text(l10n.commonRetry)),
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
                label: Text(l10n.commonRetry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
