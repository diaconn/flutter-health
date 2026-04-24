// Integration tests run on a real device with a host app.
// These tests verify the plugin is reachable and returns sensible types.
// Health data access requires a real device with permissions granted.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_health/flutter_health.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final plugin = FlutterHealth();

  testWidgets('isAvailable returns bool', (tester) async {
    final result = await plugin.isAvailable();
    expect(result, isA<bool>());
  });

  testWidgets('connect returns bool', (tester) async {
    final result = await plugin.connect();
    expect(result, isA<bool>());
  });
}
