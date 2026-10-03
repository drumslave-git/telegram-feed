import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:app_db/app_db.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../app_name.dart';
import '../host/secure_window.dart';
import '../l10n/l10n.dart';
import '../widgets/destructive_button.dart';

/// Where the lock keeps what it knows: the hash of the PIN and its own settings. The app
/// uses the keystore, tests a map of their own.
abstract interface class LockStore {
  Future<String?> read(String key);

  /// Null removes the value.
  Future<void> write(String key, String? value);
}

/// The keystore, beside the AI key. It belongs to the device, not to an account: the lock
/// holds for every account and outlives a logout.
class KeystoreLockStore implements LockStore {
  const KeystoreLockStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } on MissingPluginException {
      // No keystore: a widget test. There is no lock then.
      return null;
    }
  }

  @override
  Future<void> write(String key, String? value) => value == null
      ? _storage.delete(key: key)
      : _storage.write(key: key, value: value);
}

/// The lock of the app itself: a PIN the reader sets, and the device's own fingerprint or
/// face where they allow it. Private channels are readable by anyone holding the unlocked
/// phone, which is what this is for (H-34). The PIN is never stored: only a salted hash of
/// it. The lock is on while a PIN exists, for every account on the device.
class AppLock {
  const AppLock({LockStore? store, DateTime Function()? clock})
    : _store = store ?? const KeystoreLockStore(),
      _clock = clock ?? DateTime.now;
  final LockStore _store;
  final DateTime Function() _clock;

  static const _pinKey = 'lock.pin';
  static const _timeoutKey = 'lock.timeout';
  static const _biometricsKey = 'lock.biometrics';
  static const _showContentKey = 'lock.showContent';
  static const _triesKey = 'lock.tries';
  static const _retryAtKey = 'lock.retryAt';

  /// Counts up whenever the lock is set, removed or told what the task switcher may show,
  /// so the screens that say so follow.
  static final changes = ValueNotifier<int>(0);

  /// How long the app may rest before it asks again.
  static const timeouts = <int>[0, 60, 300, 3600];

  /// The rest before the lock asks again until the reader picks another: an hour, as the
  /// official app's passcode starts.
  static const defaultTimeout = 3600;

  Future<bool> get enabled => hasPin();

  Future<bool> hasPin() async =>
      (await _store.read(_pinKey))?.isNotEmpty ?? false;

  Future<bool> get biometrics async =>
      (await _store.read(_biometricsKey)) == 'true';

  Future<void> setBiometrics(bool on) => _store.write(_biometricsKey, '$on');

  Future<Duration> get timeout async => Duration(
    seconds:
        int.tryParse(await _store.read(_timeoutKey) ?? '') ?? defaultTimeout,
  );

  Future<void> setTimeout(int seconds) => _store.write(_timeoutKey, '$seconds');

  /// Whether the task switcher may show the app, and screenshots be taken, while the lock
  /// is set. Off until the reader allows it, as in the official app.
  Future<bool> get showContent async =>
      (await _store.read(_showContentKey)) == 'true';

  Future<void> setShowContent(bool on) async {
    await _store.write(_showContentKey, '$on');
    changes.value++;
    await applyToWindow();
  }

  /// Sets (or replaces) the PIN, which turns the lock on.
  Future<void> setPin(String pin) async {
    final salt = _salt();
    await _store.write(_pinKey, '$salt:${_hash(pin, salt)}');
    await _clearTries();
    changes.value++;
    await applyToWindow();
  }

  Future<void> remove() async {
    await _store.write(_pinKey, null);
    await _clearTries();
    changes.value++;
    await applyToWindow();
  }

