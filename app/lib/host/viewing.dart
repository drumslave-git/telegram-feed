import 'package:flutter/foundation.dart';

/// The channels of the timeline that is on screen: a feed's sources, or the one channel
/// of a channel's timeline. A post that matches a rule there does not pop up over the
/// timeline it has just appeared in; it only sounds, as the official app does for the
/// chat that is open. Empty while no timeline is in front.
abstract final class Viewing {
  static final chats = ValueNotifier<Set<int>>(const {});

  /// The timelines that say they are in front, the last one on top.
  static final _shown = <Object, Set<int>>{};

  /// [owner]'s timeline is in front and reads [chatIds].
  static void show(Object owner, Iterable<int> chatIds) {
    _shown
      ..remove(owner)
      ..[owner] = {...chatIds};
    _publish();
  }

  /// [owner]'s timeline is covered or gone.
  static void hide(Object owner) {
    if (_shown.remove(owner) != null) _publish();
  }

  static void _publish() {
    final now = _shown.isEmpty ? const <int>{} : _shown.values.last;
    if (!setEquals(now, chats.value)) chats.value = now;
  }
}
