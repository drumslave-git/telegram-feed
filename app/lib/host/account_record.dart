import 'dart:async';

import 'package:flutter/material.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../service/core_service.dart' show appPaths;
import 'accounts.dart';

/// Stands around the home screen of a logged-in account and keeps the list of accounts
/// told about it ([AccountRecorder]): that it is logged in, its profile and photo, and
/// the count of unread channels the home screen hands to [builder]'s callback.
class AccountRecord extends StatefulWidget {
  const AccountRecord({
    super.key,
    required this.gateway,
    required this.builder,
    this.store,
  });
  final TelegramGateway gateway;

  /// The app's own lives beside the databases; tests pass theirs.
  final AccountStore? store;
  final Widget Function(BuildContext context, ValueChanged<int> onUnread)
  builder;

  @override
  State<AccountRecord> createState() => _AccountRecordState();
}

class _AccountRecordState extends State<AccountRecord> {
  AccountRecorder? _recorder;
  int? _unread;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    final AccountRecorder recorder;
    try {
      final store = widget.store ?? AccountStore((await appPaths()).support);
      recorder = AccountRecorder(store, await store.activeId());
      await recorder.loggedIn();
    } on Object {
      // No paths (widget tests, desktop): no list of accounts to keep.
      return;
    }
    _recorder = recorder;
    if (_unread case final n?) unawaited(recorder.unread(n));
    try {
      final me = await widget.gateway.me();
      String? photo;
      if (me.photo case final ref?) {
        try {
          photo = (await widget.gateway.download(ref)).localPath;
        } on TelegramException {
          // The row shows initials until the photo can be had.
        }
      }
      await recorder.profile(me, photoPath: photo);
    } on TelegramException {
      // The list keeps the profile it has.
    }
  }

  void _onUnread(int channels) {
    if (channels == _unread) return;
    _unread = channels;
    unawaited(_recorder?.unread(channels));
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _onUnread);
}
