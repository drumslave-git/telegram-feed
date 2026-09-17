import 'package:app_db/app_db.dart';
import 'package:test/test.dart';

void main() {
  test('package is wired into the workspace', () {
    expect(packageName, 'app_db');
  });
}
