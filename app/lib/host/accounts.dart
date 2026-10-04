import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:telegram_gateway/telegram_gateway.dart' show UserInfo;

/// One Telegram account on this device. The id decides where its data lives: account 1 uses
/// the paths the app has always used, so an install that predates several accounts keeps
/// everything where it left it.
class AccountInfo {
  const AccountInfo({
    required this.id,
    this.label = '',
    this.name = '',
    this.phone = '',
    this.photo = '',
    this.unread = 0,
    this.loggedIn,
  });
  final int id;

  /// What an older build named the account: its name and phone in one line.
  final String label;

  /// The name of its profile, once it has logged in.
  final String name;

  /// The phone number of its profile as people write it, where Telegram gave one.
  final String phone;

  /// The path of the copy of its profile photo that the list of accounts shows; empty
  /// while it has none.
  final String photo;

  /// How many of its channels have unread posts: counted while it is in use, and for a
  /// logged-in account that is not, whenever the number on the app's icon is counted
  /// (`AccountWatch.channels`).
  final int unread;

  /// False for an account that was added and has not logged in; null for an account an
  /// older build kept, of which this is not known.
  final bool? loggedIn;

  /// The name the account goes by: its profile's, or what an older build called it;
  /// empty while neither is known.
  String get title => name.isNotEmpty ? name : label;

  AccountInfo copyWith({
    String? label,
    String? name,
    String? phone,
    String? photo,
    int? unread,
    bool? loggedIn,
  }) => AccountInfo(
    id: id,
    label: label ?? this.label,
    name: name ?? this.name,
    phone: phone ?? this.phone,
    photo: photo ?? this.photo,
    unread: unread ?? this.unread,
    loggedIn: loggedIn ?? this.loggedIn,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'name': name,
    'phone': phone,
    'photo': photo,
    'unread': unread,
    if (loggedIn != null) 'loggedIn': loggedIn,
  };

  static AccountInfo fromJson(Map<Object?, Object?> m) => AccountInfo(
    id: (m['id'] as num).toInt(),
    label: (m['label'] as String?) ?? '',
    name: (m['name'] as String?) ?? '',
    phone: (m['phone'] as String?) ?? '',
    photo: (m['photo'] as String?) ?? '',
    unread: (m['unread'] as num?)?.toInt() ?? 0,
    loggedIn: m['loggedIn'] as bool?,
  );

  @override
  bool operator ==(Object other) =>
      other is AccountInfo &&
      other.id == id &&
      other.label == label &&
      other.name == name &&
      other.phone == phone &&
      other.photo == photo &&
      other.unread == unread &&
      other.loggedIn == loggedIn;
  @override
  int get hashCode =>
      Object.hash(id, label, name, phone, photo, unread, loggedIn);
}

/// The accounts of this device and which one is in use, in a small file beside the
/// per-account databases. It has to live outside them: it says which of them to open.
class AccountStore {
  const AccountStore(this.supportDirectory);
  final String supportDirectory;

  /// As many as the official app holds with Premium; without it that app stops at three.
  static const maxAccounts = 4;

  String get _path => '$supportDirectory/accounts.json';

  static String _suffix(int id) => id <= 1 ? '' : '-$id';

  /// Where the account's TDLib directory, its app database and the copy of its profile
  /// photo are. Account 1 keeps the paths the app has always used.
  String tdlibOf(int id) => '$supportDirectory/tdlib${_suffix(id)}';
  String dbOf(int id) => '$supportDirectory/app${_suffix(id)}.sqlite';
  String photoOf(int id) => '$supportDirectory/account${_suffix(id)}.jpg';

  /// Where the account's videos were left in the viewer (`VideoPositions`).
  String videoPositionsOf(int id) =>
      '$supportDirectory/video-positions${_suffix(id)}.json';

  /// Changes to the file wait for each other: the profile and the unread count of the
  /// account in use are written from different places, and each change reads the file
  /// first.
  static Future<void> _queue = Future<void>.value();

  Future<T> _oneAtATime<T>(Future<T> Function() change) {
    final done = _queue.then((_) => change());
    _queue = done.then<void>((_) {}, onError: (Object _) {});
    return done;
  }

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

  Future<void> setActive(int id) => _oneAtATime(() async {
    final now = await load();
    if (!now.accounts.any((a) => a.id == id)) return;
    await _save(now.accounts, id);
  });

