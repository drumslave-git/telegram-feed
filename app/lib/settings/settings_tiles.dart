import 'package:flutter/material.dart';

/// The blue title over a group of settings, as the official app heads its sections.
class SettingsHeader extends StatelessWidget {
  const SettingsHeader(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}

/// The grey note under a group of settings, saying what they do.
class SettingsFooter extends StatelessWidget {
  const SettingsFooter(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}

/// One row of a settings list that leads to a screen of its own.
class SettingsLink extends StatelessWidget {
  const SettingsLink({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String? subtitle;

  /// The current state, on the right of the row (the official app's value cell).
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: subtitle == null
        ? null
        : Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis),
    trailing: value == null
        ? null
        : Text(
            value!,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: Theme.of(context).colorScheme.primary),
          ),
    onTap: onTap,
  );
}

/// Pushes [screen] over the current route.
Future<void> openSettingsScreen(BuildContext context, Widget screen) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
