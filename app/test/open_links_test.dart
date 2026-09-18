import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/feeds/open_links.dart';

void main() {
  test('falls through to the next link when a scheme has no handler', () async {
    final tried = <String>[];
    final ok = await launchFirst(
      [
        Uri.parse('tg://privatepost?channel=1&post=2'),
        null,
        Uri.parse('https://t.me/c/1/2'),
      ],
      launch: (u) async {
        tried.add(u.scheme);
        if (u.scheme == 'tg') {
          throw PlatformException(code: 'ACTIVITY_NOT_FOUND');
        }
        return true;
      },
    );
    expect(ok, isTrue);
    expect(tried, ['tg', 'https']);
  });

  test('reports false when nothing opens', () async {
    expect(
      await launchFirst([Uri.parse('tg://x')], launch: (_) async => false),
      isFalse,
    );
  });
}
