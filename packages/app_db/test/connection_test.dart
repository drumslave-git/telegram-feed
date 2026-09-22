import 'dart:io';

import 'package:app_db/app_db.dart';
import 'package:test/test.dart';

void main() {
  test(
    'a write waits for another connection\'s write instead of failing',
    () async {
      final dir = await Directory.systemTemp.createTemp('app_db_lock');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/app.sqlite');
      final a = AppDatabase(appDatabaseFile(file, inBackground: true));
      final b = AppDatabase(appDatabaseFile(file, inBackground: true));
      addTearDown(() async {
        await a.close();
        await b.close();
      });
      await a.setSetting('warm', '1');
      await b.setting('warm');

      // A holds a write transaction for a while; B writes meanwhile.
      final holding = a.transaction(() async {
        await a.setSetting('a', '1');
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await b.setSetting('b', '2');
      await holding;
      expect(await a.setting('b'), '2');
      expect(await b.setting('a'), '1');
    },
  );
}
