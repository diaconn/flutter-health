import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_health_method_channel.dart';
import 'src/models/health_record.dart';

abstract class FlutterHealthPlatform extends PlatformInterface {
  FlutterHealthPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterHealthPlatform _instance = MethodChannelFlutterHealth();

  static FlutterHealthPlatform get instance => _instance;

  static set instance(FlutterHealthPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<bool> isAvailable() => throw UnimplementedError();
  Future<bool> connect() => throw UnimplementedError();
  Future<void> disconnect() => throw UnimplementedError();
  Future<bool> isPermissionGranted() => throw UnimplementedError();
  Future<bool> requestPermission() => throw UnimplementedError();
  Future<HealthRecord?> queryMetric(DateTime from, DateTime to) => throw UnimplementedError();
  Future<List<HealthRecord>> queryEndedSleepSessions(DateTime since, DateTime to) => throw UnimplementedError();
  Future<List<HealthRecord>> queryEndedExerciseSessions(DateTime since, DateTime to) => throw UnimplementedError();
  Future<HealthRecord?> queryHourlySummary(DateTime hourStart, DateTime hourEnd) => throw UnimplementedError();
  Future<HealthRecord?> queryDailySummary(DateTime date) => throw UnimplementedError();
  Future<List<HealthRecord>> queryWeights(DateTime since, DateTime to) => throw UnimplementedError();
  Future<List<HealthRecord>> queryBloodGlucose(DateTime since, DateTime to) => throw UnimplementedError();
  Future<List<HealthRecord>> queryBloodPressure(DateTime since, DateTime to) => throw UnimplementedError();
  /// iOS 전용. `HKQuantityTypeIdentifierInsulinDelivery` 샘플들을 양(IU) + basal/bolus reason 함께 반환.
  /// Android(Samsung) 는 SDK 에 reason 자체가 없어 항상 빈 리스트.
  Future<List<HealthRecord>> queryInsulinDelivery(DateTime since, DateTime to) => throw UnimplementedError();
  Future<List<HealthRecord>> queryNutrition(DateTime since, DateTime to) => throw UnimplementedError();
  Future<List<HealthRecord>> queryWaterIntake(DateTime since, DateTime to) => throw UnimplementedError();
  Future<List<HealthRecord>> queryFloorsClimbed(DateTime since, DateTime to) => throw UnimplementedError();
  Future<List<HealthRecord>> queryBodyTemperature(DateTime since, DateTime to) => throw UnimplementedError();
  /// iOS 전용. 개별 걸음 샘플(stepCount)을 시작/종료/걸음수로 반환. Android 는 빈 리스트.
  Future<List<HealthRecord>> queryStepSegments(DateTime since, DateTime to) => throw UnimplementedError();
  Future<List<HealthRecord>> queryMedication(DateTime since, DateTime to) => throw UnimplementedError();
}
