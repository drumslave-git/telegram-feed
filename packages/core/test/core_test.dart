import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  test('package is wired into the workspace', () {
    expect(packageName, 'core');
  });
}
