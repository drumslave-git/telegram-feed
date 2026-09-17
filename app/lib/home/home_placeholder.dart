import 'package:flutter/material.dart';

/// App-bar action that confirms and runs a logout.
class LogOutAction extends StatelessWidget {
  const LogOutAction({super.key, required this.onLogOut});
  final Future<void> Function() onLogOut;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Log out',
      icon: const Icon(Icons.logout),
      onPressed: () async {
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
      },
    );
  }
}
