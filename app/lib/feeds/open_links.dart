import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

Future<bool> _launchExternal(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

/// Launches the first of [uris] that some app accepts and reports whether one did.
///
/// url_launcher throws (`ACTIVITY_NOT_FOUND`) instead of returning false when nothing
/// handles a custom scheme, e.g. `tg://` without the Telegram app, so a failure moves on
/// to the next candidate (the `t.me` link in the browser).
Future<bool> launchFirst(
  Iterable<Uri?> uris, {
  Future<bool> Function(Uri uri) launch = _launchExternal,
}) async {
  for (final uri in uris) {
    if (uri == null) continue;
    try {
      if (await launch(uri)) return true;
    } on PlatformException {
      // try the next candidate
    }
  }
  return false;
}