  /// Writes what is given of the account [id] and leaves the rest; nothing is written
  /// when nothing changes.
  Future<void> update(
    int id, {
    String? label,
    String? name,
    String? phone,
    String? photo,
    int? unread,
    bool? loggedIn,
  }) => _oneAtATime(() async {
    final now = await load();
    final accounts = [...now.accounts];
    final i = accounts.indexWhere((a) => a.id == id);
    if (i < 0) return;
    final next = accounts[i].copyWith(
      label: label,
      name: name,
      phone: phone,
      photo: photo,
      unread: unread,
      loggedIn: loggedIn,
    );
    if (next == accounts[i]) return;
    accounts[i] = next;
    await _save(accounts, now.active);
  });

  /// Adds an account and makes it the one in use; null when there is no room left. It has
  /// not logged in yet, and is dropped again if it never does ([dropNeverLoggedIn]).
  Future<AccountInfo?> add() => _oneAtATime(() async {
    final now = await load();
    if (now.accounts.length >= maxAccounts) return null;
    final ids = {for (final a in now.accounts) a.id};
    var id = 1;
    while (ids.contains(id)) {
      id++;
    }
    final added = AccountInfo(id: id, loggedIn: false);
    await _save([...now.accounts, added], id);
    return added;
  });

  /// Takes the account off this device, with its TDLib data, its feeds and the copy of
  /// its photo. The last one cannot go: the app would have nothing to open.
  Future<bool> remove(int id, {String? tdlib, String? db}) =>
      _oneAtATime(() async {
        final now = await load();
        if (now.accounts.length <= 1) return false;
        final left = [
          for (final a in now.accounts)
            if (a.id != id) a,
        ];
        final active = now.active == id ? left.first.id : now.active;
        await _save(left, active);
        await _deleteData(id, tdlib: tdlib, db: db);
        return true;
      });

  Future<void> _deleteData(int id, {String? tdlib, String? db}) async {
    final base = db ?? dbOf(id);
    for (final path in [
      base,
      '$base-wal',
      '$base-shm',
      photoOf(id),
      videoPositionsOf(id),
    ]) {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    }
    final dir = Directory(tdlib ?? tdlibOf(id));
    if (dir.existsSync()) await dir.delete(recursive: true);
  }

  /// Drops every account that was added and never logged in, except the one in use,
  /// which may be logging in right now. An account of an older build, of which it is not
  /// known whether it logged in, stays.
  Future<void> dropNeverLoggedIn() => _oneAtATime(() async {
    final now = await load();
    final gone = [
      for (final a in now.accounts)
        if (a.loggedIn == false && a.id != now.active) a.id,
    ];
    if (gone.isEmpty) return;
    await _save([
      for (final a in now.accounts)
        if (!gone.contains(a.id)) a,
    ], now.active);
    for (final id in gone) {
      await _deleteData(id);
    }
  });
}

/// Writes what the list of accounts shows of the account in use: its profile once it is
/// logged in, and how many of its channels have unread posts, as that changes.
class AccountRecorder {
  const AccountRecorder(this.store, this.id);
  final AccountStore store;
  final int id;

  /// The account is logged in. Written before anything is asked of Telegram, so an
  /// account that logged in is never taken for one that did not.
  Future<void> loggedIn() => store.update(id, loggedIn: true);

  /// The profile, and a copy of its photo from [photoPath] (a file of the account's own
  /// TDLib directory, which the list cannot rely on while another account is in use).
  Future<void> profile(UserInfo me, {String? photoPath}) async {
    var photo = '';
    if (photoPath != null && photoPath.isNotEmpty) {
      try {
        final copy = await File(photoPath).copy(store.photoOf(id));
        photo = copy.path;
        // The path is the same as for the photo before it.
        await FileImage(copy).evict();
      } on FileSystemException {
        // Without the copy the row shows initials.
      }
    }
    await store.update(
      id,
      name: me.displayName,
      phone: me.phoneNumber.isEmpty ? '' : me.phoneDisplay,
      photo: photo,
      loggedIn: true,
    );
  }

  Future<void> unread(int channels) => store.update(id, unread: channels);

  /// The reader logged out: nothing of the profile stays, and the account counts as one
  /// that never logged in.
  Future<void> loggedOut() async {
    await store.update(
      id,
      label: '',
      name: '',
      phone: '',
      photo: '',
      unread: 0,
      loggedIn: false,
    );
    final photo = File(store.photoOf(id));
    if (photo.existsSync()) await photo.delete();
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

  /// The same, for what has no widget to ask: a tap on a notification of another
  /// account. Set by the app's root while it is there.
  static Future<void> Function()? root;

  static AccountSwitch? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AccountSwitch>();

  @override
  bool updateShouldNotify(AccountSwitch old) => false;
}
