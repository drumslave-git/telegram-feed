import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../home/unread_badge.dart';
import '../host/accounts.dart';
import '../l10n/l10n.dart';
import '../service/core_service.dart' show appPaths;
import '../widgets/destructive_button.dart';

/// The other accounts of this device, under the profile in Settings as the official app
/// lists them: photo, name, phone and the count of unread channels each had when it was
/// last in use, then "Add an account" while there is room for one. A tap switches to an
/// account; a long press offers to take it off the device. Switching takes the core and
/// the database of this account down and brings the other one's up, so Settings closes
/// when it happens.
class AccountRows extends StatefulWidget {
  const AccountRows({super.key, this.store, this.onSwitched});

  /// The app's own lives beside the databases; tests pass theirs.
  final AccountStore? store;

  /// Handed down from the root by [AccountSwitch]; tests pass their own.
  final Future<void> Function()? onSwitched;

  @override
  State<AccountRows> createState() => _AccountRowsState();
}

class _AccountRowsState extends State<AccountRows> {
  AccountStore? _store;
  List<AccountInfo> _others = const [];
  int _count = 1;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  Future<void> _read() async {
    try {
      final store = widget.store ?? AccountStore((await appPaths()).support);
      // Settings opens only in an account that is logged in, so any other that never
      // logged in is one whose login was given up.
      await store.dropNeverLoggedIn();
      final now = await store.load();
      if (!mounted) return;
      setState(() {
        _store = store;
        _count = now.accounts.length;
        _others = [
          for (final a in now.accounts)
            if (a.id != now.active) a,
        ];
      });
    } on Object {
      // No paths (widget tests, desktop): only this account.
    }
  }

  /// The profile the account was last seen with, or its number on this device.
  static String _name(AccountInfo a, AppLocalizations l10n) =>
      a.title.isEmpty ? l10n.accountsNumbered(a.id) : a.title;

  Future<void> Function()? get _switched =>
      widget.onSwitched ?? AccountSwitch.of(context)?.onSwitched;

  Future<void> _use(AccountInfo account) async {
    final store = _store;
    if (store == null || _busy) return;
    final switched = _switched;
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    await store.setActive(account.id);
    if (switched != null) await switched();
    if (!mounted) return;
    setState(() => _busy = false);
    // The app is on the other account now; Settings belongs to the one that went.
    navigator.popUntil((route) => route.isFirst);
  }

  Future<void> _add() async {
    final store = _store;
    if (store == null || _busy) return;
    final switched = _switched;
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    final added = await store.add();
    if (added != null && switched != null) await switched();
    if (!mounted) return;
    setState(() => _busy = false);
    if (added == null) {
      await _read();
      return;
    }
    // The new account has no session, so the app asks it to log in.
    navigator.popUntil((route) => route.isFirst);
  }

  Future<void> _remove(AccountInfo account) async {
    final store = _store;
    if (store == null || _busy) return;
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.accountsRemoveTitle(_name(account, l10n))),
        content: Text(l10n.accountsRemoveText),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.commonCancel),
          ),
          DestructiveButton(
            onPressed: () => Navigator.pop(context, true),
            label: l10n.commonRemove,
          ),
        ],
      ),
    );
    if (!(ok ?? false)) return;
    await store.remove(account.id);
    await _read();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final account in _others)
          ListTile(
            key: ValueKey('account-${account.id}'),
            leading: AccountPhoto(account: account, name: _name(account, l10n)),
            title: Text(
              _name(account, l10n),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: account.phone.isEmpty ? null : Text(account.phone),
            trailing: account.unread > 0 ? UnreadBadge(account.unread) : null,
            onTap: _busy ? null : () => unawaited(_use(account)),
            onLongPress: _busy ? null : () => unawaited(_remove(account)),
          ),
        if (_count < AccountStore.maxAccounts)
          ListTile(
            leading: const Icon(Icons.add),
            title: Text(l10n.accountsAdd),
            enabled: !_busy,
            onTap: () => unawaited(_add()),
          ),
      ],
    );
  }
}

/// The copy of an account's profile photo, or its initials on a disc while it has none.
class AccountPhoto extends StatelessWidget {
  const AccountPhoto({
    super.key,
    required this.account,
    required this.name,
    this.radius = 20,
  });
  final AccountInfo account;
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final words = name.trim().split(RegExp(r'\s+'))
      ..removeWhere((w) => w.isEmpty);
    final letters = words.isEmpty
        ? '?'
        : words.length == 1
        ? words.first.characters.first.toUpperCase()
        : (words.first.characters.first + words[1].characters.first)
              .toUpperCase();
    final file = account.photo.isEmpty ? null : File(account.photo);
    final has = file != null && file.existsSync();
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.secondaryContainer,
      foregroundColor: scheme.onSecondaryContainer,
      backgroundImage: has
          ? ResizeImage(
              FileImage(file),
              width: (radius * 2 * MediaQuery.devicePixelRatioOf(context))
                  .ceil(),
              policy: ResizeImagePolicy.fit,
            )
          : null,
      child: has
          ? null
          : ExcludeSemantics(
              child: Text(letters, style: TextStyle(fontSize: radius * 0.7)),
            ),
    );
  }
}
