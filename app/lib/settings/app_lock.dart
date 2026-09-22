import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:app_db/app_db.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../app_name.dart';
import '../widgets/destructive_button.dart';

/// Where the hash of the PIN is kept. The app uses the keystore, tests a map of their own.
abstract interface class PinStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

/// The keystore, beside the AI key.
class KeystorePinStore implements PinStore {
  const KeystorePinStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  static const _key = 'lock.pin';

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);

  @override
  Future<void> delete() => _storage.delete(key: _key);
}

/// The lock of the app itself: a PIN the reader sets, and the device's own fingerprint or
/// face where they allow it. Private channels are readable by anyone holding the unlocked
/// phone, which is what this is for (H-34). The PIN is never stored: only a salted hash of
/// it, in the keystore beside the AI key.
class AppLock {
  const AppLock({required this.db, PinStore? store})
    : _store = store ?? const KeystorePinStore();
  final AppDatabase db;
  final PinStore _store;

  /// How long the app may rest before it asks again.
  static const timeouts = <int>[0, 60, 300, 3600];

  /// The rest before the lock asks again until the reader picks another: an hour, as the
  /// official app's passcode starts.
  static const defaultTimeout = 3600;

  Future<bool> get enabled async =>
      (await db.setting(SettingKeys.lockEnabled)) == 'true' && await hasPin();

  Future<bool> hasPin() async => (await _store.read())?.isNotEmpty ?? false;

  Future<bool> get biometrics async =>
      (await db.setting(SettingKeys.lockBiometrics)) == 'true';

  Future<Duration> get timeout async => Duration(
    seconds:
        int.tryParse(await db.setting(SettingKeys.lockTimeout) ?? '') ??
        defaultTimeout,
  );

  /// Sets (or replaces) the PIN and turns the lock on.
  Future<void> setPin(String pin) async {
    final salt = _salt();
    await _store.write('$salt:${_hash(pin, salt)}');
    await db.setSetting(SettingKeys.lockEnabled, 'true');
  }

  Future<void> remove() async {
    await _store.delete();
    await db.setSetting(SettingKeys.lockEnabled, 'false');
  }

  Future<bool> check(String pin) async {
    final stored = await _store.read() ?? '';
    final parts = stored.split(':');
    if (parts.length != 2) return false;
    return _hash(pin, parts.first) == parts.last;
  }

  static String _salt() {
    final random = Random.secure();
    return base64Url.encode(List<int>.generate(12, (_) => random.nextInt(256)));
  }

  static String _hash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt$pin')).toString();
}

/// Keeps the app behind [LockScreen] while it is locked, and locks it again when it has
/// rested longer than the reader's timeout. It sits above the navigator, so no screen and no
/// notification tap can go round it.
class LockGate extends StatefulWidget {
  const LockGate({
    super.key,
    required this.db,
    required this.child,
    this.lock,
    this.auth,
  });
  final AppDatabase db;
  final Widget child;

  /// Tests hand in their own.
  final AppLock? lock;
  final LocalAuthentication? auth;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  AppLock get _lock => widget.lock ?? AppLock(db: widget.db);
  bool _locked = false;
  DateTime? _restingSince;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_lockIfEnabled());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _lockIfEnabled() async {
    if (await _lock.enabled && mounted) setState(() => _locked = true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _restingSince = DateTime.now();
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    final since = _restingSince;
    _restingSince = null;
    unawaited(_maybeLock(since));
  }

  Future<void> _maybeLock(DateTime? since) async {
    if (_locked || !await _lock.enabled) return;
    final timeout = await _lock.timeout;
    final rested = since == null
        ? Duration.zero
        : DateTime.now().difference(since);
    if (rested >= timeout && mounted) setState(() => _locked = true);
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      widget.child,
      if (_locked)
        LockScreen(
          lock: _lock,
          auth: widget.auth,
          onUnlocked: () => setState(() => _locked = false),
        ),
    ],
  );
}

/// Asks for the PIN, and offers the device's own check where the reader allowed it.
class LockScreen extends StatefulWidget {
  const LockScreen({
    super.key,
    required this.lock,
    required this.onUnlocked,
    this.auth,
    this.title = '$appName is locked',
  });
  final AppLock lock;
  final VoidCallback onUnlocked;
  final LocalAuthentication? auth;

  /// What the screen asks for: unlocking the app, or opening the lock's own settings.
  final String title;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _pin = TextEditingController();
  String? _error;
  bool _checking = false;

  /// The reader allowed the device's own check; only then is its button shown.
  bool _biometricsAllowed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_biometrics());
  }

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _biometrics() async {
    if (!await widget.lock.biometrics) return;
    if (mounted) setState(() => _biometricsAllowed = true);
    final auth = widget.auth ?? LocalAuthentication();
    try {
      final ok = await auth.authenticate(
        localizedReason: 'Unlock $appName',
        persistAcrossBackgrounding: true,
      );
      if (ok && mounted) widget.onUnlocked();
    } on Object {
      // The PIN is always there as the way in.
      if (mounted) {
        setState(
          () => _error = 'The phone\'s check is not available; use the PIN.',
        );
      }
    }
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    final ok = await widget.lock.check(_pin.text);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _error = ok ? null : 'Wrong PIN';
      if (ok) _pin.clear();
    });
    if (ok) widget.onUnlocked();
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 48),
            const SizedBox(height: 16),
            Text(widget.title, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            TextField(
              controller: _pin,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                labelText: 'PIN',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => unawaited(_check()),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _checking ? null : () => unawaited(_check()),
              child: const Text('Unlock'),
            ),
            if (_biometricsAllowed)
              TextButton(
                onPressed: () => unawaited(_biometrics()),
                child: const Text('Use fingerprint or face'),
              ),
          ],
        ),
      ),
    ),
  );
}

