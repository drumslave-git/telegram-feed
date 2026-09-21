import 'package:flutter/material.dart';

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
        'Feeds, read positions and settings on this device are deleted.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Log out'),
        ),
      ],
    ),
  );
  if (ok ?? false) await onLogOut();
}
