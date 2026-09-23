import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'dart:async';

import '../app_name.dart';
import '../host/accounts.dart';
import '../service/core_service.dart' show appPaths;
import '../widgets/error_state.dart';

/// Shows the screen for the current [AuthState] and [child] once logged in.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.gateway, required this.child});
  final TelegramGateway gateway;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: gateway.authState,
      builder: (context, snap) {
        final state = snap.data ?? const AuthStarting();
        return switch (state) {
          AuthReady() => child,
          AuthWaitPhoneNumber() => PhoneScreen(gateway: gateway),
          AuthWaitOtherDeviceConfirmation(:final link) => QrScreen(
            gateway: gateway,
            link: link,
          ),
          AuthWaitCode(:final phoneNumber, :final codeLength) => CodeScreen(
            gateway: gateway,
            phoneNumber: phoneNumber,
            codeLength: codeLength,
          ),
          AuthWaitPassword(:final hint) => PasswordScreen(
            gateway: gateway,
            hint: hint,
          ),
          AuthWaitRegistration() => RegistrationScreen(gateway: gateway),
          AuthStarting() ||
          AuthLoggingOut() ||
          AuthClosed() => const _Waiting(),
        };
      },
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

/// One text field, one action, errors from Telegram shown inline.
class _StepForm extends StatefulWidget {
  const _StepForm({
    required this.title,
    required this.explanation,
    required this.label,
    required this.action,
    required this.onSubmit,
    this.keyboardType = TextInputType.text,
    this.obscure = false,
    this.maxLength,
    this.hint,
    this.initialValue,
    this.footnote,
    this.secondaryLabel,
    this.secondaryIcon,
    this.onSecondary,
    this.tertiaryLabel,
    this.tertiaryIcon,
    this.onTertiary,
  });
  final String title;
  final String explanation;
  final String label;
  final String action;
  final Future<void> Function(String value) onSubmit;
  final TextInputType keyboardType;
  final bool obscure;
  final int? maxLength;

  /// An example of what to type, e.g. a phone number in international format.
  final String? hint;

  /// What the field starts with, e.g. the "+" every phone number begins with.
  final String? initialValue;

  /// A quiet line under the buttons, e.g. where something else has to be done.
  final String? footnote;

  /// Optional second action (e.g. "log in with QR"), run with the same error handling.
  final String? secondaryLabel;
  final IconData? secondaryIcon;
  final Future<void> Function()? onSecondary;

  /// A third action beside the second one (e.g. "Resend code").
  final String? tertiaryLabel;
  final IconData? tertiaryIcon;
  final Future<void> Function()? onTertiary;

  @override
  State<_StepForm> createState() => _StepFormState();
}

class _StepFormState extends State<_StepForm> {
  late final _ctl = TextEditingController(text: widget.initialValue ?? '');
  String? _error;
  bool _busy = false;
  late bool _hidden = widget.obscure;
  String? _note;

  Future<void> _submit() async {
    final value = _ctl.text.trim();
    if (value.isEmpty) return;
    await _guard(() => widget.onSubmit(value));
  }

