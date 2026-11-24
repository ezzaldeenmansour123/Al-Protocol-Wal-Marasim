// Flutter-side wrapper for the pure-Dart retrieval-core checks.
//
// Runs the same main() from retrieval_core_test.dart inside a real
// flutter_test test case, so `flutter test` reports pass/fail in CI.
// The pure script itself stays flutter_test-free so it can run with
// plain `dart test/retrieval_core_test.dart` on a machine without the
// Flutter SDK.
import 'package:flutter_test/flutter_test.dart';

import 'retrieval_core_test.dart' as core_test;

void main() {
  test('retrieval core (pure Dart checks)', () {
    core_test.main();
  });
}