  /// Whether [pin] is the PIN. A wrong one counts, and from the third in a row the next
  /// try has to wait ([delayAfter]); while it waits every PIN is refused.
  Future<bool> check(String pin) async {
    if (await retryIn() > Duration.zero) return false;
    final stored = await _store.read(_pinKey) ?? '';
    final parts = stored.split(':');
    if (parts.length == 2 && _hash(pin, parts.first) == parts.last) {
      await _clearTries();
      return true;
    }
    final tries = (int.tryParse(await _store.read(_triesKey) ?? '') ?? 0) + 1;
    await _store.write(_triesKey, '$tries');
    final wait = delayAfter(tries);
    await _store.write(
      _retryAtKey,
      wait == Duration.zero
          ? null
          : '${_clock().add(wait).millisecondsSinceEpoch}',
    );
    return false;
  }

  /// How long the next try still has to wait; zero when it may be made now.
  Future<Duration> retryIn() async {
    final at = int.tryParse(await _store.read(_retryAtKey) ?? '');
    if (at == null) return Duration.zero;
    final left = at - _clock().millisecondsSinceEpoch;
    // A clock set back must not lock the reader out for longer than the longest wait.
    if (left <= 0 || left > delayAfter(8).inMilliseconds) return Duration.zero;
    return Duration(milliseconds: left);
  }

  /// The wait after so many wrong PINs in a row, as the official app's passcode makes one
  /// wait: none for the first two, then 5, 10, 15, 20, 25 seconds, and 30 from then on.
  static Duration delayAfter(int tries) =>
      tries < 3 ? Duration.zero : Duration(seconds: min(30, (tries - 2) * 5));

  Future<void> _clearTries() async {
    await _store.write(_triesKey, null);
    await _store.write(_retryAtKey, null);
  }

  /// Builds before the lock belonged to the device kept its timeout and the fingerprint
  /// switch in the account's database; they are taken over once.
  Future<void> adoptLegacy(AppDatabase db) async {
    if (!await hasPin()) return;
    if (await _store.read(_timeoutKey) == null) {
      final old = await db.setting(SettingKeys.lockTimeout);
      if (old != null) await _store.write(_timeoutKey, old);
    }
    if (await _store.read(_biometricsKey) == null) {
      final old = await db.setting(SettingKeys.lockBiometrics);
      if (old != null) await _store.write(_biometricsKey, old);
    }
  }

  /// While the lock is set the window is secure: the task switcher shows a blank card and
  /// no screenshot can be taken, unless the reader allowed that ([showContent]).
  Future<void> applyToWindow() async => SecureWindow.set(
    _windowHolder,
    secure: await enabled && !await showContent,
  );

  static const _windowHolder = 'app lock';

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
  const LockGate({super.key, required this.child, this.lock, this.auth});
  final Widget child;

  /// Tests hand in their own.
  final AppLock? lock;
  final LocalAuthentication? auth;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  AppLock get _lock => widget.lock ?? const AppLock();
  bool _locked = false;
  DateTime? _restingSince;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_lockIfEnabled());
    unawaited(_lock.applyToWindow());
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
      // Hidden from a screen reader and from the keyboard while the lock is up: a
      // painted-over list is still a readable list to TalkBack.
      ExcludeSemantics(
        excluding: _locked,
        child: ExcludeFocus(excluding: _locked, child: widget.child),
      ),
      if (_locked)
        LockScreen(
          lock: _lock,
          auth: widget.auth,
          onUnlocked: () => setState(() => _locked = false),
        ),
    ],
  );
}

/// A PIN is digits only: a field that merely asks for the number keyboard still takes a
/// pasted word, and the stored hash would then be of something no keypad can retype.
final _pinDigits = [FilteringTextInputFormatter.digitsOnly];
const _pinMaxLength = 16;

/// Asks for the PIN, and offers the device's own check where the reader allowed it.
class LockScreen extends StatefulWidget {
  const LockScreen({
    super.key,
    required this.lock,
    required this.onUnlocked,
    this.auth,
    this.title,
  });
  final AppLock lock;
  final VoidCallback onUnlocked;
  final LocalAuthentication? auth;

