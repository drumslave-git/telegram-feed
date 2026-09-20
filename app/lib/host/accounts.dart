import 'package:flutter/material.dart';

import 'dart:convert';
import 'dart:io';

/// One Telegram account on this device. The id decides where its data lives: account 1 uses
/// the paths the app has always used, so an install that predates several accounts keeps
/// everything where it left it.
class AccountInfo {
  const AccountInfo({required this.id, this.label = ''});
  final int id;

  /// What the switcher shows; the account's own name once it has logged in.
  final String label;

  Map<String, Object?> toJson() => {'id': id, 'label': label};

  static AccountInfo fromJson(Map<Object?, Object?> m) => AccountInfo(
    id: (m['id'] as num).toInt(),
    label: (m['label'] as String?) ?? '',
  );
}

/// The accounts of this device and which one is in use, in a small file beside the
/// per-account databases. It has to live outside them: it says which of them to open.
class AccountStore {
  const AccountStore(this.supportDirectory);
  final String supportDirectory;

  /// As many as the official app holds.
  static const maxAccounts = 4;

  String get _path => '$supportDirectory/accounts.json';

  Future<({List<AccountInfo> accounts, int active})> load() async {
    final file = File(_path);
    if (!file.existsSync()) {
      return (accounts: const [AccountInfo(id: 1)], active: 1);
    }
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return (accounts: const [AccountInfo(id: 1)], active: 1);
      final accounts = [
        for (final a in (raw['accounts'] as List? ?? const []))
          if (a is Map<Object?, Object?>) AccountInfo.fromJson(a),
      ];
      if (accounts.isEmpty) {
        return (accounts: const [AccountInfo(id: 1)], active: 1);
      }
      final active = (raw['active'] as num?)?.toInt() ?? accounts.first.id;
      return (
        accounts: accounts,
        active: accounts.any((a) => a.id == active)
            ? active
            : accounts.first.id,
      );
    } on Object {
      // A broken file must not lock the reader out of their own app.
      return (accounts: const [AccountInfo(id: 1)], active: 1);
    }
  }

  Future<int> activeId() async => (await load()).active;

  Future<void> _save(List<AccountInfo> accounts, int active) async {
    await File(_path).writeAsString(
      jsonEncode({
        'active': active,
        'accounts': [for (final a in accounts) a.toJson()],
      }),
    );
  }

  Future<void> setActive(int id) async {
    final now = await load();
    if (!now.accounts.any((a) => a.id == id)) return;
    await _save(now.accounts, id);
  }

  Future<void> rename(int id, String label) async {
    final now = await load();
    await _save([
      for (final a in now.accounts)
        if (a.id == id) AccountInfo(id: id, label: label) else a,
    ], now.active);
  }

  /// Adds an account and makes it the one in use; null when there is no room left.
  Future<AccountInfo?> add() async {
    final now = await load();
    if (now.accounts.length >= maxAccounts) return null;
    final ids = {for (final a in now.accounts) a.id};
    var id = 1;
    while (ids.contains(id)) {
      id++;
    }
    final added = AccountInfo(id: id);
    await _save([...now.accounts, added], id);
    return added;
  }

  /// Takes the account off this device, with its TDLib data and its feeds. The last one
  /// cannot go: the app would have nothing to open.
  Future<bool> remove(
    int id, {
    required String tdlib,
    required String db,
  }) async {
    final now = await load();
    if (now.accounts.length <= 1) return false;
    final left = [
      for (final a in now.accounts)
        if (a.id != id) a,
    ];
    final active = now.active == id ? left.first.id : now.active;
    await _save(left, active);
    for (final path in [db, '$db-wal', '$db-shm']) {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    }
    final dir = Directory(tdlib);
    if (dir.existsSync()) await dir.delete(recursive: true);
    return true;
  }
}

/// Lets a screen deep in the app ask for the account to be switched. The root holds the
/// host, so only it can take the old core down and bring a new one up.
class AccountSwitch extends InheritedWidget {
  const AccountSwitch({
    super.key,
    required this.onSwitched,
    required super.child,
  });

  /// Called once the store's active account has been changed.
  final Future<void> Function() onSwitched;

  static AccountSwitch? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AccountSwitch>();

  @override
  bool updateShouldNotify(AccountSwitch old) => false;
}
