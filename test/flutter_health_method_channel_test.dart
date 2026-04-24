import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_health/flutter_health_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final platform = MethodChannelFlutterHealth();
  const channel = MethodChannel('flutter_health');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      switch (call.method) {
        case 'isAvailable':
          return true;
        case 'connect':
          return true;
        case 'isPermissionGranted':
          return false;
        case 'requestPermission':
          return true;
        case 'queryMetric':
        case 'queryHourlySummary':
        case 'queryDailySummary':
          return null;
        case 'queryEndedSleepSessions':
        case 'queryEndedExerciseSessions':
          return [];
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('isAvailable returns true', () async {
    expect(await platform.isAvailable(), true);
  });

  test('connect returns true', () async {
    expect(await platform.connect(), true);
  });

  test('isPermissionGranted returns false', () async {
    expect(await platform.isPermissionGranted(), false);
  });

  test('queryMetric returns null when channel returns null', () async {
    final result = await platform.queryMetric(
        DateTime.now().subtract(const Duration(minutes: 5)), DateTime.now());
    expect(result, isNull);
  });

  test('queryEndedSleepSessions returns empty list', () async {
    final result = await platform.queryEndedSleepSessions(
        DateTime.now().subtract(const Duration(days: 1)), DateTime.now());
    expect(result, isEmpty);
  });
}
