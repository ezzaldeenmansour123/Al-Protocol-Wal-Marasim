// Flutter-side wrapper for the pure-Dart model-catalog checks (P6).
//
// Runs the same main() from model_catalog_test.dart inside a real
// flutter_test test case, so `flutter test` reports pass/fail in CI.
// The pure script itself stays flutter_test-free so it can run with
// plain `dart test/model_catalog_test.dart` on a machine without the
// Flutter SDK.
import 'package:flutter_test/flutter_test.dart';

import 'model_catalog_test.dart' as catalog_test;

void main() {
  test('model catalog (pure Dart checks)', () {
    catalog_test.main();
  });
}
