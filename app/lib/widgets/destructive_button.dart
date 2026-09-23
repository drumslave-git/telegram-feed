import 'package:flutter/material.dart';

/// The confirming button of a dialog that deletes or removes something, in the error
/// colour, as the official app draws Delete and Remove.
class DestructiveButton extends StatelessWidget {
  const DestructiveButton({
    super.key,
    required this.label,
    required this.onPressed,
  });
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // A text button in the error colour: what Material dialogs and the official app use
    // for Delete and Remove, next to a plain Cancel.
    return TextButton(
      style: TextButton.styleFrom(foregroundColor: scheme.error),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}