  /// What the screen asks for: unlocking the app (the default), or opening the lock's
  /// own settings.
  final String? title;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _pin = TextEditingController();
  String? _error;
  bool _checking = false;

  /// The reader allowed the device's own check; only then is its button shown.
  bool _biometricsAllowed = false;

  /// Seconds the next try still has to wait after too many wrong PINs; 0 when it may be
  /// made.
  int _wait = 0;
  Timer? _waiting;

  /// Counts the wrong PINs of this screen; each gets a field of its own.
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_biometrics());
    unawaited(_readWait());
  }

  @override
  void dispose() {
    _waiting?.cancel();
    _pin.dispose();
    super.dispose();
  }

  /// Counts the wait down on the screen, second by second.
  Future<void> _readWait() async {
    final left = await widget.lock.retryIn();
    if (!mounted) return;
    _waiting?.cancel();
    setState(() => _wait = (left.inMilliseconds / 1000).ceil());
    if (_wait == 0) return;
    _waiting = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() {
        _wait--;
        if (_wait <= 0) {
          _wait = 0;
          _error = null;
        }
      });
      if (_wait == 0) t.cancel();
    });
  }

  Future<void> _biometrics() async {
    if (!await widget.lock.biometrics || !mounted) return;
    setState(() => _biometricsAllowed = true);
    final l10n = context.l10n;
    final auth = widget.auth ?? LocalAuthentication();
    try {
      final ok = await auth.authenticate(
        localizedReason: l10n.appLockUnlockReason(appName),
        persistAcrossBackgrounding: true,
      );
      if (ok && mounted) widget.onUnlocked();
    } on Object {
      // The PIN is always there as the way in.
      if (mounted) {
        setState(() => _error = l10n.appLockBiometricsUnavailable);
      }
    }
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    final ok = await widget.lock.check(_pin.text);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _error = ok ? null : context.l10n.appLockWrongPin;
      // A wrong PIN is typed again from the start, as in the official app. The field is
      // made anew for that: the keyboard keeps the digits of a field that is only
      // cleared, and would send them again in front of the next ones.
      _pin.clear();
      if (!ok) _attempt++;
    });
    if (ok) {
      widget.onUnlocked();
    } else {
      await _readWait();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 48),
              const SizedBox(height: 16),
              Text(
                widget.title ?? l10n.appLockLocked(appName),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextField(
                key: ValueKey(_attempt),
                controller: _pin,
                autofocus: true,
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: _pinDigits,
                maxLength: _pinMaxLength,
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  labelText: l10n.appLockPin,
                  errorText: _wait > 0
                      ? l10n.appLockTooManyTries(_wait)
                      : _error,
                  errorMaxLines: 2,
                  border: const OutlineInputBorder(),
                ),
                // The keyboard's own key checks the PIN and leaves the field in focus: a
                // wrong PIN is typed again without another tap.
                onEditingComplete: () {
                  if (_wait == 0 && !_checking) unawaited(_check());
                },
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _checking || _wait > 0
                    ? null
                    : () => unawaited(_check()),
                child: Text(l10n.appLockUnlock),
              ),
              if (_biometricsAllowed)
                TextButton(
                  onPressed: () => unawaited(_biometrics()),
                  child: Text(l10n.appLockUseBiometrics),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The lock's own settings: set or change the PIN, the timeout, and the device check.
class AppLockScreen extends StatefulWidget {
  const AppLockScreen({super.key, this.lock, this.auth});
  final AppLock? lock;
  final LocalAuthentication? auth;

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  AppLock get _lock => widget.lock ?? const AppLock();
  final _pin = TextEditingController();
  final _again = TextEditingController();
  bool _hasPin = false;
  int _timeout = AppLock.defaultTimeout;
  bool _biometrics = false;
  bool _showContent = false;
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
    final timeout = (await _lock.timeout).inSeconds;
    final biometrics = await _lock.biometrics;
    final showContent = await _lock.showContent;
    if (!mounted) return;
    setState(() {
      _hasPin = has;
      _timeout = timeout;
      _biometrics = biometrics;
      _showContent = showContent;
      if (first) _needsPin = has;
    });
  }

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.appLockRemoveTitle),
        content: Text(context.l10n.appLockRemoveMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.commonCancel),
          ),
          DestructiveButton(
            onPressed: () => Navigator.pop(context, true),
            label: context.l10n.commonRemove,
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _lock.remove();
    await _read();
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    if (_pin.text.length < 4) {
      setState(() => _error = l10n.appLockTooShort);
      return;
    }
    if (_pin.text != _again.text) {
      setState(() => _error = l10n.appLockMismatch);
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
        content: Text(replaced ? l10n.appLockPinReplaced : l10n.appLockPinSet),
      ),
    );
    await _read();
  }

  static String _timeoutLabel(AppLocalizations l10n, int seconds) =>
      switch (seconds) {
        0 => l10n.appLockTimeoutAtOnce,
        60 => l10n.appLockTimeoutMinute,
        300 => l10n.appLockTimeoutFiveMinutes,
        _ => l10n.appLockTimeoutHour,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final needsPin = _needsPin;
    if (needsPin == null) {
      return Scaffold(appBar: AppBar(title: Text(l10n.appLockTitle)));
    }
    if (needsPin) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.appLockTitle)),
        body: LockScreen(
          lock: _lock,
          auth: widget.auth,
          title: l10n.appLockEnterPinToChange,
          onUnlocked: () => setState(() => _needsPin = false),
        ),
      );
    }
    return _settings(context);
  }

  Widget _settings(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.appLockTitle)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _hasPin ? l10n.appLockIntroWithPin : l10n.appLockIntroNoPin,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _pin,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: _pinDigits,
              maxLength: _pinMaxLength,
              decoration: InputDecoration(
                labelText: _hasPin ? l10n.appLockNewPin : l10n.appLockPin,
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
              inputFormatters: _pinDigits,
              maxLength: _pinMaxLength,
              decoration: InputDecoration(labelText: l10n.appLockPinAgain),
              onSubmitted: (_) => unawaited(_save()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                FilledButton(
                  onPressed: () => unawaited(_save()),
                  child: Text(
                    _hasPin ? l10n.appLockReplacePin : l10n.appLockSetPin,
                  ),
                ),
                const SizedBox(width: 12),
                if (_hasPin)
                  TextButton(
                    onPressed: () => unawaited(_remove()),
                    child: Text(l10n.appLockRemove),
                  ),
              ],
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(l10n.appLockAskAgain),
          ),
          RadioGroup<int>(
            groupValue: _timeout,
            // Nothing to time out before there is a PIN.
            onChanged: (v) {
              if (!_hasPin) return;
              final seconds = v ?? AppLock.defaultTimeout;
              setState(() => _timeout = seconds);
              unawaited(_lock.setTimeout(seconds));
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final t in AppLock.timeouts)
                  RadioListTile<int>(
                    value: t,
                    enabled: _hasPin,
                    title: Text(_timeoutLabel(l10n, t)),
                  ),
              ],
            ),
          ),
          const Divider(),
          SwitchListTile(
            value: _biometrics,
            title: Text(l10n.appLockBiometrics),
            subtitle: Text(l10n.appLockBiometricsSubtitle),
            onChanged: _hasPin
                ? (v) {
                    setState(() => _biometrics = v);
                    unawaited(_lock.setBiometrics(v));
                  }
                : null,
          ),
          SwitchListTile(
            value: _showContent,
            title: Text(l10n.appLockShowContent),
            subtitle: Text(l10n.appLockShowContentSubtitle),
            onChanged: _hasPin
                ? (v) {
                    setState(() => _showContent = v);
                    unawaited(_lock.setShowContent(v));
                  }
                : null,
          ),
        ],
      ),
    );
  }
}