  Future<void> _guard(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on TelegramException catch (e) {
      setState(
        () => _error = telegramErrorLine(e, what: 'Telegram refused that.'),
      );
    } catch (e) {
      debugPrint('login: $e');
      setState(() => _error = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      // Scrolls, so the keyboard never pushes the buttons off a small screen.
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(widget.explanation),
          const SizedBox(height: 16),
          TextField(
            controller: _ctl,
            autofocus: true,
            enabled: !_busy,
            keyboardType: widget.keyboardType,
            obscureText: _hidden,
            maxLength: widget.maxLength,
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: widget.hint,
              errorText: _error,
              // A password typed on a phone is worth being able to look at.
              suffixIcon: !widget.obscure
                  ? null
                  : IconButton(
                      tooltip: _hidden ? 'Show' : 'Hide',
                      icon: Icon(
                        _hidden
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () => setState(() => _hidden = !_hidden),
                    ),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _submit,
            // Telegram can take a few seconds; the button shows it is working.
            child: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(widget.action),
          ),
          if (widget.onTertiary != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      await _guard(widget.onTertiary!);
                      if (mounted && _error == null) {
                        setState(() => _note = 'A new code is on its way.');
                      }
                    },
              icon: Icon(widget.tertiaryIcon),
              label: Text(widget.tertiaryLabel ?? ''),
            ),
          ],
          if (widget.onSecondary != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _guard(widget.onSecondary!),
              icon: Icon(widget.secondaryIcon),
              label: Text(widget.secondaryLabel ?? ''),
            ),
          ],
          if (_note != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _note!,
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            ),
          const OtherAccountButton(),
          if (widget.footnote != null)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Text(
                widget.footnote!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class PhoneScreen extends StatelessWidget {
  const PhoneScreen({super.key, required this.gateway});
  final TelegramGateway gateway;

  @override
  Widget build(BuildContext context) {
    return _StepForm(
      title: 'Log in to Telegram',
      explanation:
          '$appName reads the channels your Telegram account has joined. '
          'Enter the phone number of that account in international format.',
      label: 'Phone number',
      action: 'Send code',
      keyboardType: TextInputType.phone,
      hint: '+44 7700 900123',
      initialValue: '+',
      onSubmit: gateway.setPhoneNumber,
      secondaryLabel: 'Log in with QR code instead',
      secondaryIcon: Icons.qr_code,
      onSecondary: gateway.requestQrCode,
    );
  }
}

class CodeScreen extends StatelessWidget {
  const CodeScreen({
    super.key,
    required this.gateway,
    required this.phoneNumber,
    required this.codeLength,
  });
  final TelegramGateway gateway;
  final String phoneNumber;
  final int codeLength;

  @override
  Widget build(BuildContext context) {
    return _StepForm(
      title: 'Enter the code',
      explanation:
          'Telegram sent a code to $phoneNumber (by SMS or to another logged-in device).',
      label: 'Code',
      action: 'Continue',
      keyboardType: TextInputType.number,
      maxLength: codeLength > 0 ? codeLength : null,
      onSubmit: gateway.checkCode,
      // A code that never arrived: ask for it again without starting over.
      tertiaryLabel: 'Resend code',
      tertiaryIcon: Icons.refresh,
      onTertiary: gateway.resendCode,
      // A mistyped number, or a code that never came: back to the number, as the
      // official app's "Wrong number?".
      secondaryLabel: 'Change number',
      secondaryIcon: Icons.edit_outlined,
      onSecondary: gateway.logOut,
    );
  }
}

class PasswordScreen extends StatelessWidget {
  const PasswordScreen({super.key, required this.gateway, required this.hint});
  final TelegramGateway gateway;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return _StepForm(
      title: 'Two-step verification',
      explanation: hint.isEmpty
          ? 'Your account has a cloud password.'
          : 'Your account has a cloud password. Hint: $hint',
      label: 'Password',
      action: 'Continue',
      obscure: true,
      // Resetting it is part of two-step verification, which stays in the official app.
      footnote:
          'Forgotten it? A cloud password can only be reset in the official Telegram '
          'app, under Settings, Privacy and Security.',
      onSubmit: gateway.checkPassword,
    );
  }
}

class RegistrationScreen extends StatelessWidget {
  const RegistrationScreen({super.key, required this.gateway});
  final TelegramGateway gateway;

  @override
  Widget build(BuildContext context) {
    return _StepForm(
      title: 'New account',
      explanation: 'This number has no Telegram account yet. Enter a first name to create one.',
      label: 'First name',
      action: 'Create account',
      onSubmit: (name) => gateway.registerUser(firstName: name),
    );
  }
}

class QrScreen extends StatelessWidget {
  const QrScreen({super.key, required this.gateway, required this.link});
  final TelegramGateway gateway;
  final String link;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Log in with QR code')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Text(
              'In Telegram on your phone open Settings, Devices, Link Desktop Device, '
              'and scan this code. It refreshes automatically.',
            ),
            const SizedBox(height: 24),
            Center(
              child: QrImageView(
                data: link,
                size: 240,
                backgroundColor: Colors.white,
              ),
            ),
            const Spacer(),
            const OtherAccountButton(),
            TextButton(
              onPressed: () {
                final messenger = ScaffoldMessenger.of(context);
                gateway.logOut().catchError((Object e) {
                  showTelegramError(
                    messenger,
                    e,
                    what: 'Could not go back to the phone number.',
                  );
                });
              },
              child: const Text('Use a phone number instead'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A way back to an account that is already logged in. Adding an account switches the
/// app to a fresh one at once, and without this the login screen would be a room with no
/// door: Settings is unreachable from here.
class OtherAccountButton extends StatefulWidget {
  const OtherAccountButton({super.key});

  @override
  State<OtherAccountButton> createState() => _OtherAccountButtonState();
}

class _OtherAccountButtonState extends State<OtherAccountButton> {
  AccountInfo? _other;
  AccountStore? _store;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final store = AccountStore((await appPaths()).support);
      final now = await store.load();
      final other = now.accounts
          .where((a) => a.id != now.active && a.label.isNotEmpty)
          .firstOrNull;
      if (mounted) {
        setState(() {
          _store = store;
          _other = other;
        });
      }
    } on Object {
      // No paths (tests, desktop): no other account to offer.
    }
  }

  Future<void> _use(AccountInfo other) async {
    final switched = AccountSwitch.of(context)?.onSwitched;
    if (switched == null) return;
    setState(() => _busy = true);
    await _store!.setActive(other.id);
    await switched();
  }

  @override
  Widget build(BuildContext context) {
    final other = _other;
    if (other == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: TextButton.icon(
        onPressed: _busy ? null : () => unawaited(_use(other)),
        icon: const Icon(Icons.switch_account_outlined),
        label: Text('Use ${other.label} instead'),
      ),
    );
  }
}
