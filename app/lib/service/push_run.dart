import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:app_db/app_db.dart';
import 'package:core/core.dart';
import 'package:core/native_isolate.dart';
import 'package:flutter/widgets.dart';
import 'package:push_runner/push_runner.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../l10n/l10n.dart';
import 'account_watch.dart';
import 'core_bootstrap.dart';
import 'core_lock.dart';
import 'launcher_badge.dart';
import 'notification_plan.dart';
import 'push_registration.dart';
import 'rule_alerts.dart';

/// A run (ARCHITECTURE 6.5): Android started the app's `pushMain` in an engine of its
/// own, for a push, a button pressed on a notification while nothing ran, or a new FCM
/// token. Says `done` when it is over, and the job ends.
Future<void> runPush() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  final run = PushRun();
  PushRunner.listen(onQueued: run.drain, onStop: run.stop);
  try {
    await run.run();
  } on Object catch (e, st) {
    debugPrint('push: run failed: $e\n$st');
  }
  await PushRunner.done();
}

/// When the app's core is up in this process, a run hands it what came and waits while
/// the app's alerts do the rest. Otherwise it hosts the core, the alerts and the number on
/// the app's icon itself, as the app would, until nothing is left to do: TDLib connected
/// and caught up, no new post for [quiet], the alerts idle. Then it hands TDLib back. The
/// app takes such a core over when it opens, and the run ends.
final class PushRun {
  PushRun({
    this.quiet = const Duration(seconds: 10),
    this.connectWait = const Duration(seconds: 30),
    this.limit = const Duration(minutes: 8),
  });

  /// How long nothing has to happen before the run ends.
  final Duration quiet;

  /// How long a run waits for TDLib's connection before it may end without it.
  final Duration connectWait;

  /// The longest run; WorkManager stops a job at ten minutes.
  final Duration limit;

  static void _log(String s) => debugPrint('push: $s');

  final _started = DateTime.now();
  final _stopped = Completer<void>();
  DateTime _lastActivity = DateTime.now();
  bool _connected = false;
  CoreClient? _client;
  Future<void> Function()? _register;
  Future<void> _draining = Future.value();
  final _subs = <StreamSubscription<Object?>>[];

  /// Android ends the run early: it winds down at once.
  void stop() {
    if (!_stopped.isCompleted) _stopped.complete();
  }

  /// Hands on what waits in the queue, one batch after the other. Before there is a core
  /// to hand it to, it stays queued.
  void drain() {
    if (_client == null) return;
    _draining = _draining.then((_) => _drainOnce());
  }

  Future<void> run() async {
    final existing = IsolateNameServer.lookupPortByName(corePortName);
    if (existing != null && await _forwardTo(existing)) return;
    await _host();
  }

  /// The app's core is up: it gets the pushes, and its alerts notify.
  Future<bool> _forwardTo(SendPort port) async {
    final CoreClient client;
    try {
      client = await CoreClient.connect(port)
          .timeout(const Duration(seconds: 5));
    } on Object catch (e) {
      // An engine that went without handing its core back left its name behind.
      _log('the core registered in this process does not answer: $e');
      IsolateNameServer.removePortNameMapping(corePortName);
      return false;
    }
    _log('the app is up: its core gets the push');
    _client = client;
    _follow(client);
    _register = () async {
      final paths = await appPaths();
      final db = AppDatabase(appDatabaseFile(File(paths.db)));
      final watch = await AccountWatch.open(client, support: paths.support);
      try {
        await PushRegistration.ensure(
          main: client,
          mainDb: db,
          others: watch.clients,
        );
      } finally {
        await watch.dispose();
        await db.close();
      }
    };
    drain();
    await _settle(busy: _appAlertsBusy);
    await _close();
    await client.close();
    return true;
  }

