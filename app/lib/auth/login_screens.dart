import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../app_name.dart';

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
    this.secondaryLabel,
    this.secondaryIcon,
    this.onSecondary,
  });
  final String title;
  final String explanation;
  final String label;
  final String action;
  final Future<void> Function(String value) onSubmit;
  final TextInputType keyboardType;
  final bool obscure;
  final int? maxLength;

  /// Optional second action (e.g. "log in with QR"), run with the same error handling.
  final String? secondaryLabel;
  final IconData? secondaryIcon;
  final Future<void> Function()? onSecondary;

  @override
  State<_StepForm> createState() => _StepFormState();
}

class _StepFormState extends State<_StepForm> {
  final _ctl = TextEditingController();
  String? _error;
  bool _busy = false;

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
      setState(() => _error = _describe(e));
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
            obscureText: widget.obscure,
            maxLength: widget.maxLength,
            decoration: InputDecoration(
              labelText: widget.label,
              errorText: _error,
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
          if (widget.onSecondary != null) ...[
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _guard(widget.onSecondary!),
              icon: Icon(widget.secondaryIcon),
              label: Text(widget.secondaryLabel ?? ''),
            ),
          ],
        ],
      ),
    );
  }
}

String _describe(TelegramException e) => switch (e.message) {
  'PHONE_NUMBER_INVALID' => 'That phone number is not valid.',
  'PHONE_CODE_INVALID' => 'Wrong code.',
  'PHONE_CODE_EXPIRED' =>
    'The code expired. Change the number to get a new one.',
  'PASSWORD_HASH_INVALID' => 'Wrong password.',
  'API_ID_INVALID' =>
    'This build has no valid Telegram api_id/api_hash (see README).',
  final m when m.startsWith('Too Many Requests') =>
    'Too many attempts. Wait and retry.',
  final m => m,
};

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
            TextButton(
              onPressed: () {
                final messenger = ScaffoldMessenger.of(context);
                gateway.logOut().catchError((Object e) {
                  messenger.showSnackBar(SnackBar(content: Text('$e')));
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
