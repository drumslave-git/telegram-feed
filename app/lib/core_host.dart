import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:core/native_isolate.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

/// Telegram API credentials come from `--dart-define`; never committed (SPEC section 7).
const int tgApiId = int.fromEnvironment('TG_API_ID');
const String tgApiHash = String.fromEnvironment('TG_API_HASH');
const bool tgTestDc = bool.fromEnvironment('TG_TEST_DC');

/// Owns the app's connection to the core and the app database.
///
/// Phase 1: spawns the core isolate itself. Phase 2: finds the one the foreground service
/// started. After a logout TDLib closes its client (`AuthClosed`), so the host respawns the
/// core and re-exposes a fresh gateway through [gateway].
final class CoreHost extends ChangeNotifier {
  CoreHost._(this.db, this._supportDir);

  static Future<CoreHost> start() async {
    final support = await getApplicationSupportDirectory();
    final db = AppDatabase(
      NativeDatabase.createInBackground(File('${support.path}/app.sqlite')),
    );
    final host = CoreHost._(db, support.path);
    await host._connect();
    return host;
  }

  final AppDatabase db;
  final String _supportDir;
  CoreClient? _client;
  StreamSubscription<AuthState>? _authSub;
  int _generation = 0;

  /// The gateway to use; identity changes after a restart (listeners are notified).
  TelegramGateway get gateway => _client!;
  int get generation => _generation;

  Future<void> _connect() async {
    var port = IsolateNameServer.lookupPortByName(corePortName);
    if (port == null) {
      port = await spawnCoreIsolate(
        CoreBootstrap(
          apiId: tgApiId,
          apiHash: tgApiHash,
          databaseDirectory: '$_supportDir/tdlib',
          filesDirectory: '$_supportDir/tdlib/files',
          useTestDc: tgTestDc,
          deviceModel: Platform.isAndroid
              ? 'Android'
              : Platform.operatingSystem,
          systemVersion: Platform.operatingSystemVersion,
        ),
      );
      IsolateNameServer.removePortNameMapping(corePortName);
      IsolateNameServer.registerPortWithName(port, corePortName);
    }
    _client = await CoreClient.connect(port);
    _authSub = _client!.authState.listen((s) {
      if (s is AuthClosed) unawaited(_restart());
    });
    _generation++;
    notifyListeners();
  }

  /// TDLib destroyed its database; start a fresh core so the user can log in again.
  Future<void> _restart() async {
    await _authSub?.cancel();
    await _client?.close();
    _client = null;
    IsolateNameServer.removePortNameMapping(corePortName);
    await _connect();
  }

  /// Logs out and wipes everything the app stored (ARCHITECTURE section 10). TDLib deletes
  /// its own database and files directory as part of `logOut`.
  Future<void> logOutAndWipe() async {
    await db.wipe();
    await gateway.logOut();
  }

  @override
  Future<void> dispose() async {
    await _authSub?.cancel();
    await _client?.close();
    await db.close();
    super.dispose();
  }
}
