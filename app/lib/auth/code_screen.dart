import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../l10n/l10n.dart';
import '../widgets/error_state.dart';
import 'login_screens.dart' show OtherAccountButton;

/// The login code, as in the official app: one box per digit, sent as soon as the last
/// one is typed, and a countdown until Telegram lets the code be asked for again.
class CodeScreen extends StatefulWidget {
  const CodeScreen({
    super.key,
    required this.gateway,
    required this.phoneNumber,
    required this.codeLength,
    this.resendAfter = 0,
    this.canResend = true,
    this.now = DateTime.now,
  });
  final TelegramGateway gateway;
  final String phoneNumber;

  /// How many digits the code has; 0 when Telegram did not say, and then the code is
  /// typed into one field and sent with a button.
  final int codeLength;

  /// Seconds before the code can be asked for again.
  final int resendAfter;

  /// Whether Telegram has another way to send the code.
  final bool canResend;

  /// The clock; tests hand in their own.
  final DateTime Function() now;

  @override
  State<CodeScreen> createState() => _CodeScreenState();
}

class _CodeScreenState extends State<CodeScreen> {
  final _code = TextEditingController();
  final _focus = FocusNode();
  String? _error;
  String? _note;
  bool _busy = false;

  /// When the code may be asked for again.
  late DateTime _resendAt;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _startCountdown();
    _focus.addListener(_repaint);
  }

  @override
  void didUpdateWidget(CodeScreen old) {
    super.didUpdateWidget(old);
    // Telegram sent the code again, or sends it another way: the wait starts over.
    if (!identical(old, widget) &&
        (old.resendAfter != widget.resendAfter ||
            old.phoneNumber != widget.phoneNumber ||
            old.codeLength != widget.codeLength)) {
      _startCountdown();
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _focus
      ..removeListener(_repaint)
      ..dispose();
    _code.dispose();
    super.dispose();
  }

  void _repaint() {
    if (mounted) setState(() {});
  }

  void _startCountdown() {
    _resendAt = widget.now().add(Duration(seconds: widget.resendAfter));
    _tick?.cancel();
    if (widget.resendAfter <= 0) return;
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_left == Duration.zero) t.cancel();
      _repaint();
    });
  }

  /// How long the code cannot be asked for yet.
  Duration get _left {
    final left = _resendAt.difference(widget.now());
    return left.isNegative ? Duration.zero : left;
  }

  static String _clock(Duration d) {
    final seconds = (d.inMilliseconds / 1000).ceil();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  void _onChanged(String text) {
    setState(() {
      _error = null;
      _note = null;
    });
    if (widget.codeLength > 0 && text.length == widget.codeLength) {
      unawaited(_submit());
    }
  }

  Future<void> _submit() async {
    final code = _code.text.trim();
    if (code.isEmpty || _busy) return;
    final ok = await _guard(() => widget.gateway.checkCode(code));
    if (!ok && mounted) {
      // A wrong code is typed again from the first box.
      _code.clear();
      _focus.requestFocus();
    }
  }

  Future<bool> _guard(Future<void> Function() action) async {
    final l10n = context.l10n;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      return true;
    } on TelegramException catch (e) {
      if (mounted) {
        setState(
          () => _error = telegramErrorLine(
            e,
            what: l10n.loginTelegramRefused,
            l10n: l10n,
          ),
        );
      }
      return false;
    } on Object catch (e) {
      debugPrint('login: $e');
      if (mounted) setState(() => _error = l10n.loginSomethingWentWrong);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    final l10n = context.l10n;
    if (await _guard(widget.gateway.resendCode) && mounted) {
      setState(() => _note = l10n.loginNewCodeSent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final left = _left;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.loginCodeTitle)),
      // Scrolls, so the keyboard never pushes the buttons off a small screen.
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(l10n.loginCodeExplanation(widget.phoneNumber)),
          const SizedBox(height: 24),
          if (widget.codeLength > 0)
            _boxes(scheme)
          else ...[
            TextField(
              controller: _code,
              focusNode: _focus,
              autofocus: true,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: l10n.loginCode,
                border: const OutlineInputBorder(),
              ),
              onChanged: _onChanged,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(l10n.commonContinue),
            ),
          ],
          // A place of its own, so nothing below moves when the line comes or goes.
          SizedBox(
            height: 44,
            child: Center(
              child: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      _error ?? _note ?? '',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _error != null ? scheme.error : scheme.primary,
                      ),
                    ),
            ),
          ),
          if (widget.canResend)
            OutlinedButton.icon(
              // A code that never arrived: asked for again without starting over, once
              // Telegram allows it.
              onPressed: _busy || left > Duration.zero ? null : _resend,
              icon: const Icon(Icons.refresh),
              label: Text(
                left > Duration.zero
                    ? l10n.loginResendCodeIn(_clock(left))
                    : l10n.loginResendCode,
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            // A mistyped number: back to it, as the official app's "Wrong number?".
            onPressed: _busy ? null : () => _guard(widget.gateway.logOut),
            icon: const Icon(Icons.edit_outlined),
            label: Text(l10n.loginChangeNumber),
          ),
          const OtherAccountButton(),
        ],
      ),
    );
  }

  /// One box per digit. The field that takes the typing lies over them, unseen, so a
  /// tap anywhere on the boxes brings the keyboard and the code can be pasted.
  Widget _boxes(ColorScheme scheme) {
    final typed = _code.text;
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < widget.codeLength; i++)
                Container(
                  width: 44,
                  height: 56,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      width: _focus.hasFocus && i == typed.length ? 2 : 1,
                      color: _error != null
                          ? scheme.error
                          : _focus.hasFocus && i == typed.length
                          ? scheme.primary
                          : scheme.outline,
                    ),
                  ),
                  child: Text(
                    i < typed.length ? typed[i] : '',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
            ],
          ),
          Positioned.fill(
            child: Semantics(
              label: context.l10n.loginCode,
              child: TextField(
                controller: _code,
                focusNode: _focus,
                autofocus: true,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                maxLength: widget.codeLength,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                // The boxes show the digits.
                showCursor: false,
                enableInteractiveSelection: false,
                style: const TextStyle(color: Colors.transparent, fontSize: 1),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  counterText: '',
                ),
                onChanged: _onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
