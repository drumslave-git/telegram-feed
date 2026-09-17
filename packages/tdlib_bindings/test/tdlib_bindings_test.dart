import 'package:tdlib_bindings/tdlib_bindings.dart';
import 'package:test/test.dart';

void main() {
  test('package is wired into the workspace', () {
    expect(packageName, 'tdlib_bindings');
  });
}
