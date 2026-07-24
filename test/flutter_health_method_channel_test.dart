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
        case 'queryHourlySummary':
        case 'queryDailySummary':
          return null;
        case 'queryHeartRate':
        case 'querySteps':
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

  test('queryHeartRate returns empty list when channel returns empty', () async {
    final result = await platform.queryHeartRate(
        DateTime.now().subtract(const Duration(minutes: 10)), DateTime.now());
    expect(result, isEmpty);
  });

}
