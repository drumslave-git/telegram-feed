import 'package:flutter/material.dart';

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
      title: const Text('Log out?'),
      content: const Text(
        'Your feeds, rules, settings and the AI key on this device are deleted, and '
        'Google Drive sync is turned off. A copy stays in your Drive if sync was on.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        DestructiveButton(
          onPressed: () => Navigator.pop(context, true),
          label: 'Log out',
        ),
      ],
    ),
  );
  if (ok ?? false) await onLogOut();
}
