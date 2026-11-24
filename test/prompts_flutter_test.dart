// Flutter-side wrapper for the pure-Dart RAG-prompt checks (P6).
//
// Runs the same main() from prompts_test.dart inside a real
// flutter_test test case, so `flutter test` reports pass/fail in CI.
// The pure script itself stays flutter_test-free so it can run with
// plain `dart test/prompts_test.dart` on a machine without the
// Flutter SDK.
import 'package:flutter_test/flutter_test.dart';

import 'prompts_test.dart' as prompts_test;

void main() {
  test('RAG prompts (pure Dart checks)', () {
    prompts_test.main();
  });
}
