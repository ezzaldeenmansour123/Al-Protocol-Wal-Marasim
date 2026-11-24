// Flutter-side wrapper for the pure-Dart refusal-guard checks.
//
// Runs the same main() from refusal_guard_test.dart inside a real
// flutter_test test case, so `flutter test` reports pass/fail in CI.
// The pure script itself stays flutter_test-free so it can run with
// plain `dart test/refusal_guard_test.dart` on a machine without the
// Flutter SDK.
import 'package:flutter_test/flutter_test.dart';

import 'refusal_guard_test.dart' as guard_test;

void main() {
  test('refusal guard (pure Dart checks)', () {
    guard_test.main();
  });
}
