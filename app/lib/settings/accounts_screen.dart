import 'dart:async';

import 'package:flutter/material.dart';

import '../host/accounts.dart';
import '../service/core_service.dart' show appPaths;
import '../widgets/destructive_button.dart';

/// The accounts of this device: which one is in use, one more up to four, and taking one
/// off the device again (H-35). Switching takes the core and the database of this account
/// down and brings the other one's up, so the screen closes itself when it happens.
class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key, required this.store, this.onSwitched});
  final AccountStore store;

  /// Handed down from the root by [AccountSwitch]; tests pass their own.
  final Future<void> Function()? onSwitched;

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  List<AccountInfo> _accounts = const [];
  int _active = 1;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  Future<void> _read() async {
    final now = await widget.store.load();
    if (mounted) {
      setState(() {
        _accounts = now.accounts;
        _active = now.active;
      });
    }
  }

  Future<void> Function()? get _switched =>
      widget.onSwitched ?? AccountSwitch.of(context)?.onSwitched;

  Future<void> _use(int id) async {
    if (id == _active || _busy) return;
    final switched = _switched;
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    await widget.store.setActive(id);
    if (switched != null) await switched();
    if (!mounted) return;
    setState(() => _busy = false);
    // The app is on the other account now; this screen belongs to the one that went.
    navigator.popUntil((route) => route.isFirst);
  }

  Future<void> _add() async {
    final messenger = ScaffoldMessenger.of(context);
    final added = await widget.store.add();
    if (added == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Four accounts is as many as the app holds.'),
        ),
      );
      return;
    }
    await _read();
    // The new account has no session, so the app asks it to log in.
    final switched = _switched;
    if (switched != null) await switched();
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _remove(AccountInfo account) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove account ${account.id}?'),
        content: const Text(
          'Its session, feeds, rules and cached posts are deleted from this device. '
          'The Telegram account itself stays as it is.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          DestructiveButton(
            onPressed: () => Navigator.pop(context, true),
            label: 'Remove',
          ),
        ],
      ),
    );
    if (!(ok ?? false)) return;
    final paths = await appPaths(account.id);
    final removed = await widget.store.remove(
      account.id,
      tdlib: paths.tdlib,
      db: paths.db,
    );
    if (!removed) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('The last account cannot be removed; log out instead.'),
        ),
      );
      return;
    }
    final wasActive = account.id == _active;
    await _read();
    if (!wasActive) return;
    final switched = _switched;
    if (switched != null) await switched();
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Accounts')),
    body: ListView(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Each account has its own session, feeds and rules on this device. Switching '
            'takes the watcher down and brings it up again on the other account.',
          ),
        ),
        for (final account in _accounts)
          ListTile(
            leading: Icon(
              account.id == _active
                  ? Icons.check_circle
                  : Icons.account_circle_outlined,
              color: account.id == _active
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            title: Text(
              account.label.isEmpty ? 'Account ${account.id}' : account.label,
            ),
            subtitle: Text(
              account.id == _active ? 'In use' : 'Tap to switch to it',
            ),
            onTap: _busy ? null : () => unawaited(_use(account.id)),
            trailing: _accounts.length <= 1
                ? null
                : IconButton(
                    tooltip: 'Remove from this device',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _busy ? null : () => unawaited(_remove(account)),
                  ),
          ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.person_add_alt),
          title: const Text('Add an account'),
          subtitle: Text(
            _accounts.length >= AccountStore.maxAccounts
                ? 'Four is as many as the app holds'
                : 'Logs in as another account and switches to it',
          ),
          enabled: !_busy && _accounts.length < AccountStore.maxAccounts,
          onTap: () => unawaited(_add()),
        ),
      ],
    ),
  );
}
