import 'package:flutter/material.dart';

/// One row of a popup menu: an icon and a label, the destructive one in the error colour.
/// Every menu in the app is built from it, so they all read and look the same.
PopupMenuItem<T> menuItem<T>(
  T value,
  IconData icon,
  String label, {
  bool danger = false,
  bool enabled = true,
}) => PopupMenuItem<T>(
  value: value,
  enabled: enabled,
  child: Builder(
    builder: (context) {
      final color = danger ? Theme.of(context).colorScheme.error : null;
      return ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: color),
        title: Text(label, style: TextStyle(color: color)),
      );
    },
  ),
);
