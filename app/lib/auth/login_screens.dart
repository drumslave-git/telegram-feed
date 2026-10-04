import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'dart:async';

import '../app_name.dart';
import '../host/accounts.dart';
import '../l10n/l10n.dart';
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
          AuthWaitEmailAddress() => EmailScreen(gateway: gateway),
          AuthWaitEmailCode(:final emailPattern, :final codeLength) =>
            EmailCodeScreen(
              gateway: gateway,
              emailPattern: emailPattern,
              codeLength: codeLength,
            ),
          AuthUnsupported() => UnsupportedLoginScreen(gateway: gateway),
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
    final l10n = context.l10n;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on TelegramException catch (e) {
      setState(
        () => _error = telegramErrorLine(
          e,
          what: l10n.loginTelegramRefused,
          l10n: l10n,
        ),
      );
    } catch (e) {
      debugPrint('login: $e');
      setState(() => _error = l10n.loginSomethingWentWrong);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
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
                      tooltip: _hidden
                          ? l10n.loginShowPassword
                          : l10n.loginHidePassword,
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
                        setState(() => _note = l10n.loginNewCodeSent);
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
    final l10n = context.l10n;
    return _StepForm(
      title: l10n.loginPhoneTitle,
      explanation: l10n.loginPhoneExplanation(appName),
      label: l10n.loginPhoneNumber,
      action: l10n.loginSendCode,
      keyboardType: TextInputType.phone,
      hint: '+44 7700 900123',
      initialValue: '+',
      onSubmit: gateway.setPhoneNumber,
      secondaryLabel: l10n.loginWithQrInstead,
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
    final l10n = context.l10n;
    return _StepForm(
      title: l10n.loginCodeTitle,
      explanation: l10n.loginCodeExplanation(phoneNumber),
      label: l10n.loginCode,
      action: l10n.commonContinue,
      keyboardType: TextInputType.number,
      maxLength: codeLength > 0 ? codeLength : null,
      onSubmit: gateway.checkCode,
      // A code that never arrived: ask for it again without starting over.
      tertiaryLabel: l10n.loginResendCode,
      tertiaryIcon: Icons.refresh,
      onTertiary: gateway.resendCode,
      // A mistyped number, or a code that never came: back to the number, as the
      // official app's "Wrong number?".
      secondaryLabel: l10n.loginChangeNumber,
      secondaryIcon: Icons.edit_outlined,
      onSecondary: gateway.logOut,
    );
  }
}

/// Telegram asks some accounts for an email address, where their login codes go from
/// then on.
class EmailScreen extends StatelessWidget {
  const EmailScreen({super.key, required this.gateway});
  final TelegramGateway gateway;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _StepForm(
      title: l10n.loginEmailTitle,
      explanation: l10n.loginEmailExplanation,
      label: l10n.loginEmail,
      action: l10n.commonContinue,
      keyboardType: TextInputType.emailAddress,
      onSubmit: gateway.setEmailAddress,
      secondaryLabel: l10n.loginChangeNumber,
      secondaryIcon: Icons.edit_outlined,
      onSecondary: gateway.logOut,
    );
  }
}

/// The login code went to the account's email address.
class EmailCodeScreen extends StatelessWidget {
  const EmailCodeScreen({
    super.key,
    required this.gateway,
    required this.emailPattern,
    required this.codeLength,
  });
  final TelegramGateway gateway;
  final String emailPattern;
  final int codeLength;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _StepForm(
      title: l10n.loginEmailCodeTitle,
      explanation: l10n.loginEmailCodeExplanation(emailPattern),
      label: l10n.loginCode,
      action: l10n.commonContinue,
      keyboardType: TextInputType.number,
      maxLength: codeLength > 0 ? codeLength : null,
      onSubmit: gateway.checkEmailCode,
      secondaryLabel: l10n.loginChangeNumber,
      secondaryIcon: Icons.edit_outlined,
      onSecondary: gateway.logOut,
    );
  }
}

/// A step the app cannot do: Telegram asks for a Premium purchase before this login goes
/// on. The way out is another number, or the official app.
class UnsupportedLoginScreen extends StatelessWidget {
  const UnsupportedLoginScreen({super.key, required this.gateway});
  final TelegramGateway gateway;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.loginPhoneTitle)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.loginUnsupportedExplanation),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => unawaited(gateway.logOut()),
              icon: const Icon(Icons.edit_outlined),
              label: Text(l10n.loginChangeNumber),
            ),
          ],
        ),
      ),
    );
  }
}

class PasswordScreen extends StatelessWidget {
  const PasswordScreen({super.key, required this.gateway, required this.hint});
  final TelegramGateway gateway;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _StepForm(
      title: l10n.loginPasswordTitle,
      explanation: hint.isEmpty
          ? l10n.loginPasswordExplanation
          : l10n.loginPasswordExplanationWithHint(hint),
      label: l10n.loginPassword,
      action: l10n.commonContinue,
      obscure: true,
      // Resetting it is part of two-step verification, which stays in the official app.
      footnote: l10n.loginPasswordForgotten,
      onSubmit: gateway.checkPassword,
    );
  }
}

class RegistrationScreen extends StatelessWidget {
  const RegistrationScreen({super.key, required this.gateway});
  final TelegramGateway gateway;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _StepForm(
      title: l10n.loginNewAccountTitle,
      explanation: l10n.loginNewAccountExplanation,
      label: l10n.loginFirstName,
      action: l10n.loginCreateAccount,
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
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.loginQrTitle)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(l10n.loginQrExplanation),
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
                  showTelegramError(messenger, e, what: l10n.loginQrBackFailed);
                });
              },
              child: Text(l10n.loginWithPhoneInstead),
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
      // One that is logged in, as far as is known: an account that was added and never
      // logged in is no way back.
      final other = now.accounts
          .where((a) => a.id != now.active && a.loggedIn != false)
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
    final store = _store!;
    await store.setActive(other.id);
    await switched();
    // The account this login was for never logged in: it leaves nothing behind. Only
    // now, when its core is down and no longer holds its files.
    await store.dropNeverLoggedIn();
    // Still here: the account gone back to has no session either. The button then
    // offers what is left to go to, which may be nothing.
    if (!mounted) return;
    setState(() {
      _busy = false;
      _other = null;
    });
    await _load();
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
        label: Text(
          context.l10n.loginUseOtherAccount(
            other.title.isEmpty
                ? context.l10n.accountsNumbered(other.id)
                : other.title,
          ),
        ),
      ),
    );
  }
}
