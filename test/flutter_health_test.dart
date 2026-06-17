import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_health/flutter_health.dart';
import 'package:flutter_health/flutter_health_platform_interface.dart';
import 'package:flutter_health/flutter_health_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterHealthPlatform
    with MockPlatformInterfaceMixin
    implements FlutterHealthPlatform {
  @override
  Future<bool> isAvailable() => Future.value(true);

  @override
  Future<bool> connect() => Future.value(true);

  @override
  Future<void> disconnect() => Future.value();

  @override
  Future<bool> isPermissionGranted() => Future.value(true);

  @override
  Future<bool> requestPermission() => Future.value(true);

  @override
  Future<List<HealthRecord>> queryHeartRate(DateTime since, DateTime to) =>
      Future.value([]);

  @override
  Future<List<HealthRecord>> querySteps(DateTime since, DateTime to) =>
      Future.value([]);

  @override
  Future<List<HealthRecord>> queryDistance(DateTime since, DateTime to) =>
      Future.value([]);

  @override
  Future<List<HealthRecord>> queryCalories(DateTime since, DateTime to) =>
      Future.value([]);

  @override
  Future<List<HealthRecord>> queryStepsDaily(DateTime date) => Future.value([]);

  @override
  Future<List<HealthRecord>> queryEndedSleepSessions(
          DateTime since, DateTime to) =>
      Future.value([]);

  @override
  Future<List<HealthRecord>> queryEndedExerciseSessions(
          DateTime since, DateTime to) =>
      Future.value([]);

  @override
  Future<HealthRecord?> queryHourlySummary(
          DateTime hourStart, DateTime hourEnd) =>
      Future.value(null);

  @override
  Future<HealthRecord?> queryDailySummary(DateTime date) =>
      Future.value(null);

  @override
  Future<List<HealthRecord>> queryWeights(DateTime since, DateTime to) =>
      Future.value([]);

  @override
  Future<List<HealthRecord>> queryBloodGlucose(DateTime since, DateTime to) =>
      Future.value([]);

  @override
  Future<List<HealthRecord>> queryBloodPressure(DateTime since, DateTime to) =>
      Future.value([]);

  @override
  Future<List<HealthRecord>> queryInsulinDelivery(DateTime since, DateTime to) =>
      Future.value([]);

  @override
  Future<List<HealthRecord>> queryNutrition(DateTime since, DateTime to) =>
      Future.value([]);

  @override
  Future<List<HealthRecord>> queryWaterIntake(DateTime since, DateTime to) =>
      Future.value([]);

  @override
  Future<List<HealthRecord>> queryStepSegments(DateTime since, DateTime to) =>
      Future.value([]);

  @override
  Future<List<HealthRecord>> queryHeight(DateTime since, DateTime to) =>
      Future.value([]);

  @override
  Future<List<HealthRecord>> queryMedication(DateTime since, DateTime to) =>
      Future.value([]);
}

void main() {
  final FlutterHealthPlatform initialPlatform = FlutterHealthPlatform.instance;

  test('$MethodChannelFlutterHealth is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFlutterHealth>());
  });

  test('isAvailable delegates to platform', () async {
    final plugin = FlutterHealth();
    FlutterHealthPlatform.instance = MockFlutterHealthPlatform();
    expect(await plugin.isAvailable(), true);
  });
}
