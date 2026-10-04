import 'dart:io';

import 'package:core/core.dart';
import 'package:core/native_isolate.dart';
import 'package:telegram_gateway/telegram_gateway.dart';
import 'package:test/test.dart';

/// One core isolate serves the account in use and the other logged-in accounts.
void main() {
  test('the core serves the other accounts beside the one in use, each with '
      'its own login, and lets one go', () async {
    final dir = Directory.systemTemp.createTempSync('core_accounts');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // The isolate may still hold a database file open.
      }
    });
    final at = dir.path.replaceAll(r'\', '/');
    final port = await spawnCoreIsolate(
      CoreBootstrap(
        apiId: 0,
        apiHash: '',
        databaseDirectory: '$at/tdlib',
        filesDirectory: '$at/tdlib/files',
        appDatabasePath: '$at/app.sqlite',
        // The fake account: no TDLib behind it.
        fakeMediaDirectory: at,
        others: [
          OtherAccount(
            id: 2,
            databaseDirectory: '$at/tdlib-2',
            filesDirectory: '$at/tdlib-2/files',
            appDatabasePath: '$at/app-2.sqlite',
          ),
        ],
      ),
    );
    final main = await CoreClient.connect(port);
    final ports = await main.otherAccounts();
    expect(ports.keys, [2]);

    // The other account logs in; the one in use is none the wiser.
    final other = await CoreClient.connect(ports[2]!);
    await other.setPhoneNumber('+15550001111');
    await other.checkCode('12345');
    expect(await other.authState.first, isA<AuthReady>());
    expect(await main.authState.first, isA<AuthWaitPhoneNumber>());
    expect(File('$at/tdlib-2/fake_session').existsSync(), isTrue);
    expect(File('$at/tdlib/fake_session').existsSync(), isFalse);
    expect(await other.myChannels(), isNotEmpty);

    // The account is removed from the device: the core lets it go first.
    await main.dropAccount(2);
    expect(await main.otherAccounts(), isEmpty);

    await other.close();
    await main.shutdown();
    await main.close();
  });
}
