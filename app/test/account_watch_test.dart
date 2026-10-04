import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/service/account_watch.dart';

void main() {
  test('the core serves every other account that has logged in, and none that '
      'has not', () async {
    final dir = Directory.systemTemp.createTempSync('account_watch');
    addTearDown(() => dir.deleteSync(recursive: true));
    final support = dir.path.replaceAll(r'\\', '/');
    File('$support/accounts.json').writeAsStringSync(
      jsonEncode({
        'active': 2,
        'accounts': [
          {'id': 1, 'name': 'Ann', 'loggedIn': true},
          {'id': 2, 'name': 'Bob', 'loggedIn': true},
          // Added, and never logged in.
          {'id': 3, 'loggedIn': false},
          // Kept by an older build, which did not say.
          {'id': 4, 'name': 'Old'},
        ],
      }),
    );
    final others = await otherAccountsToServe(support);
    expect(others.map((o) => o.id), [1]);
    expect(others.single.databaseDirectory, '$support/tdlib');
    expect(others.single.filesDirectory, '$support/tdlib/files');
    expect(others.single.appDatabasePath, '$support/app.sqlite');
  });

  test('with one account there is nothing beside it', () async {
    final dir = Directory.systemTemp.createTempSync('account_watch');
    addTearDown(() => dir.deleteSync(recursive: true));
    expect(await otherAccountsToServe(dir.path), isEmpty);
  });
}