/// The lock's own settings: set or change the PIN, the timeout, and the device check.
class AppLockScreen extends StatefulWidget {
  const AppLockScreen({super.key, required this.db, this.lock, this.auth});
  final AppDatabase db;
  final AppLock? lock;
  final LocalAuthentication? auth;

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  AppLock get _lock => widget.lock ?? AppLock(db: widget.db);
  final _pin = TextEditingController();
  final _again = TextEditingController();
  bool _hasPin = false;
  String? _error;

  /// Null until the store answered; then whether the PIN must be entered first. Whoever
  /// holds the unlocked phone must not be able to change or remove the lock.
  bool? _needsPin;

  @override
  void initState() {
    super.initState();
    unawaited(_read(first: true));
  }

  @override
  void dispose() {
    _pin.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _read({bool first = false}) async {
    final has = await _lock.hasPin();
    if (!mounted) return;
    setState(() {
      _hasPin = has;
      if (first) _needsPin = has;
    });
  }

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove the lock?'),
        content: const Text(
          'Anyone holding the unlocked phone can then read your channels.',
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
    if (ok != true) return;
    await _lock.remove();
    await _read();
  }

  Future<void> _save() async {
    if (_pin.text.length < 4) {
      setState(() => _error = 'At least four digits');
      return;
    }
    if (_pin.text != _again.text) {
      setState(() => _error = 'The two do not match');
      return;
    }
    final replaced = _hasPin;
    await _lock.setPin(_pin.text);
    _pin.clear();
    _again.clear();
    if (!mounted) return;
    setState(() => _error = null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(replaced ? 'PIN replaced' : 'PIN set, the lock is on'),
      ),
    );
    await _read();
  }

  static String _timeoutLabel(int seconds) => switch (seconds) {
    0 => 'At once',
    60 => 'After a minute',
    300 => 'After five minutes',
    _ => 'After an hour',
  };

  @override
  Widget build(BuildContext context) {
    final needsPin = _needsPin;
    if (needsPin == null) {
      return Scaffold(appBar: AppBar(title: const Text('App lock')));
    }
    if (needsPin) {
      return Scaffold(
        appBar: AppBar(title: const Text('App lock')),
        body: LockScreen(
          lock: _lock,
          auth: widget.auth,
          title: 'Enter your PIN to change the lock',
          onUnlocked: () => setState(() => _needsPin = false),
        ),
      );
    }
    return _settings(context);
  }

  Widget _settings(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('App lock')),
    body: ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _hasPin
                ? 'The app asks for this PIN when it has rested. Setting a new one replaces it.'
                : 'A PIN keeps the channels you read out of the hands of whoever holds the '
                      'unlocked phone.',
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _pin,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: _hasPin ? 'New PIN' : 'PIN',
              errorText: _error,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _again,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'PIN again'),
            onSubmitted: (_) => unawaited(_save()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              FilledButton(
                onPressed: () => unawaited(_save()),
                child: Text(_hasPin ? 'Replace the PIN' : 'Set the PIN'),
              ),
              const SizedBox(width: 12),
              if (_hasPin)
                TextButton(
                  onPressed: () => unawaited(_remove()),
                  child: const Text('Remove the lock'),
                ),
            ],
          ),
        ),
        const Divider(),
        StreamBuilder<String?>(
          stream: widget.db.watchSetting(SettingKeys.lockTimeout),
          builder: (context, snap) {
            final seconds =
                int.tryParse(snap.data ?? '') ?? AppLock.defaultTimeout;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text('Ask again'),
                ),
                RadioGroup<int>(
                  groupValue: seconds,
                  // Nothing to time out before there is a PIN.
                  onChanged: (v) {
                    if (!_hasPin) return;
                    unawaited(
                      widget.db.setSetting(
                        SettingKeys.lockTimeout,
                        '${v ?? AppLock.defaultTimeout}',
                      ),
                    );
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final t in AppLock.timeouts)
                        RadioListTile<int>(
                          value: t,
                          enabled: _hasPin,
                          title: Text(_timeoutLabel(t)),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        const Divider(),
        StreamBuilder<String?>(
          stream: widget.db.watchSetting(SettingKeys.lockBiometrics),
          builder: (context, snap) => SwitchListTile(
            value: snap.data == 'true',
            title: const Text('Fingerprint or face'),
            subtitle: const Text(
              'Offered first when the app is locked; the PIN always works too',
            ),
            onChanged: _hasPin
                ? (v) => widget.db.setSetting(SettingKeys.lockBiometrics, '$v')
                : null,
          ),
        ),
      ],
    ),
  );
}
