// Flutter-side wrapper for the pure-Dart provider-selector checks (P6).
//
// Runs the same main() from provider_selector_test.dart inside a real
// flutter_test test case, so `flutter test` reports pass/fail in CI.
// The pure script itself stays flutter_test-free so it can run with
// plain `dart test/provider_selector_test.dart` on a machine without
// the Flutter SDK.
import 'package:flutter_test/flutter_test.dart';

import 'provider_selector_test.dart' as selector_test;

void main() {
  test('provider selector (pure Dart checks)', () {
    selector_test.main();
  });
}
