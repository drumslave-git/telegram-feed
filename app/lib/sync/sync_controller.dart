import 'dart:async';

import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

import 'drive_auth.dart';
import 'drive_sync_store.dart';

/// Device-local sync bookkeeping (never synced itself, see `isSyncedSetting`).
abstract final class SyncKeys {
  static const enabled = 'sync.enabled'; // 'true' while the user has sync on
  static const lastSyncedAt = 'sync.lastSyncedAt'; // Unix ms
  static const account =
      'sync.account'; // the Google account's email, on this device
}

/// What the sync settings screen shows.
@immutable
final class SyncStatus {
  const SyncStatus({
    this.available = true,
    this.account,
    this.syncing = false,
    this.lastSyncedAt,
    this.error,
  });

  /// False when the build has no Google client id.
  final bool available;

  /// Email of the Google account while sync is on; null while off.
  final String? account;
  final bool syncing;
  final DateTime? lastSyncedAt;
  final String? error;

  bool get isOn => account != null;

  SyncStatus copyWith({
    String? Function()? account,
    bool? syncing,
    DateTime? lastSyncedAt,
    String? Function()? error,
  }) => SyncStatus(
    available: available,
    account: account == null ? this.account : account(),
    syncing: syncing ?? this.syncing,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    error: error == null ? this.error : error(),
  );
}

/// Runs Drive sync for the UI isolate (ARCHITECTURE.md section 5.5): on start, a short
/// while after local edits, every quarter of an hour while the app is open, and on demand.
/// Pulled changes land in the database, which the core already watches for rule changes.
final class SyncController {
  SyncController({
    required this.db,
    required this.auth,
    SyncStore? store,
    DateTime Function()? clock,
    this.debounce = const Duration(seconds: 15),
    this.interval = const Duration(minutes: 15),
  }) : _clock = clock ?? DateTime.now {
    _store = store ?? DriveSyncStore(auth.accessToken);
    _engine = SyncEngine(db: db, store: _store, clock: _clock);
    status = ValueNotifier(SyncStatus(available: auth.isConfigured));
  }

  final AppDatabase db;
  final DriveAuth auth;
  final Duration debounce;
  final Duration interval;
  final DateTime Function() _clock;
  late final SyncStore _store;
  late final SyncEngine _engine;
  late final ValueNotifier<SyncStatus> status;

  StreamSubscription<void>? _changes;
  Timer? _debounceTimer;
  Timer? _periodic;
  Future<void>? _running;
  bool _again = false;

  /// What this device held right after its last sync run, encoded. The watcher fires on any
  /// write to the watched tables, also the run's own bookkeeping and device-local settings;
  /// only a difference to this is worth a request to Drive.
  String? _synced;

  /// Restores a previous sign-in and, if sync was on, syncs and starts watching.
  Future<void> start() async {
    if (!auth.isConfigured) return;
    final last = int.tryParse(await db.setting(SyncKeys.lastSyncedAt) ?? '');
    if (last != null) {
      status.value = status.value.copyWith(
        lastSyncedAt: DateTime.fromMillisecondsSinceEpoch(last),
      );
    }
    if (await db.setting(SyncKeys.enabled) != 'true') return;
    final account = await auth.restore(
      knownEmail: await db.setting(SyncKeys.account),
    );
    if (account == null) {
      status.value = status.value.copyWith(
        error: () => 'Signed out of Google. Sign in again to keep syncing.',
      );
      return;
    }
    await db.setSetting(SyncKeys.account, account);
    status.value = status.value.copyWith(account: () => account);
    _watch();
    unawaited(syncNow());
  }

  /// Interactive: sign in, remember that sync is on, run the first sync.
  Future<void> turnOn() async {
    status.value = status.value.copyWith(error: () => null);
    try {
      final account = await auth.signIn();
      await db.setSetting(SyncKeys.enabled, 'true');
      await db.setSetting(SyncKeys.account, account);
      status.value = status.value.copyWith(account: () => account);
      _watch();
      await syncNow();
    } on SyncException catch (e) {
      status.value = status.value.copyWith(error: () => e.message);
    }
  }

  /// Stops syncing on this device. The file in Drive and other devices are untouched.
  Future<void> turnOff() async {
    _unwatch();
    await db.setSetting(SyncKeys.enabled, 'false');
    await auth.signOut();
    status.value = status.value.copyWith(
      account: () => null,
      error: () => null,
    );
  }

  /// One sync run; calls made while one is running collapse into a single follow-up.
  Future<void> syncNow() {
    if (!status.value.isOn) return Future.value();
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    return _running = _run().whenComplete(() {
      _running = null;
      if (_again) {
        _again = false;
        unawaited(syncNow());
      }
    });
  }

  Future<void> _run() async {
    status.value = status.value.copyWith(syncing: true);
    try {
      final result = await _engine.sync();
      final now = _clock();
      await db.setSetting(
        SyncKeys.lastSyncedAt,
        '${now.millisecondsSinceEpoch}',
      );
      _synced = (await _engine.exportLocal()).encode();
      debugPrint('sync: pulled ${result.pulled}, pushed ${result.pushed}');
      status.value = status.value.copyWith(
        syncing: false,
        lastSyncedAt: now,
        error: () => null,
      );
    } on SyncException catch (e) {
      status.value = status.value.copyWith(
        syncing: false,
        error: () => e.message,
      );
    }
  }

  void _watch() {
    _unwatch();
    _changes = db.watchSyncedData().skip(1).listen((_) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(debounce, () => unawaited(_syncIfChanged()));
    });
    _periodic = Timer.periodic(interval, (_) => unawaited(syncNow()));
  }

  Future<void> _syncIfChanged() async {
    if (_synced != null && (await _engine.exportLocal()).encode() == _synced) {
      return;
    }
    await syncNow();
  }

  void _unwatch() {
    unawaited(_changes?.cancel());
    _changes = null;
    _debounceTimer?.cancel();
    _periodic?.cancel();
  }

  Future<void> dispose() async {
    _unwatch();
    await _running;
    status.dispose();
  }
}