  /// Nothing runs the core in this process: the run does, until nothing is left to do.
  /// Another engine may be starting one (the app, the service): the push goes to that
  /// one once it is registered; a holder of the lock that registers none in time is
  /// taken as gone ([CoreLock]).
  Future<void> _host() async {
    if (CoreLock.held) {
      final end = DateTime.now().add(const Duration(seconds: 20));
      while (DateTime.now().isBefore(end)) {
        final port = IsolateNameServer.lookupPortByName(corePortName);
        if (port != null && await _forwardTo(port)) return;
        if (!CoreLock.held) break;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    final lock = await CoreLock.take(force: true, standDownHolder: false);
    try {
      await _hostCore();
    } finally {
      CoreLock.release(lock);
    }
  }

  Future<void> _hostCore() async {
    final paths = await appPaths();
    final db = AppDatabase(appDatabaseFile(File(paths.db)));
    final strings = AppLanguage.strings(await db.setting(SettingKeys.language));
    final reply = ReceivePort();
    final core = await Isolate.spawn(
      coreIsolateMain,
      coreBootstrap(
        paths,
        others: await otherAccountsToServe(paths.support),
        replyTo: reply.sendPort,
      ),
      debugName: 'core',
    );
    final port = await reply.first as SendPort;
    reply.close();
    IsolateNameServer.removePortNameMapping(corePortName);
    IsolateNameServer.registerPortWithName(port, corePortName);
    final client = await CoreClient.connect(port);
    _client = client;
    _follow(client);
    final watch = await AccountWatch.open(client, support: paths.support);
    for (final changes in watch.changes) {
      _subs.add(changes.listen((_) => _lastActivity = DateTime.now()));
    }
    final alerts = RuleAlerts.of(
      client,
      db: db,
      account: watch.activeId,
      accountName: watch.activeName,
      others: watch.alerts,
      // Nobody shows a banner; the notifications show what is read.
      onReading: (_) {},
      log: (s) => _log('alerts: $s'),
    );
    await alerts.start(strings);
    final badge = LauncherBadge(
      db: db,
      channels: watch.channels,
      changes: watch.changes,
    );
    await badge.start();
    _register = () => PushRegistration.ensure(
      main: client,
      mainDb: db,
      others: watch.clients,
    );
    unawaited(_register!());
    _log('core up');
    drain();
    bool takenOver() =>
        IsolateNameServer.lookupPortByName(corePortName) != port;
    await _settle(busy: () async => alerts.busy, takenOver: takenOver);
    await _close();
    final handedOver = takenOver();
    await badge.dispose();
    await alerts.dispose();
    await watch.dispose();
    if (!handedOver) {
      // TDLib goes back before the isolate goes, so the app's own core may start one.
      try {
        await client.shutdown().timeout(const Duration(seconds: 10));
      } on Object catch (e) {
        _log('core shutdown: $e');
      }
      IsolateNameServer.removePortNameMapping(corePortName);
    }
    await client.close();
    core.kill(priority: Isolate.immediate);
    await db.close();
    _log(handedOver ? 'the app took the core over' : 'core down');
  }

  /// What the core does counts as activity, and its connection decides when the run may
  /// end.
  void _follow(CoreClient client) {
    _subs
      ..add(client.postEvents.listen((_) => _lastActivity = DateTime.now()))
      ..add(client.matches.listen((_) => _lastActivity = DateTime.now()))
      ..add(
        client.connection.listen((c) {
          if (c == ConnectionStatus.ready) _connected = true;
        }),
      );
  }

  Future<void> _drainOnce() async {
    final items = await PushRunner.take();
    for (final item in items) {
      _lastActivity = DateTime.now();
      switch (item) {
        case PushMessage(:final payload):
          _log('push');
          try {
            await _client?.processPush(payload);
          } on Object catch (e) {
            _log('push not handled: $e');
          }
        case PushAction(:final response):
          // The alerts read aloud what the notification lists.
          IsolateNameServer.lookupPortByName(notifierPortName)?.send(response);
        case PushRegister():
          try {
            await _register?.call();
          } on Object catch (e) {
            _log('registration: $e');
          }
      }
    }
    _lastActivity = DateTime.now();
  }

  /// Waits until nothing is left to do, the run was stopped or taken over, or is over
  /// [limit].
  Future<void> _settle({
    required Future<bool> Function() busy,
    bool Function()? takenOver,
  }) async {
    final end = _started.add(limit);
    while (!_stopped.isCompleted && DateTime.now().isBefore(end)) {
      if (takenOver?.call() ?? false) return;
      final now = DateTime.now();
      final connectedOrGaveUp =
          _connected || now.difference(_started) >= connectWait;
      if (connectedOrGaveUp &&
          now.difference(_lastActivity) >= quiet &&
          !await busy()) {
        await _draining;
        if (DateTime.now().difference(_lastActivity) >= quiet) return;
      }
      await Future.any([
        Future<void>.delayed(const Duration(seconds: 1)),
        _stopped.future,
      ]);
    }
  }

  Future<void> _close() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
  }

  /// Whether the app's alerts are still at work ([RuleAlerts.busy], asked on their port).
  static Future<bool> _appAlertsBusy() async {
    final port = IsolateNameServer.lookupPortByName(notifierPortName);
    if (port == null) return false;
    final reply = ReceivePort();
    port.send({'type': alertsBusy, 'reply': reply.sendPort});
    try {
      return await reply.first.timeout(const Duration(seconds: 2)) == true;
    } on TimeoutException {
      return false;
    } finally {
      reply.close();
    }
  }
}
