import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:core/native_isolate.dart' show OtherAccount;
import 'package:flutter/foundation.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../host/accounts.dart';
import 'rule_alerts.dart';

/// The other logged-in accounts the core is to serve beside the one in use: every
/// account that has logged in, so its rules go on notifying while another one is open.
Future<List<OtherAccount>> otherAccountsToServe(String support) async {
  final store = AccountStore(support);
  final (:accounts, :active) = await store.load();
  return [
    for (final a in accounts)
      if (a.id != active && a.loggedIn == true)
        OtherAccount(
          id: a.id,
          databaseDirectory: store.tdlibOf(a.id),
          filesDirectory: '${store.tdlibOf(a.id)}/files',
          appDatabasePath: store.dbOf(a.id),
        ),
  ];
}

/// The other logged-in accounts as the host of the core watches them (ARCHITECTURE 9):
/// a client to each one's server in the core and its own database, for its alerts, and
/// every account's channels, for the number on the app's icon. The pause is one for all
/// of them: the others follow the account in use.
class AccountWatch {
  AccountWatch._(this._main, this._store, this.activeId, this.activeName);

  final CoreClient _main;
  final AccountStore _store;

  /// The account in use, and what it is called.
  final int activeId;
  final String activeName;
  final _others =
      <({int id, String name, CoreClient client, AppDatabase db})>[];
  StreamSubscription<bool>? _pause;

  /// Connects to the accounts the core at [main] serves beside its own.
  static Future<AccountWatch> open(
    CoreClient main, {
    required String support,
  }) async {
    final store = AccountStore(support);
    final (:accounts, :active) = await store.load();
    String nameOf(int id) =>
        accounts.where((a) => a.id == id).map((a) => a.title).firstOrNull ?? '';
    final watch = AccountWatch._(main, store, active, nameOf(active));
    Map<int, SendPort> ports;
    try {
      ports = await main.otherAccounts().timeout(const Duration(seconds: 5));
    } on Object catch (e) {
      debugPrint('accounts: the core serves no others: $e');
      return watch;
    }
    for (final MapEntry(key: id, value: port) in ports.entries) {
      try {
        final client = await CoreClient.connect(port)
            .timeout(const Duration(seconds: 5));
        watch._others.add((
          id: id,
          name: nameOf(id),
          client: client,
          db: AppDatabase(appDatabaseFile(File(store.dbOf(id)))),
        ));
      } on Object catch (e) {
        debugPrint('accounts: account $id not watched: $e');
      }
    }
    await watch._followPause();
    return watch;
  }

  /// Whether another account is watched: the notifications then say which account.
  bool get any => _others.isNotEmpty;

  /// What the alerts need of each other account.
  List<AlertAccount> get alerts => [
    for (final o in _others)
      AlertAccount.of(o.client, db: o.db, id: o.id, name: o.name),
  ];

  /// The channels of every account, for the number on the app's icon. On the way the
  /// list of accounts learns how many channels of each other account have unread posts,
  /// which Settings shows.
  Future<List<Channel>> channels() async {
    final all = [...await _main.myChannels()];
    for (final o in _others) {
      try {
        final theirs = await o.client.myChannels();
        all.addAll(theirs);
        final unread = theirs
            .where((c) => c.unreadCount > 0 || c.isMarkedUnread)
            .length;
        if (_unread[o.id] != unread) {
          _unread[o.id] = unread;
          await AccountRecorder(_store, o.id).unread(unread);
        }
      } on Object catch (e) {
        debugPrint('accounts: channels of account ${o.id} not read: $e');
      }
    }
    return all;
  }

  final _unread = <int, int>{};

  /// Whatever may change that number, in any account.
  List<Stream<Object?>> get changes => [
    _main.postEvents,
    _main.readUpdates,
    for (final o in _others) ...[o.client.postEvents, o.client.readUpdates],
  ];

  Future<void> _followPause() async {
    Future<void> set(bool paused) async {
      for (final o in _others) {
        try {
          await o.client.setPaused(paused);
        } on Object catch (e) {
          debugPrint('accounts: pause of account ${o.id}: $e');
        }
      }
    }

    if (_others.isEmpty) return;
    await set(await _main.isPaused());
    _pause = _main.pausedChanges.listen((p) => unawaited(set(p)));
  }

  Future<void> dispose() async {
    await _pause?.cancel();
    for (final o in _others) {
      await o.client.close();
      await o.db.close();
    }
    _others.clear();
  }
}
