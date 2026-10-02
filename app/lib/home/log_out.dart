import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../widgets/destructive_button.dart';

/// Asks before a logout and runs it on a yes: the official app's Log Out in the Settings
/// menu.
Future<void> confirmLogOut(
  BuildContext context,
  Future<void> Function() onLogOut,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.l10n.logOutTitle),
      content: Text(context.l10n.logOutMessage),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(context.l10n.commonCancel),
        ),
        DestructiveButton(
          onPressed: () => Navigator.pop(context, true),
          label: context.l10n.logOutAction,
        ),
      ],
    ),
  );
  if (!(ok ?? false)) return;
  await onLogOut();
  // Whatever was open over the home screen goes: the login screen is underneath it.
  if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
}
